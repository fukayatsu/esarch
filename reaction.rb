require 'redis'
require 'twitter'
require 'slack'
require 'octokit'
require 'esa'
require 'net/http'

# Make it easy to check log on Papertrail addon
$stdout.sync = true

Slack.configure do |config|
  config.token = ENV['SLACK_TOKEN']
end

class Reaction
  def listen!
    client = Slack::RealTime::Client.new
    client.on :hello do
      puts '[Slack Real Time Messaging API] Successfully connected.'
    end

    # https://api.slack.com/events/reaction_added
    client.on :reaction_added do |data|
      on_reaction_added(data)
    end
    client.start_async
  end

  private

  def on_reaction_added(data)
    puts '[on_reaction_added]'
    p data
    begin
      item = data['item']
      puts 'message:'
      p message = fetch_message_for(item)

      # ignore reaction for file
      return unless message['type'] == 'message'

      status_ids = message['text'].scan(%r{twitter.com/\S+/status/(\d+)}).flatten

      print 'reaction_name: '
      # F**K: data.reaction for 1st emoji, data.reactions for rest
      puts reaction_name = data['reaction'] || data['reactions'].last['name']


      all_reacted_reactions = message['reactions'].select { |r| r['count'] == 3 }
      if all_reacted_reactions.any? { |r| r['name'] == reaction_name }
        notify_notify_all_reacted(item, reaction_name)
      end

      case reaction_name
      when /no_/
        # Do not notify tweets from this user anymore
        puts "[will ban] #{message['text']}"
        puts ban_users_from(status_ids)
        puts "[banned] #{message['text']}"
      when 'innocent'
        # Unban user
        puts "[will unban] #{message['text']}"
        puts unban_users_from(status_ids)
        puts "[unbanned] #{message['text']}"
      when 'octocat'
        puts "[will create issue] #{message['text']}"
        create_issue_or_ignore_from(item['channel'], item['ts'], message, ENV['GITHUB_REPOSITORY'])
        puts "[created issue] #{message['text']}"
      when 'esaise'
        puts "[will esaise] #{message['text']}"
        esaise(item, message)
        puts "[esaised] #{message['text']}"
      when /kaesita|kaeshita/
        puts "[will reply_done] #{message['text']}"
        reply_done
        puts "[reply_done] #{message['text']}"
      when 'rt', 'repeat', 'retweet'
        # ReTweet the tweet
        puts "[will retweet] #{message['text']}"
        retweet(status_ids)
        puts "[retweeted] #{message['text']}"
      else
        # Add favorite to the tweet
        puts "[will favorite] #{message['text']}"
        favorite(status_ids)
        puts "[favorited] #{message['text']}"
      end
    rescue => e
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
    slack_web_client.chat_postMessage(channel: item['channel'], text: msg, username: 'esaise', icon_emoji: ':esaise:', as_user: false)
  end

  def fetch_message_for(item)
    # https://api.slack.com/methods/channels.history
    channels_history = slack_web_client.channels_history(
      channel: item['channel'],
      latest: item['ts'],
      oldest: item['ts'],
      inclusive: 1
    )
    channels_history['messages'].first
  end

  def fetch_permalink_for(item)
    slack_web_client.chat_getPermalink(
      channel: item['channel'],
      message_ts: item['ts'],
    ).permalink
  end

  def notify_notify_all_reacted(item, emoji)
    permalink = fetch_permalink_for(item)
    slack_web_client.chat_postMessage(
      channel: item['channel'],
      text: "<!channel> This got 3 :#{emoji}: #{permalink}",
      username: 'mannjouitti',
      icon_emoji: ':mannjouitti:',
      as_user: false
    )
  end

  def channel_name_for(channel_id)
    channels_info = slack_web_client.channels_info(channel: channel_id)
    channels_info['channel']['name']
  end

  def host
    slack_web_client.auth_test['url']
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

  def slack_web_client
    @slack_web_client ||= Slack::Web::Client.new
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
end

Reaction.new.listen!

# for keep alive
require 'sinatra'
set :port, ENV['PORT'] || 4567
get '/' do
  'ok'
end
