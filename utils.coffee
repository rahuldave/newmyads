redis = require("redis")
redis_client = redis.createClient()

getRedisClient = () ->
  return redis_client

requests = require("./requests-myads")
failedRequest = requests.failedRequest
successfulRequest = requests.successfulRequest
ifLoggedIn = requests.ifLoggedIn
httpcallbackmaker = requests.httpcallbackmaker

#again null response is treated as error below. not sure this is right
#TODO: ecb ought to have a proper message.

#In genereal maybe stuff should raise exceptions and be handled? what does step want/ TODO
ifHaveEmail = (fname, req, res, cb) ->
  ecb=httpcallbackmaker(fname, req, res)#no next
  ifLoggedIn req, res, (loginid) ->
    redis_client.get "email:#{loginid}", (err, email) ->
        console.log "email is", email, err
        if err
            return ecb err, email
        if email
            cb email
        else
            return ecb err, email


ifHaveAuth = (req, res, ecb, cb) ->
  ifLoggedIn req, res, (loginid) ->
    redis_client.get "email:#{loginid}", (err, email) ->
        console.log "email is", email, err
        if err
            return ecb err, email
        #Philosophy: a null result is treated as an error
        if email
            return cb email
        else
            return ecb err, email

searchToText = (searchTerm) ->
    # lazy way to remove the trailing search term

    splits=searchTerm.split '#'
    s = "&#{splits[1]}"
    s = s.replace '&q=*%3A*', ''

    # only decode after the initial split to protect against the
    # unlikely event that &fq= appears as part of a search term.
    terms = s.split /&fq=/
    terms.shift()
    # ignore the first entry as '' by construction
    out = ''
    for term in terms 
        [name, value] = decodeURIComponent(term).split ':', 2
        out += "#{name}=#{value} "
    

    return out

# Returns a string representation of timeString, which
# should be a string containing the time in milliseconds,
# nowDate is the "current" date in milliseconds.
#
timeToText = (nowDate, timeString) ->
  t = parseInt timeString, 10
  delta = nowDate - t
  if delta < 1000
    return "Now"

  else if delta < 60000
    return "#{Math.floor(delta/1000)}s ago"

  else if delta < 60000 * 60
    m = Math.floor(delta / 60000)
    s = Math.floor((delta - m * 60000) /1000)
    out = "#{m}m"
    if s isnt 0
      out += " #{s}s"
    return "#{out} ago"

  else if delta < 60000 * 60 * 24
    h = Math.floor(delta / (60000 * 60))
    delta = delta - h * 60000 * 60
    m = Math.floor(delta / 60000)
    out = "#{h}h"
    if m isnt 0
      out += " #{m}m"
    return "#{out} ago"

  d = new Date(t)
  return d.toUTCString()
# A comment on saved times, used in both savePub and saveSearch.
#
# Approximate the save time as the time we process the request
# on the server, rather than when it was made (in case the user's
# clock is not set sensibly and it allows us to associate a time
# zone, even if it is our time zone and not the user's).
#
# For now we save the UTC version of the time and provide no
# way to change this to something meaningful to the user.
#
# Alternatives include:
#
# *  the client could send the time as a string, including the
#    time zone, but this relies on their clock being okay
#
# *  the client can send in the local timezone info which can
#    then be used to format the server-side derived time
#    Not sure if can trust the time zone offset from the client
#    if can not trust the time itself. Calculating a useful display
#    string from the timezone offset is fiddly.
#


# Get all the elements for the given key, stored
# in a sorted list, and sent it to callback
# as cb(err,values). If flag is true then the list is sorted in
# ascending order of score (ie zrange rather than zrevrange)
# otherwise descending order.
#
getSortedElements = (flag, key, cb) ->
  redis_client.zcard key, (err, nelem) ->
    # Could ask for nelem-1 but Redis seems to ignore
    # overflow here
    if flag
      redis_client.zrange key, 0, nelem, cb
    else
      redis_client.zrevrange key, 0, nelem, cb

# As getSortedElements but the values sent to the callback is
# a hash with two elements:
#    elements  - the elements
#    scores    - the scores
#
getSortedElementsAndScores = (flag, key, cb) ->
  redis_client.zcard key, (e1, nelem) ->
    if nelem is 0
      cb e1, elements: [], scores: []

    else
      splitIt = (err, values) ->
        # in case nelem has changed
        nval = values.length - 1
        response =
          elements: (values[i] for i in [0..nval] by 2)
          scores:   (values[i] for i in [1..nval] by 2)

        cb err, response

      if flag
        redis_client.zrange key, 0, nelem, "withscores", splitIt
      else
        redis_client.zrevrange key, 0, nelem, "withscores", splitIt

exports.ifHaveEmail = ifHaveEmail
exports.ifHaveAuth = ifHaveAuth
exports.getSortedElements = getSortedElements
exports.getSortedElementsAndScores = getSortedElementsAndScores
exports.timeToText = timeToText
exports.searchToText = searchToText
exports.getRedisClient = getRedisClient