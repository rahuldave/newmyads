server = require('./server-myads')
config = require('./config').config
redis = require 'redis'
redis_client = redis.createClient()
migration = require('./migration')

migration.validateRedis redis_client, () -> server.runServer config
