require 'twitter'
require 'redis'
require 'slack-notifier'

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
    tweets = twitter_client.search(SEARCH_QUERY,
                                   lang:        'ja',
                                   result_type: 'recent',
                                   count:       BATCH_SIZE,
                                   since_id:    since_id)
    tweets.take(BATCH_SIZE)
  end

  def notify(tweets)
    tweets.each { |tweet| notify_or_ignore(tweet) }
  end

  def notify_or_ignore(tweet)
    return if should_ignore?(tweet)
    puts "#{tweet.url} #{tweet.text}"
    slack_notifier.ping(tweet.url.to_s,
                        icon_url: tweet.user.profile_image_url.to_s,
                        username: tweet.user.screen_name)
  end

  def should_ignore?(tweet)
    return true if redis.sismember('esarch:banned_user_ids', tweet.user.id)
    return true if tweet.user.name =~ TABOO_NAME_REGEX
    return true if tweet.user.screen_name =~ TABOO_NAME_REGEX
    return true if tweet.text.scan(/@(\S+)/).flatten.any? { |screen_name| screen_name =~ TABOO_NAME_REGEX }
    return true if TABOO_WORDS.any? { |taboo_word| tweet.text.include?(taboo_word) }
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

  def slack_notifier
    @slack_notifier ||= Slack::Notifier.new ENV['SLACK_WEBHOOK_URL']
  end

  def redis
    @redis ||= Redis.new(url: ENV['REDIS_URL'])
  end
end

esarch = Esarch.new
esarch.run!
