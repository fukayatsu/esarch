require 'redis'
require 'twitter'
require 'slack'
require 'octokit'
require 'esa'
require 'net/http'
require 'sinatra'
require 'rack/contrib'

use Rack::JSONBodyParser, media: /json/

# Make it easy to check log on Papertrail addon
$stdout.sync = true

set :port, ENV['PORT'] || 4567
get '/' do
  'ok'
end

post '/events' do
  return params[:challenge] if params[:challenge]

  data = params[:event]
  on_reaction_added(data) if data[:type] == 'reaction_added'
end

def on_reaction_added(data)
  puts '[on_reaction_added]'
  p data
  begin
    item = data['item']
    puts 'message:'
    p message = fetch_message_for(item)

    # ignore reaction for file
    return unless message['type'] == 'message'

    text_or_from_url = message['text'].to_s.strip
    if text_or_from_url.empty?
      from_url_attachment = Array(message['attachments']).find { |a| a.key?('from_url') }

      text_or_from_url = from_url_attachment['from_url'] if from_url_attachment
    end

    status_ids = text_or_from_url.scan(%r{twitter.com/\S+/status/(\d+)}).flatten

    # F**K: data.reaction for 1st emoji, data.reactions for rest
    reaction_name = data['reaction'] || data['reactions'].last['name']
    puts "reaction_name: #{reaction_name}"


    all_reacted_reactions = message['reactions'].select { |r| r['count'] == 3 }
    if all_reacted_reactions.any? { |r| r['name'] == reaction_name }
      notify_notify_all_reacted(item, reaction_name, message['text'])
    end

    case reaction_name
    when /no_/
      # Do not notify tweets from this user anymore
      puts "[will ban] #{text_or_from_url}"
      puts ban_users_from(status_ids)
      puts "[banned] #{text_or_from_url}"

      begin
        remove_attachments_of(item, text: message['text'])
      rescue => e
        puts "error on remove_attachments"
        puts e.message
        puts e.backtrace.join("\n")
      end
    when 'wastebasket' # test
      remove_attachments_of(item, text: message['text'])
      puts 'remove_attachments done'
    when 'test_tube'
      slack_bot_client.chat_postMessage(channel: item['channel'], text: 'msg by bot token')
      slack_user_client.chat_postMessage(channel: item['channel'], text: 'msg by user token')
      puts "test tube done"
    when 'innocent'
      # Unban user
      puts "[will unban] #{text_or_from_url}"
      puts unban_users_from(status_ids)
      puts "[unbanned] #{text_or_from_url}"
    when 'octocat'
      puts "[will create issue] #{text_or_from_url}"
      create_issue_or_ignore_from(item['channel'], item['ts'], message, ENV['GITHUB_REPOSITORY'])
      puts "[created issue] #{text_or_from_url}"
    when 'esaise'
      puts "[will esaise] #{text_or_from_url}"
      esaise(item, message)
      puts "[esaised] #{text_or_from_url}"
    when /kaesita|kaeshita/
      puts "[will reply_done] #{text_or_from_url}"
      reply_done
      puts "[reply_done] #{text_or_from_url}"
    when 'rt', 'repeat', 'retweet'
      # ReTweet the tweet
      puts "[will retweet] #{text_or_from_url}"
      retweet(status_ids)
      puts "[retweeted] #{text_or_from_url}"
    else
      # Add favorite to the tweet
      puts "[will favorite] #{text_or_from_url}"
      favorite(status_ids)
      puts "[favorited] #{text_or_from_url}"
    end
  rescue => e
    puts e.message
    puts e.backtrace.join("\n")
  end
end

def ban_users_from(status_ids)
  users_ids = twitter_client.statuses(status_ids).map { |t| t.user.id }

  # for esarch.rb
  redis.sadd 'esarch:banned_user_ids', users_ids
end

def unban_users_from(status_ids)
  users_ids = twitter_client.statuses(status_ids).map { |t| t.user.id }

  # for esarch.rb
  redis.srem 'esarch:banned_user_ids', users_ids
end

def create_issue_or_ignore_from(channel, ts, message, repo)
  message_uid = "#{channel}:#{ts}"
  return if redis.sismember 'issue_created_messages', message_uid
  title = body = message['text']
  if message['attachments']
    message['attachments'].each do |attachment|
      text = attachment['text']
      next unless text
      body += "\n\n #{text}"
      title = text
    end
  end

  body += "\n\n#{archives_link(channel, ts)}"

  title = "[esarch] #{title[0..30]}"

  github_client.create_issue(repo, title, body, labels: 'esarch')
  redis.sadd 'issue_created_messages', message_uid
end

def favorite(status_ids)
  status_ids.each { |status_id| twitter_client.favorite(status_id) }
end

def retweet(status_ids)
  status_ids.each { |status_id| twitter_client.retweet(status_id) }
end

def reply_done
  puts Net::HTTP.get(URI.parse(ENV['REPLY_HOOK_URL']))
end

def esaise(item, message)
  link = archives_link(item['channel'], item['ts'])
  posts_result = esa_client.posts(q: link)
  if posts_result.body['total_count'].zero?
    body_md = "from: #{link}\n\n#{message['text']}"
    create_result = esa_client.create_post(name: message['text'][0..30].tr('/', '_'), category: 'esaise', user: 'esa_bot', body_md: body_md)
    msg = "created: #{create_result.body['url']}"
  else
    msg = posts_result.body['posts'].map{ |post| "#{post['full_name']} #{post['url']}" }.join("\n")
  end
  slack_bot_client.chat_postMessage(channel: item['channel'], text: msg)
end

def remove_attachments_of(item, text: nil)
  slack_bot_client.chat_update(
    channel: item['channel'],
    ts: item['ts'],
    text: text,
    attachments: [{ "text": "(deleted)" }]
  )
end

def fetch_message_for(item)
  # https://api.slack.com/methods/conversations.history
  conversations_history = slack_user_client.conversations_history(
    channel: item['channel'],
    latest: item['ts'],
    oldest: item['ts'],
    limit: 1,
    inclusive: 1
  )
  conversations_history['messages'].first
end

def fetch_permalink_for(item)
  slack_user_client.chat_getPermalink(
    channel: item['channel'],
    message_ts: item['ts'],
  ).permalink
end

def notify_notify_all_reacted(item, emoji, message)
  permalink = fetch_permalink_for(item)
  slack_bot_client.chat_postMessage(
    channel: item['channel'],
    text: "<!channel> This got 3 :#{emoji}: #{permalink}\n#{message}",
  )
end

def channel_name_for(channel_id)
  conversations_info = slack_user_client.conversations_info(channel: channel_id)
  conversations_info['channel']['name']
end

def host
  slack_user_client.auth_test['url']
end

def archives_link(channel_id, ts)
  "#{host}archives/#{channel_name_for(channel_id)}/p#{ts.delete('.')}"
end

def twitter_client
  # need Read/Write access
  @twitter_client ||= Twitter::REST::Client.new do |config|
    config.consumer_key        = ENV['TWITTER_API_KEY']
    config.consumer_secret     = ENV['TWITTER_API_SECRET']
    config.access_token        = ENV['TWITTER_ACCESS_TOKEN']
    config.access_token_secret = ENV['TWITTER_ACCESS_TOKEN_SECRET']
  end
end

def slack_user_client
  @slack_user_client ||= Slack::Web::Client.new(
    token: ENV['SLACK_USER_TOKEN']
  )
end

def slack_bot_client
  @slack_bot_client ||= Slack::Web::Client.new(
    token: ENV['SLACK_BOT_TOKEN']
  )
end

def esa_client
  @esa_client ||= Esa::Client.new(access_token: ENV['ESA_TOKEN'], current_team: ENV['ESA_TEAM'])
end

def github_client
  @github_client ||= Octokit::Client.new(access_token: ENV['GITHUB_TOKEN'])
end

def redis
  @redis ||= Redis.new(url: ENV['REDIS_URL'])
end
