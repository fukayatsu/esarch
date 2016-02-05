require 'redis'
require 'twitter'
require 'slack'

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
      message = fetch_message_for(data['item'])
      puts 'message:'
      p message

      # ignore reaction for file
      return unless message['type'] == 'message'

      status_ids = message['text'].scan(%r{twitter.com/\S+/status/(\d+)}).flatten

      print 'reaction_name: '
      # F**K: data.reaction for 1st emoji, data.reactions for rest
      puts reaction_name = data['reaction'] || data['reactions'].last['name']

      if reaction_name =~ /no_/
        # Do not notify tweets from this user anymore
        puts "[will ban] #{message['text']}"
        ban_users_from(status_ids)
        puts "[banned] #{message['text']}"
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

  def twitter_client
    # need Read/Write access
    @twitter_client ||= Twitter::REST::Client.new do |config|
      config.consumer_key        = ENV['TWITTER_API_KEY']
      config.consumer_secret     = ENV['TWITTER_API_SECRET']
      config.access_token        = ENV['TWITTER_ACCESS_TOKEN']
      config.access_token_secret = ENV['TWITTER_ACCESS_TOKEN_SECRET']
    end
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
