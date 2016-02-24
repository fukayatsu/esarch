require 'redis'
require 'twitter'
require 'slack'
require 'octokit'

# Make it easy to check log on Papertrail addon
$stdout.sync = true

Slack.configure do |config|
  config.token = ENV['SLACK_TOKEN']
end

class Reaction
  def listen!
    client = Slack.realtime
    client.on :hello do
      puts '[Slack Real Time Messaging API] Successfully connected.'
    end

    # https://api.slack.com/events/reaction_added
    client.on :reaction_added do |data|
      on_reaction_added(data)
    end
    client.start
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

      case reaction_name
      when /no_/
        # Do not notify tweets from this user anymore
        puts "[will ban] #{message['text']}"
        ban_users_from(status_ids)
        puts "[banned] #{message['text']}"
      when 'octocat'
        puts "[will create issue] #{message['text']}"
        create_issue_or_ignore_from(item['channel'], item['ts'], message, ENV['GITHUB_REPOSITORY'])
        puts "[created issue] #{message['text']}"
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

  def fetch_message_for(item)
    # https://api.slack.com/methods/channels.history
    channels_history = Slack.client.channels_history(
      channel: item['channel'],
      latest: item['ts'],
      oldest: item['ts'],
      inclusive: 1
    )
    channels_history['messages'].first
  end

  def channel_name_for(channel_id)
    channels_info = Slack.client.channels_info(channel: channel_id)
    channels_info['channel']['name']
  end

  def host
    Slack.client.auth_test['url']
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

  def github_client
    @github_client ||= Octokit::Client.new(access_token: ENV['GITHUB_TOKEN'])
  end

  def redis
    @redis ||= Redis.new(url: ENV['REDIS_URL'])
  end
end

Thread.new do
  Reaction.new.listen!
end

# for keep alive
require 'sinatra'
set :port, ENV['PORT'] || 4567
get '/' do
  'ok'
end
