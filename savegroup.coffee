###
Handles saved items - e.g. searches and publications - that involves
accessing information from Redis.
###

#BUG: when you and i boh save into a group, my removing stuff removes both our handiwork due to the set
#nature of things. The place to fix this is in the hash, where multiple existence of the same group
#in the value of a key means that we cant really delete it, because someone has a reference to it.

#BUG..where do I do redis quits? I might be losing memory!! Also related to scripts not exiting, surely!
requests = require("./requests-myads")
failedRequest = requests.failedRequest
successfulRequest = requests.successfulRequest
ifLoggedIn = requests.ifLoggedIn

httpcallbackmaker = requests.httpcallbackmaker
#consolecallbackmaker=requests.consolecallbackmaker
connectutils = require('connect').utils
url = require 'url'

savegroupdb = require("./savegroupdb")
utils = require("./utils")
CONNECTION = utils.getRedisClient()
ifHavePermissions = utils.ifHavePermissions
ifHaveAuth = utils.ifHaveAuth
ifHavePermissions = utils.ifHavePermissions
getSortedElements = utils.getSortedElements
getSortedElementsAndScores = utils.getSortedElementsAndScores
timeToText = utils.timeToText
searchToText = utils.searchToText

# Needed to check whether we get a string or an array
# of strings. Taken from
# http://stackoverflow.com/questions/1058427/how-to-detect-if-a-variable-is-an-array/1058457#1058457
#
# Is there a more CoffeeScript way of doing this (aside from a basic translation
# to CoffeeScript)

isArray = `function (o) {
    return (o instanceof Array) ||
        (Object.prototype.toString.apply(o) === '[object Array]');
};`





              
saveSearchesToGroup = ({fqGroupName, objectsToSave}, req, res, next) ->
  console.log __fname="saveSearchestoGroup"
  ifHaveEmail __fname, req, res, (savedBy) ->
      # keep as a multi even though now a single addition
      _doSaveSearchToGroup savedBy, fqGroupName, objectsToSave, 'search',  httpcallbackmaker(__fname, req, res, next)


savePubsToGroup = ({fqGroupName, objectsToSave}, req, res, next) ->
  console.log __fname="savePubsToGroup"
  ifHaveEmail __fname, req, res, (savedBy) ->
     _doSaveSearchToGroup savedBy, fqGroupName, objectsToSave, 'pub', httpcallbackmaker(__fname, req, res, next)
      
saveObsvsToGroup = ({fqGroupName, objectsToSave}, req, res, next) ->
  console.log __fname="saveObsvToGroup"
  ifHaveEmail __fname, req, res, (savedBy) ->
      _doSaveSearchToGroup savedBy, fqGroupName, objectsToSave, 'obsv', httpcallbackmaker(__fname, req, res, next)
            


createSavedTemplates = (searchtype, nowDate, searchkeys, searchtimes, namearchetypes=null, titlearchetypes=null) ->
  view = {}
  #console.log "VIEW", view
  nsearch = searchkeys.length
  view.searchtype = searchtype
  savedkey="saved#{searchtype}s"
  haskey="has#{searchtype}s"
  if nsearch is 0
    view[haskey] = false
    view[savedkey] = []

  else
    view[haskey]= true

    makeTemplate = (ctr) ->
      key = searchkeys[ctr]
      time = searchtimes[ctr]
      name = if namearchetypes then namearchetypes[ctr] else null
      title = if titlearchetypes then titlearchetypes[ctr] else null
      out =
        searchuri: key
        searchtext: searchToText key
        searchtime: time
        searchtimestr: timeToText nowDate, time
        searchctr: ctr
        searchname: name
        searchtitle: title
      return out

    view[savedkey] = (makeTemplate i for i in [0..nsearch-1])

  return view
  
_getSavedItems = (email, searchtype, templateCreatorFunc, callback, augmenthash=null) ->
    nowDate = new Date().getTime()
    savedb = new Savedb(CONNECTION, callback)
    savedb.getSavedItems searchtype, email,  (err, searches) ->
      console.log searchtype, '================', searches
      if augmenthash is null
          view = templateCreatorFunc searchtype, nowDate, searches.elements, searches.scores
          savedb.lastcallback err, view
      else
          savedb.getArchetypesForSavedItems "saved#{augmenthash.titlefield}", searches, (err3, titles) ->
            console.log 'ITLES', titles
            savedb.getArchetypesForSavedItems "saved#{augmenthash.namefield}", searches, (err4, names) ->
              console.log 'AMES', names, 'BEEP', searches
              view = templateCreatorFunc searchtype, nowDate, searches.elements, searches.scores, names, titles
              savedb.lastcallback err4, view


getSavedSearchesForGroup2 = (req, res, next) ->
  kword = 'savedsearchesforgroup'
  __fname=kword
  fqGroupName = req.query.fqGroupName
  ifHaveEmail __fname, req, res, (email) ->
      _doSearchForGroup email, fqGroupName, 'search', createSavedSearchTemplates, res, kword, httpcallbackmaker(__fname, req, res, next)
  
  


  
getSavedPubsForGroup2 = (req, res, next) ->
  kword = 'savedpubsforgroup'
  __fname=kword
  fqGroupName = req.query.fqGroupName
  ifHaveEmail __fname, req, res, (email) ->
        _doSearchForGroup email, fqGroupName, 'pub', createSavedPubTemplates, res, kword, 
                httpcallbackmaker(__fname, req, res, next), {titlefield:'titles', namefield:'bibcodes'}

  
  
getSavedObsvsForGroup2 = (req, res, next) ->
  kword = 'savedobsvsforgroup'
  fqGroupName = req.query.fqGroupName
  __fname=kword
  ifHaveEmail __fname, req, res, (email) ->
        _doSearchForGroup email, fqGroupName, 'obsv', createSavedObsvTemplates, res, kword, httpcallbackmaker(__fname, req, res, next),
                    {titlefield:'obsvtitles', namefield:'targets'}



#BUG How about deletion from savedInGroups hash

                    
removeSearchesFromGroup = (email, group, searchids, callback) ->
    _doRemoveSearchesFromGroup(email, group, 'search', searchids, callback)
    #if savedBy is you, you must be a menber of the group so dont test membership of group
    #shortcircuit by getting those searchids which the user herself has saved
    

removePubsFromGroup = (email, group, docids, callback) ->
    _doRemoveSearchesFromGroup(email, group, 'pub', docids, callback)


      
removeObsvsFromGroup = (email, group, obsids, callback) ->
   _doRemoveSearchesFromGroup(email, group, 'obsv', obsids, callback)
# Create a function to delete a single search or publication
#   funcname is used to create a console log message of 'In ' + funcname
#     on entry to the function
#   idname is the name of the key used to identify the item to delete
#     in the JSON payload
#   delItems is the routine we call to delete multiple elements



#terms = {action, fqGroupName?, [search|pub|obsv]}        
deleteItemsWithJSON = (funcname, idname, delItems) ->
  return (terms, req, res, next) ->
    console.log ">> In #{funcname}"
    ifHaveEmail funcname, req, res, (email) ->
      action = terms.action
      group=terms.fqGroupName ? 'default'
      delids = if isArray terms.items then terms.items else [terms.items]

      if action is "delete" and delids.length > 0
        delItems email, group, delids, httpcallbackmaker(funcname, req, res, next)
      else
        failedRequest res



exports.deleteSearchesFromGroup = deleteItemsWithJSON "deleteSearchesFromGroup", "searches", removeSearchesFromGroup
exports.deletePubsFromGroup     = deleteItemsWithJSON "deletePubsFromGroup",     "pubs",    removePubsFromGroup
exports.deleteObsvsFromGroup     = deleteItemsWithJSON "deleteObsvsFromGroup",     "obsvs",    removeObsvsFromGroup


exports.saveSearchesToGroup = saveSearchesToGroup
exports.savePubsToGroup = savePubsToGroup
exports.saveObsvsToGroup = saveObsvsToGroup

exports.getSavedSearchesForGroup = getSavedSearchesForGroup
exports.getSavedPubsForGroup = getSavedPubsForGroup
exports.getSavedObsvsForGroup = getSavedObsvsForGroup

