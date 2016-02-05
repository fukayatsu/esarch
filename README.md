# esarch

## Tweet captured by the query

<img width="613" alt="ss 2016-02-05 at 15 11 30" src="https://cloud.githubusercontent.com/assets/1041857/12839237/c48f2090-cc1a-11e5-93cb-c856bce8dde6.png">

## Notify to slack, and if you add a Emoji Reaction...
<img width="491" alt="ss 2016-02-05 at 15 10 01" src="https://cloud.githubusercontent.com/assets/1041857/12839238/c4a75bce-cc1a-11e5-9160-6325aefaffe4.png">

## Then, automatically favorite the tweet
<img width="609" alt="ss 2016-02-05 at 15 10 19" src="https://cloud.githubusercontent.com/assets/1041857/12839236/c46c9f2a-cc1a-11e5-9cc2-bfb60d894068.png">



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
