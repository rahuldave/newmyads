###
A NodeJS server that statically serves javascript out, proxies solr requests,
and handles authentication through the ADS
###

connect = require 'connect'
connectutils = connect.utils
http = require 'http'
querystring = require 'querystring'
url = require 'url'
fs = require 'fs'
redis = require 'redis'
redis_client = redis.createClient()
# RedisStore = require('connect-redis')(connect)

requests = require "./requests-myads"
completeRequest = requests.completeRequest
failedRequest = requests.failedRequest
successfulRequest = requests.successfulRequest
ifLoggedIn = requests.ifLoggedIn
postHandler = requests.postHandler
postHandlerWithJSON = requests.postHandlerWithJSON


user = require "./user"
loginUser = user.loginUser
logoutUser = user.logoutUser
getUser = user.getUser


saved = require "./saved"
tags = require "./tags"
groups = require "./groups"
migration = require('./migration')

config = require("./config").config
SITEPREFIX = config.SITEPREFIX

##Only run on the cookiestealer. Then TODO:test
makeADSJSONPCall = (req, res, next) ->
  #jsonpcback = url.parse(req.url, true).query.callback
  jsonpcback = req.query.callback
  console.log "makeADSJSONPCCall: #{jsonpcback}"

  adsoptions =
    host: config.ADSHOST
    path: config.ADSURL
    headers:
      Cookie: "NASA_ADS_ID=#{req.cookies.nasa_ads_id}"

  proxy.doTransformedProxy adsoptions, req, res, (val) ->
    "#{jsonpcback}(#{val})"

addUser = (req, res, next) ->
  console.log "::addToRedis cookies=#{JSON.stringify req.cookies}"
  postHandler req, res, user.insertUser

doPost = (func) ->
  (req, res, next) -> postHandler req, res, func

doPostWithJSON = (func) ->
  (req, res, next) -> postHandlerWithJSON req, res, func
# Proxy the call to ADS, setting up the NASA_ADS_ID cookie



# This is just temporary code: could add in a timeout and message


server = connect.createServer()
#server.use connect.logger()
server.use connect.cookieParser()
server.use connect.query()

server.use SITEPREFIX+'/adsjsonp', makeADSJSONPCall

# Using get to put into redis:BAD but just for testing
# QUS: Is this comment still accurate?
server.use SITEPREFIX+'/addtoredis', addUser
server.use SITEPREFIX+'/getuser', getUser
server.use SITEPREFIX+'/logout', logoutUser
server.use SITEPREFIX+'/login', loginUser


server.use SITEPREFIX+'/savesearch', doPost saved.saveSearch
server.use SITEPREFIX+'/savepub', doPost saved.savePub
server.use SITEPREFIX+'/saveobsv', doPost saved.saveObsv

server.use SITEPREFIX+'/savesearchestogroup', doPostWithJSON saved.saveSearchesToGroup
server.use SITEPREFIX+'/savepubstogroup', doPostWithJSON saved.savePubsToGroup
server.use SITEPREFIX+'/saveobsvstogroup', doPostWithJSON saved.saveObsvsToGroup


server.use SITEPREFIX+'/deletesearch', doPost saved.deleteSearch
server.use SITEPREFIX+'/deletesearches', doPost saved.deleteSearches
server.use SITEPREFIX+'/deletepub', doPost saved.deletePub
server.use SITEPREFIX+'/deletepubs', doPost saved.deletePubs
server.use SITEPREFIX+'/deleteobsv', doPost saved.deleteObsv
server.use SITEPREFIX+'/deleteobsvs', doPost saved.deleteObsvs


server.use SITEPREFIX+'/deletesearchesfromgroup', doPostWithJSON saved.deleteSearchesFromGroup
server.use SITEPREFIX+'/deletepubsfromgroup', doPostWithJSON saved.deletePubsFromGroup
server.use SITEPREFIX+'/deleteobsvsfromgroup', doPostWithJSON saved.deleteObsvsFromGroup


server.use SITEPREFIX+'/deletesearchesfromtag', doPostWithJSON tags.deleteSearchesFromTag
server.use SITEPREFIX+'/deletepubsfromtag', doPostWithJSON tags.deletePubsFromTag
server.use SITEPREFIX+'/deleteobsvsfromtag', doPostWithJSON tags.deleteObsvsFromTag
server.use SITEPREFIX+'/savedsearchesfortag', tags.getSavedSearchesForTag
server.use SITEPREFIX+'/savedpubsfortag', tags.getSavedPubsForTag
server.use SITEPREFIX+'/savedobsvsfortag', tags.getSavedObsvsForTag

server.use SITEPREFIX+'/gettagsforuser', tags.getTagsForUser
server.use SITEPREFIX+'/gettagsforgroup', tags.getTagsForGroup

server.use SITEPREFIX+'/savesearchestotag', doPostWithJSON tags.saveSearchesToTag
server.use SITEPREFIX+'/savepubstotag', doPostWithJSON tags.savePubsToTag
server.use SITEPREFIX+'/saveobsvstotag', doPostWithJSON tags.saveObsvsToTag


server.use SITEPREFIX+'/savedsearches', saved.getSavedSearches
server.use SITEPREFIX+'/savedsearches2', saved.getSavedSearches2
server.use SITEPREFIX+'/savedsearchesforgroup2', saved.getSavedSearchesForGroup2
server.use SITEPREFIX+'/savedpubs', saved.getSavedPubs
server.use SITEPREFIX+'/savedpubs2', saved.getSavedPubs2
server.use SITEPREFIX+'/savedpubsforgroup2', saved.getSavedPubsForGroup2
server.use SITEPREFIX+'/savedobsvs', saved.getSavedObsvs
server.use SITEPREFIX+'/savedobsvs2', saved.getSavedObsvs2
server.use SITEPREFIX+'/savedobsvsforgroup2', saved.getSavedObsvsForGroup2

#Groupfunctions
server.use SITEPREFIX+'/creategroup', doPostWithJSON groups.createGroup
server.use SITEPREFIX+'/addinvitationtogroup', doPostWithJSON groups.addInvitationToGroup
server.use SITEPREFIX+'/removeinvitationfromgroup', doPostWithJSON groups.removeInvitationFromGroup
server.use SITEPREFIX+'/acceptinvitationtogroup', doPostWithJSON groups.acceptInvitationToGroup
server.use SITEPREFIX+'/declineinvitationtogroup', doPostWithJSON groups.declineInvitationToGroup
server.use SITEPREFIX+'/removeuserfromgroup', doPostWithJSON groups.removeUserFromGroup
server.use SITEPREFIX+'/changeownershipofgroup', doPostWithJSON groups.changeOwnershipOfGroup
server.use SITEPREFIX+'/removeoneselffromgroup', doPostWithJSON groups.removeOneselfFromGroup
server.use SITEPREFIX+'/deletegroup', doPostWithJSON groups.deleteGroup

#and the gets   
server.use SITEPREFIX+'/getmembersofgroup', groups.getMembersOfGroup
server.use SITEPREFIX+'/getinvitationstogroup', groups.getInvitationsToGroup
server.use SITEPREFIX+'/getgroupinfo', groups.getGroupInfo
server.use SITEPREFIX+'/memberofgroups', groups.memberOfGroups
server.use SITEPREFIX+'/ownerofgroups', groups.ownerOfGroups
server.use SITEPREFIX+'/pendinginvitationtogroups', groups.pendingInvitationToGroups
# not sure of the best way to do this, but want to privide access to
# ajax-loader.gif and this way avoids hacking ResultWidget.2.0.js

runServer = (svr, port) ->
  now = new Date()
  hosturl = "http://localhost:#{port}#{SITEPREFIX}/"
  console.log "#{now.toUTCString()} - Starting server on #{hosturl}"
  svr.listen port

migration.validateRedis redis_client, () -> runServer server, config.PORT

