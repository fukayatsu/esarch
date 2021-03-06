require 'twitter'
require 'redis'
require 'slack'

class Esarch
  SEARCH_QUERY     = ENV['SEARCH_QUERY']
  TABOO_WORDS      = (ENV['TABOO_WORDS'] || '').split(',')
  BATCH_SIZE       = (ENV['BATCH_SIZE'] || 100).to_i
  TABOO_NAME_REGEX = /#{ENV['TABOO_NAME_REGEX']}/i
  REQUIRED_REGEX   = /#{ENV['REQUIRED_REGEX']}/

  def run!
    tweets = search
    return if tweets.empty?
    notify(tweets)
    update_since_id(tweets)
  end

  private

  def search
    twitter_client.search(
      SEARCH_QUERY,
      lang:        'ja',
      result_type: 'recent',
      tweet_mode:  'extended',
      count:       BATCH_SIZE,
      since_id:    since_id
    ).take(BATCH_SIZE)
  end

  def notify(tweets)
    tweets.reverse.each { |tweet| notify_or_ignore(tweet) }
  end

  def notify_or_ignore(tweet)
    return if should_ignore?(tweet)
    puts "#{tweet.url} #{tweet.text}"

    slack_bot_client.chat_postMessage(channel: ENV["SLACK_CHANNEL"], text: tweet.url.to_s)
  end

  def should_ignore?(tweet)
    taboo_tweet?(tweet) || junk_tweet?(tweet)
  end

  def taboo_tweet?(tweet)
    return true if redis.sismember('esarch:banned_user_ids', tweet.user.id)
    return true if tweet.user.name =~ TABOO_NAME_REGEX
    return true if tweet.user.screen_name =~ TABOO_NAME_REGEX
    return true if tweet.text.scan(/@(\S+)/).flatten.any? { |screen_name| screen_name =~ TABOO_NAME_REGEX }
    TABOO_WORDS.any? { |taboo_word| tweet.text.include?(taboo_word) }
  end

  def junk_tweet?(tweet)
    return false if tweet.urls.any? { |data| data.expanded_url.to_s =~ /esa\.io/ }
    !(tweet.text =~ REQUIRED_REGEX)
  end

  def update_since_id(tweets)
    redis.set('esarch:since_id', tweets.first.id)
  end

  def since_id
    (redis.get('esarch:since_id') || 0).to_i
  end

  def twitter_client
    @twitter_client ||= Twitter::REST::Client.new do |config|
      config.consumer_key        = ENV['TWITTER_API_KEY']
      config.consumer_secret     = ENV['TWITTER_API_SECRET']
      config.access_token        = ENV['TWITTER_ACCESS_TOKEN']
      config.access_token_secret = ENV['TWITTER_ACCESS_TOKEN_SECRET']
    end
  end

  def slack_bot_client
    @slack_bot_client ||= Slack::Web::Client.new(
      token: ENV['SLACK_BOT_TOKEN']
    )
  end

  def redis
    @redis ||= Redis.new(url: ENV['REDIS_URL'])
  end
end

esarch = Esarch.new
esarch.run!
