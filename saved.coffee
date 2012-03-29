###
Handles saved items - e.g. searches and publications - that involves
accessing information from Redis.
###

#BUG: when you and i boh save into a group, my removing stuff removes both our handiwork due to the set
#nature of things. The place to fix this is in the hash, where multiple existence of the same group
#in the value of a key means that we cant really delete it, because someone has a reference to it.

#BUG..where do I do redis quits? I might be losing memory!! Also related to scripts not exiting, surely!

sdb = require "./savedb"
requests = require("./requests-myads")
failedRequest = requests.failedRequest
successfulRequest = requests.successfulRequest
ifLoggedIn = requests.ifLoggedIn
httpcallbackmaker = requests.httpcallbackmaker

utils = require("./utils")
CONNECTION = utils.getRedisClient()
ifHaveEmail = utils.ifHaveEmail
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




_doSaveSearch = (savedBy, objects, searchtype, callback) ->
  saveTime = new Date().getTime()
  sdb=savedb.getSaveDb(CONNECTION, lastcb)
  margs=[]
  for idx in [0...objects.length]
    theobject=objects[idx]
    sdb.saveItem(theobject, searchtype, savedBy) 
  sdb.execute()   
  

saveSearches = (payload, req, res, next) ->
  console.log __fname="saveSearches"
  console.log "In #{__fname}: cookies=#{req.cookies} payload=#{payload}"
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (savedBy) ->
      # keep as a multi even though now a single addition
      dajson = JSON.parse payload
      objectsToSave = if isArray dajson then dajson else [dajson]
      _doSaveSearch savedBy, objectsToSave, 'search', lastcb


savePubs = (payload, req, res, next) ->
  #payload [{savedpub, pubbibcode, pubtitle}]
  console.log __fname="savePubs"
  console.log "In #{__fname}: cookies=#{req.cookies} payload=#{payload}"
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (savedBy) ->
      dajson = JSON.parse payload
      objectsToSave = if isArray dajson then dajson else [dajson]
      o2s = ({savedbibcodes:pubbibcode, savedtitles:pubtitle, savedpub:savedpub} for {savedpub, pubbibcode, pubtitle} in objectsToSave)
      _doSaveSearch savedBy, o2s, 'pub', lastcb
      
saveObsvs = (payload, req, res, next) ->
  console.log __fname="saveObsvs"
  console.log "In #{__fname}: cookies=#{req.cookies} payload=#{payload}"
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (savedBy) ->
      dajson = JSON.parse payload
      objectsToSave = if isArray dajson then dajson else [dajson]
      o2s = ({savedtargets:obsvtarget, savedobsvtitles:obsvtitle, savedobsv:savedobsv} for {savedobsv, obsvtarget, obsvtitle} in objectsToSave)
      _doSaveSearch savedBy, o2s, 'obsv', lastcb

  
#each searchObject is {savedsearch|savedpub|savedobsv}
#practically i want users to have already saved an object to save it to a group
#in actuality i dont require it. and when i delete i dont check if user has individually
#saved it. we may want to patch that, or just let it be. TODO
#BUG all this should happen atomically

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
    sdb=savedb.getSaveDb(CONNECTION, callback)
    sdb.getSavedItems searchtype, email,  (err, searches) ->
      console.log searchtype, '================', searches
      if augmenthash is null
          view = templateCreatorFunc searchtype, nowDate, searches.elements, searches.scores
          sdb.lastcallback err, view
      else
          sb.getArchetypesForSavedItems "saved#{augmenthash.titlefield}", searches, (err3, titles) ->
            console.log 'ITLES', titles
            sdb.getArchetypesForSavedItems "saved#{augmenthash.namefield}", searches, (err4, names) ->
              console.log 'AMES', names, 'BEEP', searches
              view = templateCreatorFunc searchtype, nowDate, searches.elements, searches.scores, names, titles
              sdb.lastcallback err4, view


getSavedPubs = (req, res, next) ->
  console.log __fname = 'savedpubs'
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (email) ->
      _getSavedItems email, 'pub', createSavedTemplates, lastcb, {titlefield:'titles', namefield:'bibcodes'}  
      
getSavedSearches = (req, res, next) ->
  console.log __fname = 'savedsearches'
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (email) ->
      _getSavedItems email, 'search', createSavedTemplates, lastcb
      
getSavedObsvs = (req, res, next) ->
  console.log __fname = 'savedobsvs'
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (email) ->
      _getSavedItems email, 'obsv', createSavedTemplates, lastcb, {titlefield:'obsvtitles', namefield:'targets'}          
   


#BUG NONE OF THIS REMOVAL TRIGGERS ANYTHING WITH GROUPS OR TAGS, YET
# Remove the list of searchids, associated with the given
# user cookie, from Redis.
#
# At present we require that searchids not be empty; this may
# be changed.


      

removeItems = (email, itemtype, itemids, lastcb) ->
  if itemids.length is 0
    return lastcb "No #{itemtype}s to delete", null
  sdb=savedb.getSaveDb(CONNECTION, lastcb)
  sdb.removeItems(itemids, itemtype, email) 
  sdb.execute()

deleteItem = (funcname, searchtype, delItemsFunc) ->
  idname="#{searchtype}id"
  return (payload, req, res, next) ->
    console.log ">> In #{funcname}"
    ecb = httpcallbackmaker(funcname, req, res, next)
    ifHavePermissions req, res, ecb, (email) ->
      terms = JSON.parse payload
      console.log ">> JSON payload=#{payload}"
      delid = terms[idname]
      if delid?
        delItemsFunc email, searchtype, [delid], ecb
      else
        ecb "not delete", null

# Create a function to delete multiple search or publication items
#   funcname is used to create a console log message of 'In ' + funcname
#     on entry to the function
#   idname is the name of the key used to identify the items to delete
#     in the JSON payload
#   delItems is the routine we call to delete multiple elements

deleteItems = (funcname, searchtype, delItemsFunc) ->
  return (payload, req, res, next) ->
    console.log ">> In #{funcname}"
    ecb = httpcallbackmaker(funcname, req, res, next)
    ifHavePermissions req, res, ecb, (email) ->
      terms = JSON.parse payload
      console.log ">> JSON payload=#{payload}"
      action = terms.action
      delids = if isArray terms[idname] then terms[idname] else [terms[idname]]

      if action is "delete" and delids.length > 0
        delItemsFunc email, searchtype, delids, ecb
      else
        ecb "not delete", null





    
exports.deleteSearch   = deleteItem "deleteSearch", "search", removeItems
exports.deletePub      = deleteItem "deletePub",    "pub",    removeItems
exports.deleteObsv      = deleteItem "deleteObsv",    "obsv",    removeItems

exports.deleteSearches = deleteItems "deleteSearches", "search", removeItems
exports.deletePubs     = deleteItems "deletePubs",     "pub",    removeItems
exports.deleteObsvs     = deleteItems "deleteObsvs",     "obsv",    removeItems


exports.saveSearch = saveSearch
exports.savePub = savePub
exports.saveObsv = saveObsv

exports.saveSearches = saveSearches
exports.savePubs = savePubs
exports.saveObsvs = saveObsvs



exports.getSavedSearches = getSavedSearches
exports.getSavedPubs = getSavedPubs
exports.getSavedObsvs = getSavedObsvs
exports.getSavedSearches2 = getSavedSearches2
exports.getSavedPubs2 = getSavedPubs2
exports.getSavedObsvs2 = getSavedObsvs2

