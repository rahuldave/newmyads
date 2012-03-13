###
A NodeJS server that statically serves javascript out, proxies solr requests,
and handles authentication through the ADS
###

connect = require 'connect'
connectutils = connect.utils
http = require 'http'
querystring = require 'querystring'
url = require 'url'
#fs = require 'fs'

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
savedgroup = require "./saved-group" 
tags = require "./tags"
groups = require "./groups"


addUser = (req, res, next) ->
  console.log "::addToRedis cookies=#{JSON.stringify req.cookies}"
  postHandler req, res, user.insertUser

doPost = (func) ->
  (req, res, next) -> postHandler req, res, func

doPostWithJSON = (func) ->
  (req, res, next) -> postHandlerWithJSON req, res, func
# Proxy the call to ADS, setting up the NASA_ADS_ID cookie



# This is just temporary code: could add in a timeout and message

configureServer = (config, server) ->
  #server = connect.createServer()
  #server.use connect.logger()
  #server.use connect.cookieParser()
  #server.use connect.query()

  #server.use config.SITEPREFIX+'/adsjsonp', makeADSJSONPCall

  # Using get to put into redis:BAD but just for testing
  # QUS: Is this comment still accurate?
  server.use config.SITEPREFIX+'/addtoredis', addUser
  server.use config.SITEPREFIX+'/getuser', getUser
  server.use config.SITEPREFIX+'/logout', logoutUser
  server.use config.SITEPREFIX+'/login', loginUser


  server.use config.SITEPREFIX+'/savesearch', doPost saved.saveSearches
  server.use config.SITEPREFIX+'/savepub', doPost saved.savePubs
  server.use config.SITEPREFIX+'/saveobsv', doPost saved.saveObsvs

  server.use config.SITEPREFIX+'/savesearchestogroup', doPostWithJSON savedgroup.saveSearchesToGroup
  server.use config.SITEPREFIX+'/savepubstogroup', doPostWithJSON savedgroup.savePubsToGroup
  server.use config.SITEPREFIX+'/saveobsvstogroup', doPostWithJSON savedgroup.saveObsvsToGroup


  server.use config.SITEPREFIX+'/deletesearch', doPost saved.deleteSearch
  server.use config.SITEPREFIX+'/deletesearches', doPost saved.deleteSearches
  server.use config.SITEPREFIX+'/deletepub', doPost saved.deletePub
  server.use config.SITEPREFIX+'/deletepubs', doPost saved.deletePubs
  server.use config.SITEPREFIX+'/deleteobsv', doPost saved.deleteObsv
  server.use config.SITEPREFIX+'/deleteobsvs', doPost saved.deleteObsvs


  server.use config.SITEPREFIX+'/deletesearchesfromgroup', doPostWithJSON savedgroup.deleteSearchesFromGroup
  server.use config.SITEPREFIX+'/deletepubsfromgroup', doPostWithJSON savedgroup.deletePubsFromGroup
  server.use config.SITEPREFIX+'/deleteobsvsfromgroup', doPostWithJSON savedgroup.deleteObsvsFromGroup


  server.use config.SITEPREFIX+'/deletesearchesfromtag', doPostWithJSON tags.deleteSearchesFromTag
  server.use config.SITEPREFIX+'/deletepubsfromtag', doPostWithJSON tags.deletePubsFromTag
  server.use config.SITEPREFIX+'/deleteobsvsfromtag', doPostWithJSON tags.deleteObsvsFromTag
  server.use config.SITEPREFIX+'/savedsearchesfortag', tags.getSavedSearchesForTag
  server.use config.SITEPREFIX+'/savedpubsfortag', tags.getSavedPubsForTag
  server.use config.SITEPREFIX+'/savedobsvsfortag', tags.getSavedObsvsForTag

  server.use config.SITEPREFIX+'/gettagsforuser', tags.getTagsForUser
  server.use config.SITEPREFIX+'/gettagsforgroup', tags.getTagsForGroup

  server.use config.SITEPREFIX+'/savesearchestotag', doPostWithJSON tags.saveSearchesToTag
  server.use config.SITEPREFIX+'/savepubstotag', doPostWithJSON tags.savePubsToTag
  server.use config.SITEPREFIX+'/saveobsvstotag', doPostWithJSON tags.saveObsvsToTag


  #server.use config.SITEPREFIX+'/savedsearches', saved.getSavedSearches
  server.use config.SITEPREFIX+'/savedsearches2', saved.getSavedSearches2
  server.use config.SITEPREFIX+'/savedsearchesforgroup2', savedgroup.getSavedSearchesForGroup2
  #server.use config.SITEPREFIX+'/savedpubs', saved.getSavedPubs
  server.use config.SITEPREFIX+'/savedpubs2', saved.getSavedPubs2
  server.use config.SITEPREFIX+'/savedpubsforgroup2', savedgroup.getSavedPubsForGroup2
  #server.use config.SITEPREFIX+'/savedobsvs', saved.getSavedObsvs
  server.use config.SITEPREFIX+'/savedobsvs2', saved.getSavedObsvs2
  server.use config.SITEPREFIX+'/savedobsvsforgroup2', savedgroup.getSavedObsvsForGroup2

  #Groupfunctions
  server.use config.SITEPREFIX+'/creategroup', doPostWithJSON groups.createGroup
  server.use config.SITEPREFIX+'/addinvitationtogroup', doPostWithJSON groups.addInvitationToGroup
  server.use config.SITEPREFIX+'/removeinvitationfromgroup', doPostWithJSON groups.removeInvitationFromGroup
  server.use config.SITEPREFIX+'/acceptinvitationtogroup', doPostWithJSON groups.acceptInvitationToGroup
  server.use config.SITEPREFIX+'/declineinvitationtogroup', doPostWithJSON groups.declineInvitationToGroup
  server.use config.SITEPREFIX+'/removeuserfromgroup', doPostWithJSON groups.removeUserFromGroup
  server.use config.SITEPREFIX+'/changeownershipofgroup', doPostWithJSON groups.changeOwnershipOfGroup
  server.use config.SITEPREFIX+'/removeoneselffromgroup', doPostWithJSON groups.removeOneselfFromGroup
  server.use config.SITEPREFIX+'/deletegroup', doPostWithJSON groups.deleteGroup

  #and the gets   
  server.use config.SITEPREFIX+'/getmembersofgroup', groups.getMembersOfGroup
  server.use config.SITEPREFIX+'/getinvitationstogroup', groups.getInvitationsToGroup
  server.use config.SITEPREFIX+'/getgroupinfo', groups.getGroupInfo
  server.use config.SITEPREFIX+'/memberofgroups', groups.memberOfGroups
  server.use config.SITEPREFIX+'/ownerofgroups', groups.ownerOfGroups
  server.use config.SITEPREFIX+'/pendinginvitationtogroups', groups.pendingInvitationToGroups
# not sure of the best way to do this, but want to privide access to
# ajax-loader.gif and this way avoids hacking ResultWidget.2.0.js

runServer = (config) ->
  console.log "CONFIG", config
  server = connect.createServer()
  server.use connect.logger()
  server.use connect.cookieParser()
  server.use connect.query()
  configureServer config, server
  now = new Date()
  hosturl = "http://localhost:#{config.PORT}#{config.SITEPREFIX}/"
  console.log "#{now.toUTCString()} - Starting server on #{hosturl}"
  server.listen config.PORT

exports.runServer = runServer
exports.configureServer = configureServer
