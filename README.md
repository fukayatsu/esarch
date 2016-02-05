# esarch

- earch.rb
  - twitter search => slack channel
- reaction.rb
  - slack reaction => favorite tweet

# Requirements
- Heroku
  - Redis
  - Heroku Scheduler(every 10 minutes)
    - `bundle exec ruby esarch.rb`
  - Papertrail(optional)
- Twitter Token(Read/Write)
- Slack Tokens
  - Incomming Webhook URL
  - API token

# Config Vars
```
IGNORE_WORD:                 sushi
REDIS_URL:                   redis://xxx
REQUIRED_REGEX:              sushi
SEARCH_QUERY:                (sushi OR sushi.io OR sushi_io OR #sushi_io OR #sushi) -rt
SLACK_TOKEN:                 xoxp-xxx-xxx-xxx-xxx
SLACK_WEBHOOK_URL:           https://hooks.slack.com/services/xxx/yyy/zzz
TABOO_NAME_REGEX:            sushi
TABOO_WORDS:                 SUSHI,sushi.int,酢市
TWITTER_ACCESS_TOKEN:        xxx
TWITTER_ACCESS_TOKEN_SECRET: xxx
TWITTER_API_KEY:             xxx
TWITTER_API_SECRET:          xxx
TWITTER_IGNORE_USERS:        foobar
TWITTER_LANGUAGE:            ja
```
