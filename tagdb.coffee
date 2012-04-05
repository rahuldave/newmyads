groupdb = require "./groupdb"
savedb = require "./savedb"
savegroupsb = require "./savegroupdb"
_ = require "./underscore"
#@connection = require("redis").createClient()
isArray = `function (o) {
    return (o instanceof Array) ||
        (Object.prototype.toString.apply(o) === '[object Array]');
};`

lstorempty = (x) ->
  if x is null or x is undefined
    return []
  if isArray x
    return x
  else
    return [x]

class Tagdb
  constructor: (client, lastcallback, itransaction=null) ->
    @connection = client
    @lastcallback = lastcallback
    if itransaction is null
      @transaction=[]
    else
      @transaction=itransaction
    #@gdb = groupdb.getDb client, lastcallback
    #BUG bottom depends on app so we have an inversion of calling here...better done by pub/sub
    #or separate clien call or something?
    @sdb = savedb.getDb client, lastcallback
    #@sgdb = savegroupdb.getDb client, lastcallback

  addActions: (actions) ->
    actionlist = if isArray actions then actions else [actions]
    @transaction = @transaction.concat actionlist

  clear: () ->
    @transaction=[]

  execute: (cb=null, lcb=null) ->
    lcallb = if lcb then lcb else @lastcallback
    callb = if cb then cb else @lastcallback
    @connection.multi(@transaction).exec (err, reply) =>
      #currently zero transaction ob both error and successful reply
      console.log "@transaction", @transaction
      @clear()
      if err
        return lcallb err, reply
      return callb err, reply

  #BUG: how are we making sure an item has really already been saved?
  saveItemsToTag: (authorizedEntity, tagName, savedhashlist, searchtype) ->
    saveTime = new Date().getTime()
    savedtype="saved#{searchtype}"
    taggedtype="tagged#{searchtype}"
    #BELOW: Hash for now but well could be set
    tagsForTypeHash = "tagged:#{searchtype}"
    tagsForTypeList = "tags:#{searchtype}"
    #Above: hash or set? And do we want tags for app+group?
    tagsForUserAndTypeHash = "tagged:#{authorizedEntity}:#{searchtype}"
    taggedUserAndTypeSet = "taggeditems:#{authorizedEntity}:#{searchtype}"
    #a hash keyed by the search item or URI.
    tagsForUserList = "tags:#{authorizedEntity}"
    tagsForUserAndTypeList = "tags:#{authorizedEntity}:#{searchtype}"
    #all the tags that the user ever did (used for tag display on saved page)
    #(similar thing must exist forgroups)
    itemsForTagAndTypeSet="#{taggedtype}:#{tagName}"
    #items in a particular tag, by type/app
    itemsForTagAndTypeAndUserSet="#{taggedtype}:#{authorizedEntity}:#{tagName}"
    #items like above, but per user (similar for group)
    # ASSUMPTION: already saved by user
    #shouldnt we check this?. Also cheack this in groups. BUG BUG
    #authorizedEntityUserSet="#{savedtype}:#{authorizedEntity}"
    savedSearches=(savedhashlist[idx][savedtype] for idx in [0...savedhashlist.length])
    margs=[]
    @getTagsSavedInForItems searchtype, savedSearches, (err, tags) =>
      @getTagsSavedinForItemsAndUser authorizedEntity, searchtype, savedSearches, (err, tagsuser) =>
        for idx in [0...savedSearches.length]
          savedSearch=savedSearches[idx]
          tags[idx].push(tagName)
          tagsuser[idx].push(tagName)
          tags[idx] = _.uniq tags[idx]
          tagsuser[idx] = _.uniq tagsuser[idx]
          margsi = [
            ['hset', tagsForTypeHash, savedSearch, JSON.stringify tags[idx]],
            ['hset', tagsForUserAndTypeHash, savedSearch, JSON.stringify tagsuser[idx]],
          ]
          margs = margs.concat margsi
        margs = margs.concat (['zadd', itemsForTagAndTypeAndUserSet, saveTime, s] for s in savedSearches)
        margs = margs.concat (['zadd', itemsForTagAndTypeSet, saveTime, s] for s in savedSearches)
        margs = margs.concat (['zadd', taggedUserAndTypeSet, saveTime, s] for s in savedSearches)
        margs = margs.concat [['lpush', tagsForUserList, tagName]]
        margs = margs.concat [['lpush', tagsForTypeList, tagName]]
        margs = margs.concat [['lpush', tagsForUserAndTypeList, tagName]]
        @addActions margs

getSavedItemsForTag: (authorizedEntity, fqGroupName, searchtype, cb=null, lcb=null) ->
  savedtype="saved#{searchtype}"
  taggedtype="tagged#{searchtype}"
  tagsForTypeHash = "tagged:#{searchtype}"
  tagsForTypeList = "tags:#{searchtype}"
  tagsForUserAndTypeHash = "tagged:#{authorizedEntity}:#{searchtype}"
  tagsForUserList = "tags:#{authorizedEntity}"
  itemsForTagAndTypeSet="#{taggedtype}:#{tagName}"
  itemsForTagAndTypeAndUserSet="#{taggedtype}:#{authorizedEntity}:#{tagName}"
  nowDate = new Date().getTime()
  lcallb = if lcb then lcb else @lastcallback
  callb = if cb then cb else @lastcallback
  getSortedElementsAndScores false, itemsForTagAndTypeSet, (err2, searches) =>
    if err
      return lcallb err, searches
    return callb err, searches

getSavedItemsForTagAndUser: (authorizedEntity, tagName, searchtype, cb=null, lcb=null) ->
  savedtype="saved#{searchtype}"
  taggedtype="tagged#{searchtype}"
  tagsForTypeHash = "tagged:#{searchtype}"
  tagsForTypeList = "tags:#{searchtype}"
  tagsForUserAndTypeHash = "tagged:#{authorizedEntity}:#{searchtype}"
  tagsForUserList = "tags:#{authorizedEntity}"
  itemsForTagAndTypeSet="#{taggedtype}:#{tagName}"
  itemsForTagAndTypeAndUserSet="#{taggedtype}:#{authorizedEntity}:#{tagName}"
  nowDate = new Date().getTime()
  lcallb = if lcb then lcb else @lastcallback
  callb = if cb then cb else @lastcallback
  getSortedElementsAndScores false, itemsForTagAndTypeAndUserSet, (err2, searches) =>
    if err
      return lcallb err, searches
    return callb err, searches

getAllTagsForType: (searchtype, cb=null, lcb=null) ->
  tagsForTypeList = "tags:#{searchtype}"
  lcallb = if lcb then lcb else @lastcallback
  callb = if cb then cb else @lastcallback
  @connection.lrange tagsForTypeList, (err, replies) ->
    if err
      return lcallb err, replies
    else
      return callb err, replies

getAllTagsForUser: (authorizedEntity, searchtype, cb=null, lcb=null) ->
  if searchtype
    tagsForUserList = "tags:#{authorizedEntity}:#{searchtype}"
  else
   tagsForUserList = "tags:#{authorizedEntity}" 
  lcallb = if lcb then lcb else @lastcallback
  callb = if cb then cb else @lastcallback
  @connection.lrange tagsForUserList, (err, replies) ->
    if err
      return lcallb err, replies
    else
      return callb err, replies

getTagsSavedInForItems: (searchtype, saveditems, cb=null, lcb=null) ->
  savedtype="saved#{searchtype}"
  taggedtype="tagged#{searchtype}"
  tagsForTypeHash = "tagged:#{searchtype}"
  tagsForTypeList = "tags:#{searchtype}"
  tagsForUserAndTypeHash = "tagged:#{authorizedEntity}:#{searchtype}"
  tagsForUserList = "tags:#{authorizedEntity}"
  itemsForTagAndTypeSet="#{taggedtype}:#{tagName}"
  itemsForTagAndTypeAndUserSet="#{taggedtype}:#{authorizedEntity}:#{tagName}"
  lcallb = if lcb then lcb else @lastcallback
  callb = if cb then cb else @lastcallback
  margs=(['hget', tagsForTypeHash, saveditem] for saveditem in saveditems)
  @connection.multi(margs).exec (err, replies) =>
    if err2
      return lcallb err, replies
    else
      tags = (lstorempty ele  for ele in replies)
      callb err, tags

getTagsSavedInForItemsAndUser: (authorizedEntity, searchtype, saveditems, cb=null, lcb=null) ->
  savedtype="saved#{searchtype}"
  taggedtype="tagged#{searchtype}"
  tagsForTypeHash = "tagged:#{searchtype}"
  tagsForTypeList = "tags:#{searchtype}"
  tagsForUserAndTypeHash = "tagged:#{authorizedEntity}:#{searchtype}"
  tagsForUserList = "tags:#{authorizedEntity}"
  itemsForTagAndTypeSet="#{taggedtype}:#{tagName}"
  itemsForTagAndTypeAndUserSet="#{taggedtype}:#{authorizedEntity}:#{tagName}"

  lcallb = if lcb then lcb else @lastcallback
  callb = if cb then cb else @lastcallback
  margs=(['hget', tagsForUserAndTypeHash, saveditem] for saveditem in saveditems)
  @connection.multi(margs).exec (err, replies) =>
    if err2
      return lcallb err, replies
    else
      tags= (lstorempty ele  for ele in replies)
      callb err, tags

getTaggedItemsForUser: (authorizedEntity,  searchtype, cb=null, lcb=null) ->
  nowDate = new Date().getTime()
  lcallb = if lcb then lcb else @lastcallback
  callb = if cb then cb else @lastcallback
  getSortedElementsAndScores false, "taggeditems:#{authorizedEntity}:#{searchtype}", (err2, searches) =>
    if err
      return lcallb err, searches
    return callb err, searches

removeItemsFromTag: (authorizedEntity, tagName, searchtype, searchids) ->
  saveTime = new Date().getTime()
  savedtype="saved#{searchtype}"
  taggedtype="tagged#{searchtype}"
  #BELOW: Hash for now but well could be set
  tagsForTypeHash = "tagged:#{searchtype}"
  tagsForTypeList = "tags:#{searchtype}"
  #Above: hash or set? And do we want tags for app+group?
  tagsForUserAndTypeHash = "tagged:#{authorizedEntity}:#{searchtype}"
  taggedUserAndTypeSet = "taggeditems:#{authorizedEntity}:#{searchtype}"
  #a hash keyed by the search item or URI.
  tagsForUserList = "tags:#{authorizedEntity}"
  #all the tags that the user ever did (used for tag display on saved page)
  #(similar thing must exist forgroups)
  itemsForTagAndTypeSet="#{taggedtype}:#{tagName}"
  #items in a particular tag, by type/app
  itemsForTagAndTypeAndUserSet="#{taggedtype}:#{authorizedEntity}:#{tagName}"
  @getSavedItemsForTagAndUser authorizedEntity, tagName, searchtype, (err, replies) =>
    @getSavedItemsForTag tagName, searchtype, (err2, replies2) =>
      @getTaggedItemsForUser authorizedEntity, searchtype, (err3, replies3) =>
        deletablesearches=replies.elements
        allsearchesfortag=replies2.elements
        alltaggeditemsforuser=replies3.elements
        #Surely this intersection can be done faster and more idiomatically
        rids=[]
        grids=[]
        ugrids=[]
        searchestodelete=[]
        for jdx in [0...deletablesearches]
          if deletablesearches[jdx] in searchids
            rids.push(jdx)
            searchestodelete.push(deletablesearches[jdx])
            for kdx in [0...allsearchesfortag]
              #should happen once per group if group addition was uniqie which it will be being a set
              if deletablesearches[jdx] is allsearchesfortag[kdx]
                grids.push(kdx)
            for ldx in [0...alltaggeditemsforuser]
              #should happen once per group if group addition was uniqie which it will be being a set
              if deletablesearches[jdx] is alltaggeditemsforuser[ldx]
                ugrids.push(ldx)
        #searchestodelete = _.intersection deletablesearches, searchids
        @getTagsSavedInForItems searchtype, searchestodelete, (errb, tags) =>
          margs=[]
          for idx in [0...searchestodelete]
            tags[idx] = _.without tags[idx], tagName
            margsi = [
              ['zremrangebyrank', itemsForTagAndTypeAndUserSet, rids[idx], rids[idx]],
              ['zremrangebyrank', itemsForTagAndTypeSet,  grids[idx], grids[idx]],
              ['zremrangebyrank', taggedUserAndTypeSet,  ugrids[idx], ugrids[idx]],
              ['hset', tagsForTypeHash, searchestodelete[idx], JSON.stringify tags[idx]],
              ['hset', tagsForUserAndTypeHash, searchestodelete[idx], JSON.stringify tags[idx]],
              ['lrem', tagsForUserList, -1, tagName],
              ['lrem', tagsForTypeList, -1, tagName],
              ['lrem', tagsForUserAndTypeList, -1, tagName]
            ]
            margs = margs.concat margsi
          @addActions margs

exports.getDb = (conn, lcb, itransaction=null) ->
  return new Tagdb(conn, lcb, itransaction)