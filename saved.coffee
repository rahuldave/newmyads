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




_doSaveSearch = (savedBy, objects, searchtype, callback) ->
  saveTime = new Date().getTime()
  savedtype="saved#{searchtype}"
  savedset="saved#{searchtype}:#{savedBy}"
  for idx in [0...objects.length]
    theobject=objects[idx]
    savedItem = theobject[savedtype]
    hsets = (['hset', thekey, savedItem, theobject[key]] for key of theobject)
    margsi = hsets.concat [['zadd', savedset, saveTime, savedItem]]
    margs = margs.concat margsi
  redis_client.multi(margs).exec (err2, reply) -> successfulRequest res

saveSearches = (objectsToSave, req, res, next) ->
  console.log __fname="saveSearches"
  ifHaveEmail __fname, req, res, (savedBy) ->
      # keep as a multi even though now a single addition
      _doSaveSearch savedBy, objectsToSave, 'search',  httpcallbackmaker(__fname, req, res, next)


savePubs = (objectsToSave, req, res, next) ->
  console.log __fname="savePubs"
  o2s = ({savedbibcodes:pubbibcode, savedtitles:pubtitle, savedpub:savedpub} for {savedpub, pubbibcode, pubtitle} in objectsToSave)
  ifHaveEmail __fname, req, res, (savedBy) ->
     _doSaveSearch savedBy, o2s, 'pub', httpcallbackmaker(__fname, req, res, next)
      
saveObsvs = (objectsToSave, req, res, next) ->
  console.log __fname="saveObsvs"
  o2s = ({savedtargets:obsvtarget, savedobsvtitles:obsvtitle, savedobsv:savedobsv} for {savedobsv, obsvtarget, obsvtitle} in objectsToSave)
  ifHaveEmail __fname, req, res, (savedBy) ->
      _doSaveSearch savedBy, o2s, 'obsv', httpcallbackmaker(__fname, req, res, next)
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

_doSaveSearchToGroup = (savedBy, fqGroupName, savedhashlist, searchtype, callback) ->
    saveTime = new Date().getTime()
    savedtype="saved#{searchtype}"
    taggedtype="tagged#{searchtype}"
    #hashes with JSON
    allTagsHash = "tagged:#{savedBy}:#{searchtype}"
    allTagsGroupHash = "tagged:#{fqGroupName}:#{searchtype}"
    #sets
    tagsForUser = "tags:#{savedBy}"
    tagsForGroup = "tags:#{fqGroupName}"
    savedSearches=(savedhashlist[idx][savedtype] for idx in [0...savedhashlist.length])
    #['sadd', "#{taggedtype}:#{grp}:#{tagName}", tobeTaggedSearchesToUse[idx]]
    #//['sadd', "tags:#{grp}", tagName]
    #//['hset', "tagged:#{grp}:#{searchtype}",tobeTaggedSearchesToUse[idx],outJSON[idx] ]
    redis_client.sismember "members:#{fqGroupName}", savedBy, (err, is_member)->
        if err
            return callback err, is_member
        #BUG I do not check if user has saved stuff first. Shouldnt I do that?
        if is_member
            margs=(['hget', "savedby:#{fqGroupName}", savedhash[savedtype]] for savedhash in savedhashlist)
            redis_client.multi(margs).exec (err2, replies) ->
                if err2
                    return callback err2, replies
                console.log 'REPLIES', replies, savedhashlist
                counter=0
                margs=[]
                for idx in [0...replies.length]
                    console.log "kkk", idx, replies[idx]
                    savedSearch=savedSearches[idx]
                    if replies[idx] isnt null
                        console.log "saved before", savedSearch, replies[idx]
                        savedByJSON = JSON.parse replies[idx]
                        savedByJSON.push(savedBy)
                    else
                        #first time saving
                        console.log "first time saving", savedSearch, savedBy, fqGroupName
                        savedByJSON = [savedBy]
                    #if the same thing is saved again, the score is updated to the latest time, not ideal, but how else to do in context of sorted set
                    #it would seem that a relational database is a better option for this.    
                    margsi = [
                      ['zadd', "saved#{searchtype}:#{savedBy}:#{fqGroupName}", saveTime, savedSearch],
                      ['zadd', "saved#{searchtype}:#{fqGroupName}", saveTime, savedSearch],
                      ['hset', "savedby:#{fqGroupName}", savedSearch, JSON.stringify savedByJSON],
                    ]
                    margs = margs.concat margsi
                redis_client.smembers "memberof:#{savedBy}", (errb, mygroups) ->
                    if errb
                        return callback errb, mygroups
                    
                    ######################
                    margs2=(['hget', "savedInGroups:#{searchtype}", thesearch] for thesearch in savedSearches)
                    console.log "margs2", margs2
                    redis_client.multi(margs2).exec (err4, groupJSONList) ->
                        console.log "groupJSONList", groupJSONList, err4
                        if err4
                            return callback err4, groupJSONList
                        outJSON=[]
                        outgroupsforuser=[]
                        for groupJSON in groupJSONList
                            if groupJSON is null
                                grouplist=[fqGroupName]
                                #outgrouplist=[fqGroupName]
                            else
                                grouplist = JSON.parse groupJSON
                                #outgrouplist = [ele for ele in grouplist when ele in mygroups]
                                grouplist.push(fqGroupName) #we dont check for uniqueness, no sets in json (now we want it multiple?)
                                #outgrouplist.push(fqGroupName)
                            outJSON.push JSON.stringify(grouplist)
                            #outgroupsforuser.push(outgrouplist)
                        console.log "outjsom", outJSON, outgroupsforuser, savedSearches
                        margs3 = (['hset', "savedInGroups:#{searchtype}", savedSearches[i], outJSON[i]] for i in [0...savedSearches.length])
                        console.log "margs3", margs3
                        margs=margs.concat margs3
                        
                        margs22=(['hget', allTagsHash, thesearch] for thesearch in savedSearches)
                        console.log "margs22", margs22
                        redis_client.multi(margs22).exec (err22, tagJSONList) ->
                            console.log "tagJSONList", tagJSONList, err22
                            if err22
                                return callback err22, tagJSONList
                            margs33=(['hget', "tagged:#{fqGroupName}:#{searchtype}", thesearch] for thesearch in savedSearches)
                            redis_client.multi(margs33).exec (err33, tagGroupJSONList) ->
                                console.log "tagGroupJSONList", tagGroupJSONList, err33
                                if err33
                                    return callback err33, tagGroupJSONList
                                    
                                searchgrouplist=[]
                                for idx in [0...savedSearches.length]
                                    if tagGroupJSONList[idx] is null
                                        taglist=[]
                                    else
                                        taglist = JSON.parse tagGroupJSONList[idx]
                                    searchgrouplist.push(taglist)
                                margstagcmds=[]
                                for idx in [0...savedSearches.length]                           
                                    if tagJSONList[idx] 
                                        taglist = JSON.parse tagJSONList[idx]
                                        taggrouplist = searchgrouplist[idx]
                                        mergedtaglist = taggrouplist.concat taglist
                                        mergedJSON= JSON.stringify mergedtaglist
                                        grptadd1=(['sadd', "tags:#{fqGroupName}", ele] for ele in taglist )
                                        grptadd2=(['sadd', "#{taggedtype}:#{fqGroupName}:#{ele}", savedSearches[idx]] for ele in taglist)
                                        grptadd3=[['hset', "tagged:#{fqGroupName}:#{searchtype}", savedSearches[idx], mergedJSON] ]
                                        margstagcmds = margstagcmds.concat grptadd1
                                        margstagcmds = margstagcmds.concat grptadd2
                                        margstagcmds = margstagcmds.concat grptadd3
                                margs=margs.concat margstagcmds
                                redis_client.multi(margs).exec  callback             
                
                
        else
            return callback err, is_member
              
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
   
_doSearchForGroup = (email, fqGroupName, searchtype, templateCreatorFunc, res, kword, callback, augmenthash=null) ->
    nowDate = new Date().getTime()
    allTagsGroupHash = "tagged:#{fqGroupName}:#{searchtype}"
    redis_client.sismember "members:#{fqGroupName}", email, (erra, saved_p)->
            #should it be an error is user is not member of group? (thats what it is now)
            if erra
                return callback erra, saved_p
            if saved_p
                redis_client.smembers "memberof:#{email}", (errb, groups) ->
                    if errb
                        return callback errb, groups
                    getSortedElementsAndScores false, "saved#{searchtype}:#{fqGroupName}", (err2, searches) ->
                        if err2
                            console.log "*** getSaved#{searchtype}ForGroup2: failed for email=#{email} err=#{err2}"
                            return callback err2, searches
                        console.log searchtype, 'searches.elements', searches.elements
                        margs=(['hget', "savedby:#{fqGroupName}", ele] for ele in searches.elements)
                        redis_client.multi(margs).exec (errm, savedbysjsonlist) ->
                            if errm
                                return callback errm, savedbysjsonlist
                            savedBys=[]
                            for ele in savedbysjsonlist
                                console.log "ELE", ele
                                if not ele
                                    savedBys.push([])
                                else
                                    parsedsavedbys=JSON.parse ele
                                    savedbystoadd = (ele for ele in parsedsavedbys)
                                    savedBys.push(savedbystoadd)
                            margs2=(['hget', "savedInGroups:#{searchtype}", ele] for ele in searches.elements)
                            console.log "<<<<<#{searchtype}", margs2
                            redis_client.multi(margs2).exec (err, groupjsonlist) ->
                                if err
                                    return callback err, groupjsonlist
                                console.log ">>>>>>>#{searchtype}", searches.elements, groupjsonlist
                                savedingroups=[]
                                for ele in groupjsonlist
                                    if not ele
                                        savedingroups.push([])
                                    else
                                        parsedgroups=JSON.parse ele
                                        groupstoadd = (ele for ele in parsedgroups when ele in groups)
                                        savedingroups.push(groupstoadd)
                                margs22=(['hget', allTagsGroupHash, ele] for ele in searches.elements)
                                console.log "<<<<<", margs22
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
                                    #savedingroups = (JSON.parse ele for ele in groupjsonlist)
                                    console.log "<<<<<<<<<<<<<<<<>", savedingroups
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
            else
              console.log "*** getSaved#{searchtype}ForGroup2: membership failed for email=#{email} err=#{erra}"
              return callback erra, saved_p
      
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

#BUG How about deletion from savedInGroups hash
_doRemoveSearchesFromGroup = (email, group, searchtype, searchids, callback) ->
    keyemail = "saved#{searchtype}:#{email}"
    keygroup = "saved#{searchtype}:#{group}"
    keyemailgroup = "saved#{searchtype}:#{email}:#{group}"
    keys4savedbyhash = "savedby:#{group}"
    savedingroupshash = "savedInGroups:#{searchtype}"

    margs=(['zrank', keyemailgroup, sid] for sid in searchids)

    # What about the nested multis..how does this affect atomicity?
    hashkeystodelete=[]

    redis_client.multi(margs).exec (err, replies) ->
        if err
            return callback err, replies
        ranks=(rank for rank in replies when rank isnt null)
        sididxs=(sididx for sididx in [0...replies.length] when replies[sididx] isnt null)
        console.log "sididxs", sididxs
        mysidstodelete=(searchids[idx] for idx in sididxs)
        #Should error out here if null so that we can use that in UI to say you are not owner, or should we?
        margs2=(['hget', savedingroupshash, searchids[idx]] for idx in sididxs)
        redis_client.multi(margs2).exec (errj, groupjsonlist) ->
            if errj
                return callback errj, groupjsonlist
            console.log "o>>>>>>>", searchids, groupjsonlist
            savedingroups = (JSON.parse ele for ele in groupjsonlist)
            console.log "savedingroups", savedingroups
            newsavedgroups=[]
            for grouplist in savedingroups
                console.log 'grouplist', grouplist
                newgrouplist=[]
                newgrouplist.push(ele) for ele in grouplist when ele isnt group
                console.log 'newgrouplist', newgrouplist
                newsavedgroups.push(newgrouplist)
            
            newgroupjsonlist = (JSON.stringify glist for glist in newsavedgroups)
            #BUG if empty json array should we delete key in hash? (above and below this line)
            savedingroupshashcmds=(['hset', savedingroupshash, searchids[i], newgroupjsonlist[i]] for i in sididxs)
            #Get those added by user to group from the given sids. I have substituted null for nil
            console.log "savedingroupshashcmds", savedingroupshashcmds
            margs22=(['hget', keys4savedbyhash, searchids[idx]] for idx in sididxs)
            redis_client.multi(margs22).exec (errj2, userjsonlist) ->
                if errj2
                    return callback errj2, userjsonlist
                console.log "oo>>>>>>>", searchids, userjsonlist
                savedbyusers = (JSON.parse ele for ele in userjsonlist)
                console.log "savedbyusers", savedbyusers
                newsavedbyusers=[]
                for userlist in savedbyusers
                    console.log 'userlist', userlist
                    newuserlist=[]
                    newuserlist.push(ele) for ele in userlist when ele isnt email
                    console.log 'newuserlist', newuserlist
                    newsavedbyusers.push(newuserlist)

                newuserjsonlist = (JSON.stringify ulist for ulist in newsavedbyusers)
                #BUG if empty json array should we delete key in hash? (above and below this line)
                savedbyusershashcmds=(['hset', keys4savedbyhash, searchids[i], newuserjsonlist[i]] for i in sididxs)
                #Get those added by user to group from the given sids. I have substituted null for nil
                console.log "savedbyusershashcmds", savedbyusershashcmds
            
                margsgroup = (['zremrangebyrank', keygroup, rid, rid] for rid in ranks)
                margsemailgroup = (['zremrangebyrank', keyemailgroup, rid, rid] for rid in ranks)
                margsi=margsgroup.concat margsemailgroup
                margs3=margsi.concat savedingroupshashcmds
                margs4=margs3.concat savedbyusershashcmds
                #Doing all the multis here together preserves atomicity since these are destructive
                #they should all be done or not at all
                console.log 'margs4',margs4
                redis_client.multi(margs4).exec callback
                    
removeSearchesFromGroup = (email, group, searchids, callback) ->
    _doRemoveSearchesFromGroup(email, group, 'search', searchids, callback)
    #if savedBy is you, you must be a menber of the group so dont test membership of group
    #shortcircuit by getting those searchids which the user herself has saved
    
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

removePubsFromGroup = (email, group, docids, callback) ->
    _doRemoveSearchesFromGroup(email, group, 'pub', docids, callback)


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
      
removeObsvsFromGroup = (email, group, obsids, callback) ->
   _doRemoveSearchesFromGroup(email, group, 'obsv', obsids, callback)
# Create a function to delete a single search or publication
#   funcname is used to create a console log message of 'In ' + funcname
#     on entry to the function
#   idname is the name of the key used to identify the item to delete
#     in the JSON payload
#   delItems is the routine we call to delete multiple elements

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

exports.deleteSearchesFromGroup = deleteItemsWithJSON "deleteSearchesFromGroup", "searches", removeSearchesFromGroup
exports.deletePubsFromGroup     = deleteItemsWithJSON "deletePubsFromGroup",     "pubs",    removePubsFromGroup
exports.deleteObsvsFromGroup     = deleteItemsWithJSON "deleteObsvsFromGroup",     "obsvs",    removeObsvsFromGroup

exports.saveSearch = saveSearch
exports.savePub = savePub
exports.saveObsv = saveObsv

exports.saveSearchesToGroup = saveSearchesToGroup
exports.savePubsToGroup = savePubsToGroup
exports.saveObsvsToGroup = saveObsvsToGroup

exports.getSavedSearches2 = getSavedSearches2
exports.getSavedSearchesForGroup2 = getSavedSearchesForGroup2
exports.getSavedPubs2 = getSavedPubs2
exports.getSavedPubsForGroup2 = getSavedPubsForGroup2
exports.getSavedObsvs2 = getSavedObsvs2
exports.getSavedObsvsForGroup2 = getSavedObsvsForGroup2

