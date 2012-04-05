###
Handle user login/out and checks.
###

#connectutils = require('connect').utils
url = require 'url'
#redis_client = require("redis").createClient()
requests = require("./requests-myads")
failedRequest = requests.failedRequest
successfulRequest = requests.successfulRequest
ifLoggedIn = requests.ifLoggedIn

httpcallbackmaker = requests.httpcallbackmaker
#consolecallbackmaker=requests.consolecallbackmaker
connectutils = require('connect').utils
url = require 'url'

userdb = require("./userdb")
utils = require("./utils")
CONNECTION = utils.getRedisClient()
ifHavePermissions = utils.ifHavePermissions
ifHaveAuth = utils.ifHaveAuth
ifHavePermissions = utils.ifHavePermissions
getSortedElements = utils.getSortedElements
getSortedElementsAndScores = utils.getSortedElementsAndScores
timeToText = utils.timeToText
searchToText = utils.searchToText

makeLoginCookie = (cookiename,  cookievalue, days) ->
  secs = days * 24 * 60 * 60
  milisecs = secs * 1000

  # I've seen some funny behaviour with Date.now() so switching
  # to a more explicit method which has worked elsewhere, but is probably
  # not an issue here.
  # expdate = new Date(Date.now() + milisecs)
  #
  expdate = new Date(new Date().getTime() + milisecs)
  cookie = connectutils.serializeCookie cookiename, cookievalue, expires: expdate, path: '/'
  return unique: cookievalue, cookie: cookie, expdateinsecs: secs

loginUser = (req, res, next) ->
  redirect = url.parse(req.url, true).query.redirect
  currentToken = connectutils.uid 16
  adsurl = "http://adsabs.harvard.edu/cgi-bin/nph-manage_account?man_cmd=login&man_url=#{redirect}"
  startupCookie = makeLoginCookie 'startupcookie', currentToken, 0.005
  console.log "loginUser: REDIRECT=#{redirect}"

  # inline the responsedo closure that was in the original JavaScript
  res.writeHead 302, 'Redirect',
    'Set-Cookie': startupCookie.cookie
    Location: redirect

  res.statusCode = 302
  res.end()

logoutUser = (req, res, next) ->
  console.log "::: logoutCookies #{JSON.stringify req.cookies}"
  loginCookie = req.cookies.logincookie
  newLoginCookie = makeLoginCookie 'logincookie', loginCookie, -1
  redirect = url.parse(req.url, true).query.redirect
  redis_client.expire "email:#{loginCookie}", 0, (err, reply) ->
    res.writeHead 302, 'Redirect',
      'Set-Cookie': newLoginCookie.cookie
      Location: redirect
    res.statusCode = 302
    res.end()

insertUser = (jsonpayload, req, res, next) ->
  #BUG: currently checks on the payload have been removed. This is true everywhere.
  console.log __fname='insertuser'
  currentToken = connectutils.uid 16
  loginCookie = makeLoginCookie 'logincookie', currentToken, 365
  cookie = loginCookie.cookie
  lastcb = httpcallbackmaker(__fname, req, res, next)
  udb=userdb.getDb(CONNECTION, lastcb)
  udb.insertUser(jsonpayload, loginCookie)
  efunc = (err, reply) ->
    res.writeHead 200, "OK",
      'Content-Type': 'application/json'
      'Set-Cookie': cookie
    res.end()
  #execute with this as callback. Would it not be better to enhance the regular calback with cookie additon?
  #yes it would. Should the errors also get the cookie as in the original user.coffee?
  udb.execute(efunc)

#The original getUser tried to stuff with startupcookie. We remove this now but will get back
#in another way to bootstrap from ads cookie stealer BUG
#This two should use httpcallbackmaker in some way, augmented, instead of efunc
getUser = (req, res, next) ->
  console.log __fname="getuser"
  loginCookie = req.cookies.logincookie
  startupCookie = req.cookies.startupcookie
  lastcb = httpcallbackmaker(__fname, req, res, next)
  sendback =
    startup: if startupCookie? then startupCookie else 'undefined'
    email: 'undefined'

  udb=userdb.getDb(CONNECTION, lastcb)
  efunc = (err, reply) ->
    res.writeHead 200, "OK",
      'Content-Type': 'application/json'
      'Set-Cookie': cookie
    sendback.email=reply
    res.end JSON.stringify(sendback)
  udb.getUser(loginCookie, efunc)


            
exports.loginUser = loginUser
exports.logoutUser = logoutUser
exports.insertUser = insertUser
exports.getUser = getUser

