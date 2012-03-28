removeSearches = (email, group, searchids, lastcb) ->
  if searchids.length is 0
    return lastcb "No searches to delete", null

  key = "savedsearch:#{email}"
  # with Redis v2.4 we will be able to delete multiple keys with
  # a single zrem call
  margs = (['zrem', key, sid] for sid in searchids)
  redis_client.multi(margs).exec (err2, reply) ->
    #if error reurn error, else return true...would be better with better response info
    return lastcb err2, reply


# Similar to removeSearches but removes publications.

removePubs = (email, group, docids, lastcb) ->
  if docids.length is 0
    return lastcb "No pubs to delete", null

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
    return lastcb err2, reply


removeObsvs = (email, group, docids, lastcb) ->
  if docids.length is 0
    return lastcb "No obsvs to delete", null

  console.log ">> removeObsvs docids=#{docids}"
  obsvkey = "savedobsv:#{email}"
  # In Redis 2.4 zrem and hdel can be sent multiple keys: fix sometime
  margs1 = (['zrem', obsvkey, docid] for docid in docids)
  margs=margs1
  redis_client.multi(margs).exec (err2, reply) ->
    return lastcb err2, reply


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
    