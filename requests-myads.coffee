###
Break out the request-handling code from server.js as
we rewrite in CoffeeScript. It is turning into a bit of
a grab bag of functionality.
###

# Actually create and finish the request. The options argument
# controls the choice of arguments and defoptions gives the default
# values. The current approach is probably too flexible for its
# needs but not flexible enough for expanded use.
#
# The return message is sent using the keyword value set
# to the message value.


_ = require 'underscore'

errors = './errors'
RETURNSTRINGS= errors.RETURNSTRINGS
RETURNCODES = errors.RETURNCODES

completeRequest = (res, options, defoptions) ->
  console.log "In completeRequest", options
  opts = {}
  #_.extend defoptions, options
  for key, defval of defoptions
    opts[key] = if key of options then options[key] else defval
  #An Error must have an explicit response code  
  responseCode = opts.RETURNCODE ? RETURNCODES.INTERNAL_ERROR
  responseString = RETURNSTRINGS[responseCode] ? "No Response String Specified"
  res.writeHead responseCode, responseString, 'Content-Type': 'application/json'
  out = {}
  out[opts.keyword] = opts.message
  out.status = opts.status
  omsg = JSON.stringify out
  console.log "OUT", out
  res.end omsg


# The request failed so send back our generic "you failed" JSON
# payload.
#
# The options argument is used to set the name and value
# of the value returned;
#      keyword, defaults to 'success'
#      message, defaults to 'undefined'

#We'll assume this is generally of a 400. Other errors must be explicitly mentioned
failedRequest = (res, options = {}) ->
  completeRequest res, options,
    keyword: 'failedRequest'
    message: 'undefined'
    status: 'FAILURE'
    RETURNCODE: RETURNCODES.BAD_REQUEST

# The request succeeded.
#
# The options argument is used to set the name and value
# of the value returned;
#      keyword, defaults to 'success'
#      message, defaults to 'defined'

successfulRequest = (res, options = {}) ->
  completeRequest res, options,
    keyword: 'successfulRequest'
    message: 'defined'
    status: 'SUCCESS'
    RETURNCODE: RETURNCODES.OK

# Call cb with the login cookie otherwise return
# a failed request with failopts.

ifLoggedIn = (req, res, cb, failopts = {}) ->
  loginCookie = req.cookies.logincookie
  if loginCookie?
    cb loginCookie
  else
    failedRequest res, failopts

#Use this if you are logged in and we found an email for you
    

            
# this has an undefined error mode. Returns from flasy values may do this too
#this is the 0 style returns redis sometimes gets TODO make sure this is ok, and failedrequest is getting ok options  
httpcallbackmaker = (keyword, req, res, next)->
    return (err, reply, mergedict={})->
        if err
          options = keyword: keyword, message: err
          _.extend options, mergedict
          failedRequest res, options
        else
          if reply
            options = keyword: keyword, message: reply
            _.extend options, mergedict
            successfulRequest res, options
          else
            options = keyword: keyword, message: 'reply is undefined or null'
            _.extend options, mergedict
            failedRequest res, options

#BUG above needs to be enhanced by a header dictionary and an options dictionary where i can pass in stuff
#this will be useful in login and stuff but will require js client mods to get the canonical json returns
#we provide. Along with errorhandling, we should quickly do canonical json returns.
#(atleast for everything except savedb)
            
consolecallbackmaker = (keyword) ->
    return (err, reply) ->
        if err
            console.log '#{keyword}:ERROR', err
        else
            if reply
                console.log '#{keyword}:SUCCESS', reply
            else
                console.log '#{keyword}:FAILURE', reply
        
# Handle a POST request by collecting all the
# data and then sending it to the callback
# as  cb(buffer, req, res)

postHandler = (req, res, cb) ->
  if req.method isnt 'POST'
    return false
  buffer = ''
  req.addListener 'data', (chunk) ->
    buffer += chunk
  req.addListener 'end', () ->
    cb buffer, req, res

  return true
  
postHandlerWithJSON = (req, res, cb) ->
  console.log "oooooooooooooooooooooooooooooooooo"
  if req.method isnt 'POST'
    return false

  buffer = ''
  req.addListener 'data', (chunk) ->
    buffer += chunk
  req.addListener 'end', () ->
    console.log "cookies=#{req.cookies} payload=#{buffer}"
    cb JSON.parse(buffer), req, res

  return true

doPost = (func) ->
  (req, res, next) -> postHandler req, res, func

doPostWithJSON = (func) ->
  (req, res, next) -> postHandlerWithJSON req, res, func

exports.completeRequest = completeRequest
exports.failedRequest = failedRequest
exports.successfulRequest = successfulRequest
exports.ifLoggedIn = ifLoggedIn

exports.postHandler = postHandler
exports.postHandlerWithJSON = postHandlerWithJSON

exports.doPost = doPost
exports.doPostWithJSON = doPostWithJSON
exports.consolecallbackmaker=consolecallbackmaker
exports.httpcallbackmaker=httpcallbackmaker