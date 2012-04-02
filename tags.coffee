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
_doSaveSearchToTag = (taggedBy, tagName, savedhashlist, searchtype, callback) ->
  tdb = tagdb.getTagDb(CONNECTION, callback)
  tdb.saveItemsToTag savedBy, tagName, savedhashlist, searchtype
  tdb.execute()

              
saveSearchesToTag = ({tagName, objectsToSave}, req, res, next) ->
  console.log __fname="saveSearchestoTag"
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (savedBy) ->
      # keep as a multi even though now a single addition
      _doSaveSearchToTag savedBy, tagName, objectsToSave, 'search'

      


savePubsToTag = ({tagName, objectsToSave}, req, res, next) ->
  console.log __fname="savePubsToTag"
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (savedBy) ->
     _doSaveSearchToTag savedBy, tagName, objectsToSave, 'pub'
      

      
saveObsvsToTag = ({tagName, objectsToSave}, req, res, next) ->
  console.log __fname="saveObsvsToTag"
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (savedBy) ->
      _doSaveSearchToTag savedBy, tagName, objectsToSave, 'obsv'
            


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
  
_getSavedItemsForTag = (email, tagname, searchtype, templateCreatorFunc, callback, augmenthash=null) ->
    nowDate = new Date().getTime()
    tdb = tagdb.getTagDb(CONNECTION, callback)
    if email is 'all'
      cfunc=tdb.getSavedItemsForTag
    else
      cfunc=tdb.getSavedItemsForTagAndUser
    cfunc email, tagname, searchtype,  (err, searches) ->
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
  ifHavePermissions req, res, lastcb, (email) ->
    _getSavedItemsForTag email, tagName, 'search', createSavedTemplates, lastcb
  
  


  
getSavedPubsForTag = (req, res, next) ->
  console.log __fname = 'savedpubsfortag'
  tagName = req.query.tagName
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (email) ->
    _getSavedItemsForTag email, tagName, 'pub', createSavedTemplates, lastcb, {titlefield:'titles', namefield:'bibcodes'}

  
#BUG: getting permissions right for next 2 may be iffy due to different consumers of API  
getSavedObsvsForTag = (req, res, next) ->
  console.log __fname = 'savedobsvsfortag'
  tagName = req.query.tagName
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (email) ->
    _getSavedItemsForTag email, tagName, 'obsv', createSavedTemplates, lastcb,
                    {titlefield:'obsvtitles', namefield:'targets'}
#GET

getAllTagsForUser = (req, res, next) ->
  console.log __fname = 'gettagsforuser'
  lastcb = httpcallbackmaker(__fname, req, res, next)
  searchtype=req.query.searchtype ? null
  ifHavePermissions req, res, lastcb, (email) ->
    tdb = tagdb.getTagDb(CONNECTION, callback)
      tdb.getAllTagsForUser email, searchtype

#also the thing that gets tags for an app        
getAllTagsForType= (req, res, next) ->
  console.log __fname = 'gettagsfortype'
  lastcb = httpcallbackmaker(__fname, req, res, next)
  searchtype=req.query.searchtype
  ifHavePermissions req, res, lastcb, (email) ->
    tdb = tagdb.getTagDb(CONNECTION, callback)
    tdb.getAllTagsForType searchtype


#BUG get tags for group and all group related things later
#BUG: we also need to support tag unions and? intersections.

#BUG the bug where i can delete things of yours in a group (here in a tag) remains.
_doRemoveSearchesFromTag = (email, tagName, searchtype, searchids, callback) ->
    taggedtype="tagged#{searchtype}"
    allTagsHash = "tagged:#{taggedBy}:#{searchtype}"
    taggedAllSet="#{taggedtype}:#{tagName}"
    taggedUserSet="#{taggedtype}:#{taggedBy}:#{tagName}"

    margs=(['sismember', taggedUserSet, sid] for sid in searchids)

    # What about the nested multis..how does this affect atomicity?
    hashkeystodelete=[]

    redis_client.multi(margs).exec (err, replies) ->
        if err
            return callback err, replies
        #ranks=(rank for rank in replies when rank isnt 0)
        sididxs=(sididx for sididx in [0...replies.length] when replies[sididx] isnt 0)
        console.log "sididxs", sididxs
        mysidstodelete=(searchids[idx] for idx in sididxs)
        #Should error out here if null so that we can use that in UI to say you are not owner, or should we?
        margs2=(['hget', allTagsHash, searchids[idx]] for idx in sididxs)
        redis_client.multi(margs2).exec (errj, tagjsonlist) ->
            if errj
                return callback errj, tagjsonlist
            console.log "o>>>>>>>", searchids, tagjsonlist
            savedintags = (JSON.parse ele for ele in tagjsonlist)
            console.log "savedintags", savedintags
            newsavedtags=[]
            for taglist in savedintags
                console.log 'taglist', taglist
                newtaglist=[]
                newtaglist.push(ele) for ele in taglist when ele isnt tagName
                console.log 'newtaglist', newtaglist
                newsavedtags.push(newtaglist)
            
            newtagjsonlist = (JSON.stringify tlist for tlist in newsavedtags)
            #BUG if empty json array should we delete key in hash? (above and below this line)
            savedintagshashcmds=(['hset', allTagsHash, searchids[i], newtagjsonlist[i]] for i in sididxs)
            #Get those added by user to group from the given sids. I have substituted null for nil
            console.log "savedintagshashcmds", savedintagshashcmds
            
            
            margsuser = (['srem', taggedAllSet, sid] for sid in mysidstodelete)
            margsall = (['srem', taggedUserSet, sid] for sid in mysidstodelete)
            margsi=margsuser.concat margsall
            margs4=margsi.concat savedingroupshashcmds
            #Doing all the multis here together preserves atomicity since these are destructive
            #they should all be done or not at all
            console.log 'margs4',margs4
            redis_client.multi(margs4).exec callback
                    
removeSearchesFromTag = (email, tagName, searchids, callback) ->
    _doRemoveSearchesFromTag(email, tagName, 'search', searchids, callback)
    #if savedBy is you, you must be a menber of the group so dont test membership of group
    #shortcircuit by getting those searchids which the user herself has saved
    

removePubsFromTag = (email, tagName, docids, callback) ->
    _doRemoveSearchesFromTag(email, tagName, 'pub', docids, callback)

      
removeObsvsFromTag = (email, tagName, obsids, callback) ->
   _doRemoveSearchesFromTag(email, tagName, 'obsv', obsids, callback)


getTagsSavedInForItemsAndUser = (req, res, next) ->
  console.log __fname = 'tagssavedinforitemsanduser'
  searchtype = req.query.searchtype
  saveditems = req.query.saveditems
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (email) ->
    tdb = tagdb.getTagDb(CONNECTION, lastcb)
    tdb.getTagsSavedInForItemsAndUser email, searchtype, saveditems

#we can also do this on a per app/type basis
getTagsSavedInForItems = (req, res, next) ->
  console.log __fname = 'tagssavedinforitems'
  searchtype = req.query.searchtype
  saveditems = req.query.saveditems
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (email) ->
    tdb = tagdb.getTagDb(CONNECTION, lastcb)
    tdb.getTagsSavedInForItems searchtype, saveditems

isArray = `function (o) {
    return (o instanceof Array) ||
        (Object.prototype.toString.apply(o) === '[object Array]');
};`

#BUG How about deletion from savedInGroups hash
removeItemsFromTag = (email, tag, searchtype, searchids, lastcb) ->
  tdb = tagdb.getTagDb(CONNECTION, lastcb)
  tdb.removeItemsFromTag email, tag, searchtype, searchids
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
    ifHavePermissions req, res, ecb, (email) ->
      action = terms.action
      tag=terms.tagName ? 'default'
      delids = if isArray terms.items then terms.items else [terms.items]

      if action is "delete" and delids.length > 0
        delItemsFunc email, tag, searchtype, delids, ecb
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

exports.getTagsForUser = getTagsForUser
#exports.getTagsForGroup = getTagsForGroup
