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
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (authorizedEntity) ->
      # keep as a multi even though now a single addition
      sgdb = savegroupdb.getDb(CONNECTION, lastcb)
      sgdb.saveItemsToGroup authorizedEntity, fqGroupName, objectsToSave, 'search'
      sgdb.execute()


savePubsToGroup = ({fqGroupName, objectsToSave}, req, res, next) ->
  console.log __fname="savePubsToGroup"
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (authorizedEntity) ->
      # keep as a multi even though now a single addition
      sgdb = savegroupdb.getDb(CONNECTION, lastcb)
      sgdb.saveItemsToGroup authorizedEntity, fqGroupName, objectsToSave, 'pub'
      sgdb.execute()
      
saveObsvsToGroup = ({fqGroupName, objectsToSave}, req, res, next) ->
  console.log __fname="saveObsvToGroup"
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (authorizedEntity) ->
      # keep as a multi even though now a single addition
      sgdb = savegroupdb.getDb(CONNECTION, lastcb)
      sgdb.saveItemsToGroup authorizedEntity, fqGroupName, objectsToSave, 'obsv'
      sgdb.execute()
            
saveItemsPublic = ({searchtype, objectsToSave}, req, res, next) ->
  console.log __fname="saveitemspublic"
  lastcb = httpcallbackmaker(__fname, req, res, next)
  fqGroupName = 'public'
  #BUG: ifhavepermissions will need to have a dictionary additional argument used to establish permissins
  #against a set of capabilities. The fact that this is public will be in ther rather than replied on from
  #query.
  ifHavePermissions req, res, lastcb, (authorizedEntity) ->
      # keep as a multi even though now a single addition
      sgdb = savegroupdb.getDb(CONNECTION, lastcb)
      sgdb.saveItemsToGroup authorizedEntity, fqGroupName, objectsToSave, searchtype
      sgdb.execute()

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
  
_getSavedItemsFromGroup = (authorizedEntity, groupname, searchtype, templateCreatorFunc, callback, augmenthash=null) ->
    nowDate = new Date().getTime()
    sgdb = savegroupdb.getDb(CONNECTION, callback)
    if authorizedEntity is 'all'
      cfunc = sgdb.getSavedItemsForGroup
    else
      cfunc = sgdb.getSavedItemsForUserAndGroup
    cfunc authorizedEntity, groupname, searchtype,  (err, searches) ->
      console.log searchtype, '================', searches
      if augmenthash is null
          view = templateCreatorFunc searchtype, nowDate, searches.elements, searches.scores
          sgdb.lastcallback err, view
      else
          sgdb.sdb.getArchetypesForSavedItems "saved#{augmenthash.titlefield}", searches, (err3, titles) ->
            console.log 'ITLES', titles
            sgdb.sdb.getArchetypesForSavedItems "saved#{augmenthash.namefield}", searches, (err4, names) ->
              console.log 'AMES', names, 'BEEP', searches
              view = templateCreatorFunc searchtype, nowDate, searches.elements, searches.scores, names, titles
              sgdb.lastcallback err4, view


#BUG: Dont we also want something which gives only my stuff in group?

getPublicItems = (req, res, next) ->
  console.log __fname = 'publicitems'
  fqGroupName = 'public'
  searchtype = req.query.searchtype
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (authorizedEntity) ->
    _getSavedItemsFromGroup authorizedEntity, fqGroupName, searchtype, createSavedTemplates, lastcb

getSavedSearchesForGroup = (req, res, next) ->
  console.log __fname = 'savedsearchesforgroup'
  fqGroupName = req.query.fqGroupName
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (authorizedEntity) ->
    _getSavedItemsFromGroup authorizedEntity, fqGroupName, 'search', createSavedTemplates, lastcb
  
  


  
getSavedPubsForGroup = (req, res, next) ->
  console.log __fname = 'savedpubsforgroup'
  fqGroupName = req.query.fqGroupName
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (authorizedEntity) ->
    _getSavedItemsFromGroup authorizedEntity, fqGroupName, 'pub', createSavedTemplates, lastcb, {titlefield:'titles', namefield:'bibcodes'}

  
  
getSavedObsvsForGroup = (req, res, next) ->
  console.log __fname = 'savedobsvsforgroup'
  fqGroupName = req.query.fqGroupName
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (authorizedEntity) ->
    _getSavedItemsFromGroup authorizedEntity, fqGroupName, 'obsv', createSavedTemplates, lastcb,
                    {titlefield:'obsvtitles', namefield:'targets'}



getSavedBysForItemsInGroup = (req, res, next) ->
  console.log __fname = 'savedbysforitemsingroup'
  fqGroupName = req.query.fqGroupName
  #searchtype = req.query.searchtype
  #searchtype dosent matter here. BUG with apps maybe it has to matter.
  saveditems = req.query.saveditems
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (authorizedEntity) ->
    sgdb = savegroupdb.getDb(CONNECTION, lastcb)
    sgdb.getSavedBysForItems fqGroupName, saveditems

getGroupsSavedInForItemsAndUser = (req, res, next) ->
  console.log __fname = 'groupssavedinforitemsanduser'
  searchtype = req.query.searchtype
  saveditems = req.query.saveditems
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (authorizedEntity) ->
    sgdb = savegroupdb.getDb(CONNECTION, lastcb)
    sgdb.getGroupsSavedInForItemsAndUser authorizedEntity, searchtype, saveditems
    #lastcb will be automatically called on success, too, with the groups

#Tjis one is to be called by an app if the app is given the appropriate permissions
getGroupsSavedInForItems = (req, res, next) ->
  console.log __fname = 'groupssavedinforitems'
  searchtype = req.query.searchtype
  saveditems = req.query.saveditems
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (authorizedEntity) ->
    sgdb = savegroupdb.getDb(CONNECTION, lastcb)
    sgdb.getGroupsSavedInForItems authorizedEntity, searchtype, saveditems
    #lastcb will be automatically called on success, too, with the groups

#BUG How about deletion from savedInGroups hash
removeItemsFromGroup = (authorizedEntity, group, searchtype, searchids, lastcb) ->
  sgdb = savegroupdb.getDb(CONNECTION, lastcb)
  sgdb.removeItemsFromGroup authorizedEntity, group, searchtype, searchids
  sgdb.execute()
                    

# Create a function to delete a single search or publication
#   funcname is used to create a console log message of 'In ' + funcname
#     on entry to the function
#   idname is the name of the key used to identify the item to delete
#     in the JSON payload
#   delItems is the routine we call to delete multiple elements


#terms = {action, fqGroupName?, [search|pub|obsv]}
#Because of post payload has been parsed into JSON for us.  
#Q is payload pub or items? seems its items      
deleteItemsWithJSON = (funcname, searchtype, delItemsFunc) ->
  return (terms, req, res, next) ->
    console.log ">> In #{funcname}"
    ifHavePermissions req, res, ecb, (authorizedEntity) ->
      action = terms.action
      group=terms.fqGroupName ? 'public'
      delids = if isArray terms.items then terms.items else [terms.items]

      if action is "delete" and delids.length > 0
        delItemsFunc authorizedEntity, group, searchtype, delids, ecb
      else
        ecb "not delete", null


deleteItemsPublic = (terms, req, res, next, searchtype) ->
  curriedfunc = deleteItemsWithJSON "deleteitemspublic", searchtype, removeItemsFromGroup
  curriedfunc terms, req, res, next

exports.deleteSearchesFromGroup = deleteItemsWithJSON "deleteSearchesFromGroup", "search", removeItemsFromGroup
exports.deletePubsFromGroup     = deleteItemsWithJSON "deletePubsFromGroup",     "pub",    removeItemsFromGroup
exports.deleteObsvsFromGroup     = deleteItemsWithJSON "deleteObsvsFromGroup",     "obsv",    removeItemsFromGroup

exports.deleteItemsPublic = deleteItemsPublic
exports.saveItemsPublic = saveItemsPublic

exports.saveSearchesToGroup = saveSearchesToGroup
exports.savePubsToGroup = savePubsToGroup
exports.saveObsvsToGroup = saveObsvsToGroup

exports.getSavedSearchesForGroup = getSavedSearchesForGroup
exports.getSavedPubsForGroup = getSavedPubsForGroup
exports.getSavedObsvsForGroup = getSavedObsvsForGroup

exports.getGroupsSavedInForItems = getGroupsSavedInForItems
exports.getGroupsSavedInForItemsAndUser = getGroupsSavedInForItemsAndUser
exports.getSavedBysForItemsInGroup = getSavedBysForItemsInGroup
exports.getPublicItems = getPublicItems
