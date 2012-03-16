###
Handles saved items - e.g. searches and publications - that involves
accessing information from Redis.
###

#BUG: when you and i boh save into a group, my removing stuff removes both our handiwork due to the set
#nature of things. The place to fix this is in the hash, where multiple existence of the same group
#in the value of a key means that we cant really delete it, because someone has a reference to it.

#BUG..where do I do redis quits? I might be losing memory!! Also related to scripts not exiting, surely!
utils = require("./utils")
redis_client = utils.getRedisClient()

requests = require("./requests-myads")
failedRequest = requests.failedRequest
successfulRequest = requests.successfulRequest
ifLoggedIn = requests.ifLoggedIn
httpcallbackmaker = requests.httpcallbackmaker

ifHaveEmail = utils.ifHaveEmail
ifHaveAuth = utils.ifHaveAuth
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

class Userdb
  constructor: (client, callback, errorcallback) ->
    @connection = client
    @callback = callback
    @errorcallback = errorcallback
    @transaction=[]

  ifHaveAuth: (req, res, lastcallback, callback) ->
    ifLoggedIn req, res, (loginid) =>
      @connection.get "email:#{loginid}", (err, email) ->
          console.log "email is", email, err
          if err
              return lastcallback err, email
          if email
              callback email
          else
              return lastcallback err, email

class Savedb
  constructor: (client, callback) ->
    @connection = client
    @callback = callback
    @transaction=[]

  addActions: (actions) ->
    actionlist = if isArray actions then actions else [actions]
    @transaction = @transaction.concat actionlist

  clear: () ->
    @transaction=[]

  execute: (cb=null) ->
    @connection.multi(@transaction).exec (err, reply) =>
      #currently zero transaction ob both error and successful reply
      console.log "@transaction", @transaction
      callb = if cb then cb else @callback
      @clear()
      return callb err, reply

  saveItem: (itemobject, itemtype, savedBy) ->
    #BUG: how do we prevent adding an item twice: zadd ought to just update timestamp
    #or we should throw an error
    savetime = new Date().getTime()
    savedtype="saved#{itemtype}"
    savedset="saved#{itemtype}:#{savedBy}"
    saveditem = itemobject[savedtype]
    actions = (['hset', thekey, saveditem, itemobject[thekey]] for thekey of itemobject)
    actions = actions.concat [['zadd', savedset, savetime, saveditem]]
    @addActions actions


_doSaveSearch = (savedBy, objects, searchtype, callback) ->
  saveTime = new Date().getTime()
  savedb = new Savedb(redis_client, callback)
  margs=[]
  for idx in [0...objects.length]
    theobject=objects[idx]
    savedb.saveItem(theobject, searchtype, savedBy) 
  savedb.execute()   
  

saveSearches = (payload, req, res, next) ->
  console.log __fname="saveSearches"
  console.log "In #{__fname}: cookies=#{req.cookies} payload=#{payload}"
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHaveAuth req, res, lastcb, (savedBy) ->
      # keep as a multi even though now a single addition
      dajson = JSON.parse payload
      objectsToSave = if isArray dajson then dajson else [dajson]
      _doSaveSearch savedBy, objectsToSave, 'search', lastcb


savePubs = (payload, req, res, next) ->
  #payload [{savedpub, pubbibcode, pubtitle}]
  console.log __fname="savePubs"
  console.log "In #{__fname}: cookies=#{req.cookies} payload=#{payload}"
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHaveAuth req, res, lastcb, (savedBy) ->
      dajson = JSON.parse payload
      objectsToSave = if isArray dajson then dajson else [dajson]
      o2s = ({savedbibcodes:pubbibcode, savedtitles:pubtitle, savedpub:savedpub} for {savedpub, pubbibcode, pubtitle} in objectsToSave)
      _doSaveSearch savedBy, o2s, 'pub', lastcb
      
saveObsvs = (payload, req, res, next) ->
  console.log __fname="saveObsvs"
  console.log "In #{__fname}: cookies=#{req.cookies} payload=#{payload}"
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHaveAuth req, res, lastcb, (savedBy) ->
      dajson = JSON.parse payload
      objectsToSave = if isArray dajson then dajson else [dajson]
      o2s = ({savedtargets:obsvtarget, savedobsvtitles:obsvtitle, savedobsv:savedobsv} for {savedobsv, obsvtarget, obsvtitle} in objectsToSave)
      _doSaveSearch savedBy, o2s, 'obsv', lastcb

#################################################################################
saveSearch = (payload, req, res, next) ->
  console.log "In saveSearch: cookies=#{req.cookies} payload=#{payload}"
  saveTime = new Date().getTime()

  ifLoggedIn req, res, (loginid) ->
    jsonObj = JSON.parse payload
    savedSearch = jsonObj.savedsearch

    redis_client.get "email:#{loginid}", (err, email) ->
      # keep as a multi even though now a single addition
      margs = [['zadd', "savedsearch:#{email}", saveTime, savedSearch]]
      redis_client.multi(margs).exec (err2, reply) -> successfulRequest res


savePub = (payload, req, res, next) ->
  console.log "In savePub: cookies=#{req.cookies} payload=#{payload}"
  saveTime = new Date().getTime()

  ifLoggedIn req, res, (loginid) ->
    jsonObj = JSON.parse payload
    savedPub = jsonObj.savedpub
    bibCode = jsonObj.pubbibcode
    title = jsonObj.pubtitle

    redis_client.get "email:#{loginid}", (err, email) ->

      # Moved to a per-user database for titles and bibcodes so that
      # we can delete this information. I am thinking that this could
      # just be asked via AJAX requests of Solr by the client in the
      # pubsub branch so could be removed.
      #
      margs = [['hset', "savedbibcodes", savedPub, bibCode],
               ['hset', "savedtitles", savedPub, title],
               ['zadd', "savedpub:#{email}", saveTime, savedPub]]
      redis_client.multi(margs).exec (err2, reply) -> successfulRequest res

saveObsv = (payload, req, res, next) ->
  console.log "In saveObsv: cookies=#{req.cookies} payload=#{payload}"
  saveTime = new Date().getTime()

  ifLoggedIn req, res, (loginid) ->
    jsonObj = JSON.parse payload
    savedObsv = jsonObj.savedobsv
    target = jsonObj.obsvtarget
    title = jsonObj.obsvtitle

    redis_client.get "email:#{loginid}", (err, email) ->

      # Moved to a per-user database for titles and bibcodes so that
      # we can delete this information. I am thinking that this could
      # just be asked via AJAX requests of Solr by the client in the
      # pubsub branch so could be removed.
      #
      margs = [['hset', "savedtargets", savedObsv, target],
               ['hset', "savedobsvtitles", savedObsv, title],
               ['zadd', "savedobsv:#{email}", saveTime, savedObsv]]
      redis_client.multi(margs).exec (err2, reply) -> successfulRequest res
      
#each searchObject is {savedsearch|savedpub|savedobsv}
#practically i want users to have already saved an object to save it to a group
#in actuality i dont require it. and when i delete i dont check if user has individually
#saved it. we may want to patch that, or just let it be. TODO
#BUG all this should happen atomically

# Modify the object view to add in the needed values
# given the search results. This was originally used with Mustache
# views - hence the terminology - but the data is now passed
# back to the client as JSON.
#
createSavedSearchTemplates = (nowDate, searchkeys, searchtimes, searchbys, groupsin, tagsin) ->
  view = {}
  #console.log "VIEW", view
  nsearch = searchkeys.length

  if nsearch is 0
    view.hassearches = false
    view.savedsearches = []

  else
    view.hassearches = true

    makeTemplate = (ctr) ->
      key = searchkeys[ctr]
      time = searchtimes[ctr]
      out =
        searchuri: key
        searchby: searchbys[ctr]
        groupsin: groupsin[ctr]
        tagsin: tagsin[ctr]
        searchtext: searchToText key
        searchtime: time
        searchtimestr: timeToText nowDate, time
        searchctr: ctr
      return out

    view.savedsearches = (makeTemplate i for i in [0..nsearch-1])

  return view

createSavedPubTemplates = (nowDate, pubkeys, pubtimes, bibcodes, pubtitles, searchbys, groupsin, tagsin) ->
  view = {}
  npub = pubkeys.length

  if npub is 0
    view.haspubs = false
    view.savedpubs = []

  else
    view.haspubs = true

    makeTemplate = (ctr) ->
      bibcode = bibcodes[ctr]
      linkuri = "bibcode%3A#{ bibcode.replace(/&/g, '%26') }"
      out =
        pubid: pubkeys[ctr]
        searchby: searchbys[ctr]
        groupsin: groupsin[ctr]
        tagsin: tagsin[ctr]
        linktext: pubtitles[ctr]
        linkuri: linkuri
        pubtime: pubtimes[ctr]
        pubtimestr: timeToText nowDate, pubtimes[ctr]
        bibcode: bibcode
        pubctr: ctr
      return out

    view.savedpubs = (makeTemplate i for i in [0..npub-1])

  return view

createSavedObsvTemplates = (nowDate, obsvkeys, obsvtimes, targets, obsvtitles, searchbys, groupsin, tagsin) ->
  view = {}
  nobsv = obsvkeys.length

  if nobsv is 0
    view.hasobsvs = false
    view.savedobsvs = []

  else
    view.hasobsvs = true

    makeTemplate = (ctr) ->
      target = targets[ctr]
      #linkuri = "bibcode%3A#{ bibcode.replace(/&/g, '%26') }"
      linkuri=obsvkeys[ctr]
      out =
        obsvid: obsvkeys[ctr]
        searchby: searchbys[ctr]
        groupsin: groupsin[ctr]
        tagsin: tagsin[ctr]
        linktext: obsvkeys[ctr]
        linkuri: linkuri
        obsvtime: obsvtimes[ctr]
        obsvtimestr: timeToText nowDate, obsvtimes[ctr]
        target: target
        obsvctr: ctr
      return out

    view.savedobsvs = (makeTemplate i for i in [0..nobsv-1])

  return view
  

#Current BUG: security issue--leaks all groups the item has been saved in, not just mine
_doSearch = (email, searchtype, templateCreatorFunc, res, kword, callback, augmenthash=null) ->
    nowDate = new Date().getTime()
    allTagsHash = "tagged:#{email}:#{searchtype}"
    redis_client.smembers "memberof:#{email}", (err, groups) ->
        if err
            return callback err, groups
        getSortedElementsAndScores false, "saved#{searchtype}:#{email}", (err2, searches) ->
            if err2
                return callback err2, searches
            margs2=(['hget', "savedInGroups:#{searchtype}", ele] for ele in searches.elements)
            console.log "margs2<<<<<", margs2
            redis_client.multi(margs2).exec (errg, groupjsonlist) ->
                if errg
                    return callback errg, groupjsonlist
                savedingroups=[]
                for ele in groupjsonlist
                    if not ele
                        savedingroups.push([])
                    else
                        parsedgroups=JSON.parse ele
                        groupstoadd = (ele for ele in parsedgroups when ele in groups)
                        savedingroups.push(groupstoadd)
                margs22=(['hget', allTagsHash, ele] for ele in searches.elements)
                console.log "margs22<<<<<", margs22
                redis_client.multi(margs22).exec (errg22, tagjsonlist) ->
                    if errg22
                        return callback errg22, tagjsonlist
                    savedintags=[]
                    for ele in tagjsonlist
                        if not ele
                            savedintags.push([])
                        else
                            parsedtags=JSON.parse ele
                            tagstoadd = (ele for ele in parsedtags)
                            savedintags.push(tagstoadd)        
                    #savedingroups = (JSON.parse (ele ? '[]') for ele in groupjsonlist)
                    console.log "<<<<<<<<<<<<<<<<>", savedingroups, savedintags
                    savedBys=(email for ele in searches.elements)
                    if augmenthash is null
                        view = templateCreatorFunc nowDate, searches.elements, searches.scores, savedBys, savedingroups, savedintags
                        callback err, view
                    else
                        if searches.elements.length == 0
                            titles=[]
                            names=[]
                            view = templateCreatorFunc nowDate, searches.elements, searches.scores, names, titles, savedBys, savedingroups, savedintags
                            return callback err, view
                        redis_client.hmget "saved#{augmenthash.titlefield}", searches.elements..., (err3, titles) ->
                            if err3
                                console.log "titlefield error"
                                return callback err3, titles
                            redis_client.hmget "saved#{augmenthash.namefield}", searches.elements..., (err4, names) ->
                                if err4
                                    console.log "namefield error"
                                    return callback err4, names
                                view = templateCreatorFunc nowDate, searches.elements, searches.scores, names, titles, savedBys, savedingroups, savedintags
                                callback err4, view

getSavedPubs2 = (req, res, next) ->
  kword = 'savedpubs'
  __fname=kword
  ifHaveEmail __fname, req, res, (email) ->
      _doSearch email, 'pub', createSavedPubTemplates, res, kword, httpcallbackmaker(__fname, req, res, next), {titlefield:'titles', namefield:'bibcodes'}  
      
getSavedSearches2 = (req, res, next) ->
  kword = 'savedsearches'
  __fname=kword
  ifHaveEmail __fname, req, res, (email) ->
      _doSearch email, 'search', createSavedSearchTemplates, res, kword, httpcallbackmaker(__fname, req, res, next)
      
getSavedObsvs2 = (req, res, next) ->
  kword = 'savedobsvs'
  __fname=kword
  ifHaveEmail __fname, req, res, (email) ->
      _doSearch email, 'obsv', createSavedObsvTemplates, res, kword, httpcallbackmaker(__fname, req, res, next), {titlefield:'obsvtitles', namefield:'targets'}          
   

# Remove the list of searchids, associated with the given
# user cookie, from Redis.
#
# At present we require that searchids not be empty; this may
# be changed.

removeSearches = (res, loginid, group, searchids) ->
  if searchids.length is 0
    console.log "ERROR: removeSearches called with empty searchids list; loginid=#{loginid}"
    failedRequest res
    return

  redis_client.get "email:#{loginid}", (err, email) ->
    key = "savedsearch:#{email}"
    # with Redis v2.4 we will be able to delete multiple keys with
    # a single zrem call
    margs = (['zrem', key, sid] for sid in searchids)
    redis_client.multi(margs).exec (err2, reply) ->
      console.log "Removed #{searchids.length} searches"
      successfulRequest res


# Similar to removeSearches but removes publications.

removePubs = (res, loginid, group, docids) ->
  if docids.length is 0
    console.log "ERROR: removePubs called with empty docids list; loginid=#{loginid}"
    failedRequest res
    return

  redis_client.get "email:#{loginid}", (err, email) ->
    console.log ">> removePubs docids=#{docids}"
    pubkey = "savedpub:#{email}"
    #titlekey = "savedtitles:#{email}"
    #bibkey = "savedbibcodes:#{email}"

    # In Redis 2.4 zrem and hdel can be sent multiple keys
    margs1 = (['zrem', pubkey, docid] for docid in docids)
    #margs2 = (['hdel', titlekey, docid] for docid in docids)
    #margs3 = (['hdel', bibkey, docid] for docid in docids)
    #margs = margs1.concat margs2, margs3
    margs=margs1
    redis_client.multi(margs).exec (err2, reply) ->
      console.log "Removed #{docids.length} pubs"
      successfulRequest res


removeObsvs = (res, loginid, group, docids) ->
  if docids.length is 0
    console.log "ERROR: removeObsvs called with empty docids list; loginid=#{loginid}"
    failedRequest res
    return

  redis_client.get "email:#{loginid}", (err, email) ->
    console.log ">> removeObsvs docids=#{docids}"
    obsvkey = "savedobsv:#{email}"
    # In Redis 2.4 zrem and hdel can be sent multiple keys: fix sometime
    margs1 = (['zrem', obsvkey, docid] for docid in docids)
    margs=margs1
    redis_client.multi(margs).exec (err2, reply) ->
      console.log "Removed #{docids.length} obsvs"
      successfulRequest res
      


deleteItem = (funcname, idname, delItems) ->
  return (payload, req, res, next) ->
    console.log ">> In #{funcname}"
    ifLoggedIn req, res, (loginid) ->
      jsonObj = JSON.parse payload
      delid = jsonObj[idname]
      group='default'
      console.log "deleteItem: logincookie=#{loginid} item=#{delid}"
      if delid?
        delItems res, loginid, group, [delid]
      else
        failedRequest res

# Create a function to delete multiple search or publication items
#   funcname is used to create a console log message of 'In ' + funcname
#     on entry to the function
#   idname is the name of the key used to identify the items to delete
#     in the JSON payload
#   delItems is the routine we call to delete multiple elements

deleteItems = (funcname, idname, delItems) ->
  return (payload, req, res, next) ->
    console.log ">> In #{funcname}"
    ifLoggedIn req, res, (loginid) ->
      terms = JSON.parse payload
      console.log ">> JSON payload=#{payload}"

      action = terms.action
      group=terms.group ? 'default'
      delids = if isArray terms[idname] then terms[idname] else [terms[idname]]

      if action is "delete" and delids.length > 0
        delItems res, loginid, group, delids
      else
        failedRequest res

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



    
exports.deleteSearch   = deleteItem "deleteSearch", "searchid", removeSearches
exports.deletePub      = deleteItem "deletePub",    "pubid",    removePubs
exports.deleteObsv      = deleteItem "deleteObsv",    "obsvid",    removeObsvs

exports.deleteSearches = deleteItems "deleteSearches", "searchid", removeSearches
exports.deletePubs     = deleteItems "deletePubs",     "pubid",    removePubs
exports.deleteObsvs     = deleteItems "deleteObsvs",     "obsvid",    removeObsvs


exports.saveSearch = saveSearch
exports.savePub = savePub
exports.saveObsv = saveObsv

exports.saveSearches = saveSearches
exports.savePubs = savePubs
exports.saveObsvs = saveObsvs


exports.getSavedSearches2 = getSavedSearches2
exports.getSavedPubs2 = getSavedPubs2
exports.getSavedObsvs2 = getSavedObsvs2

