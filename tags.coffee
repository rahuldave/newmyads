###
Handles saved items - e.g. searches and publications - that involves
accessing information from Redis.
###


utils = require("./utils")
redis_client = utils.getRedisClient()
requests = require("./requests-myads")
failedRequest = requests.failedRequest
successfulRequest = requests.successfulRequest
ifLoggedIn = requests.ifLoggedIn
httpcallbackmaker = requests.httpcallbackmaker

tagsdb = require("./tagsdb")
CONNECTION = utils.getRedisClient()
ifHavePermissions = utils.ifHavePermissions
ifHaveAuth = utils.ifHaveAuth
ifHavePermissions = utils.ifHavePermissions
getSortedElements = utils.getSortedElements
getSortedElementsAndScores = utils.getSortedElementsAndScores
timeToText = utils.timeToText
searchToText = utils.searchToText


#notice that this dosent do all the saving in one transaction. this is a BUG. fix it in groups too.
_doSaveSearchToTag = (authorizedEntity, tagName, savedhashlist, searchtype, callback) ->
  tdb = tagdb.getTagDb(CONNECTION, callback)
  tdb.saveItemsToTag authorizedEntity, tagName, savedhashlist, searchtype
  tdb.execute()

              
saveSearchesToTag = ({tagName, objectsToSave}, req, res, next) ->
  console.log __fname="saveSearchestoTag"
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (authorizedEntity) ->
      # keep as a multi even though now a single addition
      _doSaveSearchToTag authorizedEntity, tagName, objectsToSave, 'search'

      


savePubsToTag = ({tagName, objectsToSave}, req, res, next) ->
  console.log __fname="savePubsToTag"
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (authorizedEntity) ->
     _doSaveSearchToTag authorizedEntity, tagName, objectsToSave, 'pub'
      

      
saveObsvsToTag = ({tagName, objectsToSave}, req, res, next) ->
  console.log __fname="saveObsvsToTag"
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (authorizedEntity) ->
      _doSaveSearchToTag authorizedEntity, tagName, objectsToSave, 'obsv'
            


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
  
_getSavedItemsForTag = (authorizedEntity, tagname, searchtype, templateCreatorFunc, callback, augmenthash=null) ->
    nowDate = new Date().getTime()
    tdb = tagdb.getTagDb(CONNECTION, callback)
    if authorizedEntity is 'all'
      cfunc=tdb.getSavedItemsForTag
    else
      cfunc=tdb.getSavedItemsForTagAndUser
    cfunc authorizedEntity, tagname, searchtype,  (err, searches) ->
      console.log searchtype, '================', searches
      if augmenthash is null
          view = templateCreatorFunc searchtype, nowDate, searches.elements, searches.scores
          tdb.lastcallback err, view
      else
          tdb.sdb.getArchetypesForSavedItems "saved#{augmenthash.titlefield}", searches, (err3, titles) ->
            console.log 'ITLES', titles
            tdb.sdb.getArchetypesForSavedItems "saved#{augmenthash.namefield}", searches, (err4, names) ->
              console.log 'AMES', names, 'BEEP', searches
              view = templateCreatorFunc searchtype, nowDate, searches.elements, searches.scores, names, titles
              tdb.lastcallback err4, view
      
getSavedSearchesForTag = (req, res, next) ->
  console.log __fname = 'savedsearchesfortag'
  tagName = req.query.tagName
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (authorizedEntity) ->
    _getSavedItemsForTag authorizedEntity, tagName, 'search', createSavedTemplates, lastcb
  
  


  
getSavedPubsForTag = (req, res, next) ->
  console.log __fname = 'savedpubsfortag'
  tagName = req.query.tagName
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (authorizedEntity) ->
    _getSavedItemsForTag authorizedEntity, tagName, 'pub', createSavedTemplates, lastcb, {titlefield:'titles', namefield:'bibcodes'}

  
#BUG: getting permissions right for next 2 may be iffy due to different consumers of API  
getSavedObsvsForTag = (req, res, next) ->
  console.log __fname = 'savedobsvsfortag'
  tagName = req.query.tagName
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (authorizedEntity) ->
    _getSavedItemsForTag authorizedEntity, tagName, 'obsv', createSavedTemplates, lastcb,
                    {titlefield:'obsvtitles', namefield:'targets'}
#GET

getAllTagsForUser = (req, res, next) ->
  console.log __fname = 'gettagsforuser'
  lastcb = httpcallbackmaker(__fname, req, res, next)
  searchtype=req.query.searchtype ? null
  ifHavePermissions req, res, lastcb, (authorizedEntity) ->
    tdb = tagdb.getTagDb(CONNECTION, callback)
      tdb.getAllTagsForUser authorizedEntity, searchtype

#also the thing that gets tags for an app        
getAllTagsForType= (req, res, next) ->
  console.log __fname = 'gettagsfortype'
  lastcb = httpcallbackmaker(__fname, req, res, next)
  searchtype=req.query.searchtype
  ifHavePermissions req, res, lastcb, (authorizedEntity) ->
    tdb = tagdb.getTagDb(CONNECTION, callback)
    tdb.getAllTagsForType searchtype


#BUG get tags for group and all group related things later
#BUG: we also need to support tag unions and? intersections.

#BUG the bug where i can delete things of yours in a group (here in a tag) remains.

                    

getTagsSavedInForItemsAndUser = (req, res, next) ->
  console.log __fname = 'tagssavedinforitemsanduser'
  searchtype = req.query.searchtype
  saveditems = req.query.saveditems
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (authorizedEntity) ->
    tdb = tagdb.getTagDb(CONNECTION, lastcb)
    tdb.getTagsSavedInForItemsAndUser authorizedEntity, searchtype, saveditems

#we can also do this on a per app/type basis
getTagsSavedInForItems = (req, res, next) ->
  console.log __fname = 'tagssavedinforitems'
  searchtype = req.query.searchtype
  saveditems = req.query.saveditems
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (authorizedEntity) ->
    tdb = tagdb.getTagDb(CONNECTION, lastcb)
    tdb.getTagsSavedInForItems searchtype, saveditems

isArray = `function (o) {
    return (o instanceof Array) ||
        (Object.prototype.toString.apply(o) === '[object Array]');
};`

#BUG How about deletion from savedInGroups hash
removeItemsFromTag = (authorizedEntity, tag, searchtype, searchids, lastcb) ->
  tdb = tagdb.getTagDb(CONNECTION, lastcb)
  tdb.removeItemsFromTag authorizedEntity, tag, searchtype, searchids
  tdb.execute()
                    

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
      tag=terms.tagName ? 'default'
      delids = if isArray terms.items then terms.items else [terms.items]

      if action is "delete" and delids.length > 0
        delItemsFunc authorizedEntity, tag, searchtype, delids, ecb
      else
        ecb "not delete", null




#Currently, no delete tags from search, but thats another way to do it
exports.deleteSearchesFromTag = deleteItemsWithJSON "deleteSearchesFromTag", "search", removeItemsFromTag
exports.deletePubsFromTag     = deleteItemsWithJSON "deletePubsFromTag",     "pub",    removeItemsFromTag
exports.deleteObsvsFromTag     = deleteItemsWithJSON "deleteObsvsFromTag",     "obsv",    removeItemsFromTag

#Currently, no saveTagsToSearch, another way to do it, perhaps more intuitive
exports.saveSearchesToTag = saveSearchesToTag
exports.savePubsToTag = savePubsToTag
exports.saveObsvsToTag = saveObsvsToTag

#For reporting functions, want (a) tags for a search (b) searches for a tag (of different kinds)
#(a) must be insinuated in via saved.coffee, like its done with groups. Later it could be made an api function.
exports.getSavedSearchesForTag = getSavedSearchesForTag

exports.getSavedPubsForTag = getSavedPubsForTag

exports.getSavedObsvsForTag = getSavedObsvsForTag

exports.getAllTagsForUser = getAllTagsForUser
exports.getAllTagsForType = getAllTagsForType
exports.getTagsSavedInForItems = getTagsSavedInForItems
exports.getTagsSavedInForItemsAndUser = getTagsSavedInForItemsAndUser
#exports.getTagsForGroup = getTagsForGroup
