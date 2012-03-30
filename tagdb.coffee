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
  constructor: (client, lastcallback) ->
    @connection = client
    @lastcallback = lastcallback
    @transaction=[]
    @gdb = groupdb.getGroupDb client, lastcallback
    @sdb = savedb.getSaveDb client, lastcallback
    @sgdb = savegroupdb.getSaveGroupDb client, lastcallback

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

  saveItemsToTag: (savedBy, tagName, savedhashlist, searchtype) ->
    saveTime = new Date().getTime()
    savedtype="saved#{searchtype}"
    taggedtype="tagged#{searchtype}"
    #BELOW: Hash for now but well could be set
    tagsForTypeHash = "tagged:#{searchtype}"
    #Above: hash or set? And do we want tags for app+group?
    tagsForUserAndTypeHash = "tagged:#{savedBy}:#{searchtype}"
    #a hash keyed by the search item or URI.
    tagsForUserSet = "tags:#{savedBy}"
    #all the tags that the user ever did (used for tag display on saved page)
    #(similar thing must exist forgroups)
    itemsForTagAndTypeSet="#{taggedtype}:#{tagName}"
    #items in a particular tag, by type/app
    itemsForTagAndTypeAndUserSet="#{taggedtype}:#{tagName}:#{savedBy}"
    #items like above, but per user (similar for group)
    # ASSUMPTION: already saved by user
    #shouldnt we check this?. Also cheack this in groups. BUG BUG
    #savedByUserSet="#{savedtype}:#{savedBy}"
    savedSearches=(savedhashlist[idx][savedtype] for idx in [0...savedhashlist.length])
    margs3 = (['hset', allTagsHash, toBeTaggedSearchesToUse[i], outJSON[i]] for i in [0...toBeTaggedSearchesToUse.length])
    console.log "margs3", margs3
    margsi = (['sadd', taggedAllSet, savedSearch] for savedSearch in toBeTaggedSearchesToUse)
    margsj = (['sadd', taggedUserSet, savedSearch] for savedSearch in toBeTaggedSearchesToUse)
    margs=margs.concat [['sadd', tagsForUser, tagName]]

    margs2=(['hget', allTagsHash, thesearch] for thesearch in toBeTaggedSearchesToUse)
    @connection.multi(margs2).exec (err, reply) ->
      @getSavedBysForItems fqGroupName, searchtype, savedSearches, (err2, savedbys) =>
        @getGroupsSavedInForItems searchtype, savedSearches, (err2, groups) =>
          margs=[]
          for idx in [0...savedSearches.length]
            savedSearch=savedSearches[idx]
            savedbys[idx].push(savedBy)
            groups[idx].push(fqGroupName)
            savedbys[idx] = _.uniq savedbys[idx]
            groupss[idx] = _.uniq groupss[idx]
            margsi = [
              ['zadd', "saved#{searchtype}:#{savedBy}:#{fqGroupName}", saveTime, savedSearch],
              ['zadd', "saved#{searchtype}:#{fqGroupName}", saveTime, savedSearch],
              ['hset', "savedby:#{fqGroupName}", savedSearch, JSON.stringify savedBys[idx]],
              ['hset', "savedInGroups:#{searchtype}", savedSearch, JSON.stringify groups[idx]],
            ]
            margs = margs.concat margsi
            #No tagstuff is currently done
          @addActions margs



exports.getTagDb = (conn, lcb) ->
  return new Tagdb(conn, lcb)