groupdb = require "./groupdb"
savedb = require "./savedb"
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

class Savegroupdb
  constructor: (client, lastcallback) ->
    @connection = client
    @lastcallback = lastcallback
    @transaction=[]
    @gdb = groupdb.getGroupDb client, lastcallback

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

  #dont check for membership here otherwise we will do it twice
  getSavedBysForItems: (fqGroupName, saveditems, cb=null, lcb=null) ->
    lcallb = if lcb then lcb else @lastcallback
    callb = if cb then cb else @lastcallback
    margs=(['hget', "savedby:#{fqGroupName}", saveditem] for saveditem in saveditems)
    @connection.multi(margs).exec (err, replies) ->
      if err2
        return lcallb err, replies
      else
        savedbys = (lstorempty ele for ele in replies)
        callb err, savedbys

  getGroupsSavedInForItems: (searchtype, saveditems, cb=null, lcb=null) ->
    lcallb = if lcb then lcb else @lastcallback
    callb = if cb then cb else @lastcallback
    margs=(['hget', "savedInGroups:#{searchtype}", saveditem] for saveditem in saveditems)
    @connection.multi(margs).exec (err, replies) ->
      if err2
        return lcallb err, replies
      else
        groups = (lstorempty ele  for ele in replies)
        callb err, groups

  saveItemsToGroup: (savedBy, fqGroupName, savedhashlist, searchtype) ->
    saveTime = new Date().getTime()
    savedtype="saved#{searchtype}"
    savedSearches=(savedhashlist[idx][savedtype] for idx in [0...savedhashlist.length])
    @gdb.is_member_of_group_p savedBy, fqGroupName, (err, is_member)=>
      if is_member
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

  #upstream this used to union with groups you were a member of to prevent leakage
  #BUG/TODO: this must now be done somewhere else. Also dosent return tags. That
  getSavedItemsForGroup: (email, fqGroupName, searchtype, cb=null, lcb=null) ->
    nowDate = new Date().getTime()
    lcallb = if lcb then lcb else @lastcallback
    callb = if cb then cb else @lastcallback
    @gdb.is_member_of_group_p savedBy, fqGroupName, (err, is_member)=>
      if is_member
        getSortedElementsAndScores false, "saved#{searchtype}:#{fqGroupName}", (err2, searches) =>
          if err
            return lcallb err, searches
          return callb err, searches

  getSavedItemsForUserAndGroup: (email, fqGroupName, searchtype, cb=null, lcb=null) ->
    nowDate = new Date().getTime()
    lcallb = if lcb then lcb else @lastcallback
    callb = if cb then cb else @lastcallback
    @gdb.is_member_of_group_p savedBy, fqGroupName, (err, is_member)=>
      if is_member
        getSortedElementsAndScores false, "saved#{searchtype}:#{email}:#{fqGroupName}", (err2, searches) =>
          if err
            return lcallb err, searches
          return callb err, searches


  removeItemsFromGroup = (email, group, searchtype, searchids, callback) ->
    #Tags are not handled BUG
    keyemail = "saved#{searchtype}:#{email}"
    keygroup = "saved#{searchtype}:#{group}"
    keyemailgroup = "saved#{searchtype}:#{email}:#{group}"
    keys4savedbyhash = "savedby:#{group}"
    savedingroupshash = "savedInGroups:#{searchtype}"
    #I can only emove stuff I have saved
    @getSavedItemsForUserAndGroup email, group, searchtype, (err, replies) =>
      @getSavedItemsForGroup email, group, searchtype, (err, replies2) =>
        deletablesearches=replies.elements
        allgroupsearches=replies2.elements
        #Surely this intersection can be done faster and more idiomatically
        rids=[]
        grids=[]
        searchestodelete=[]
        for jdx in [0...deletablesearches]
          if deletablesearches[jdx] in searchids
            rids.push(jdx)
            searchestodelete.push(deletablesearches[jdx])
            for kdx in [0...allgroupsearches]
              #should happen once per group if group addition was uniqie which it will be being a set
              if deletablesearches[jdx] is allgroupsearches[kdx]
                grids.push(kdx)
        #searchestodelete = _.intersection deletablesearches, searchids
        @getSavedBysForItems fqGroupName, searchtype, searchesodelete, (err2, savedbys) =>
          @getGroupsSavedInForItems searchtype, searchestodelete, (err2, groups) =>
            margs=[]
            for idx in [0...searchestodelete]
              groups[idx] = _.without groups[idx], group
              savedbys[idx] = _.without savedbys[idx], email
              margsi = [
                ['zremrangebyrank', keyemailgroup, rids[idx], rids[idx]],
                ['zremrangebyrank', keygroup,  grids[idx], grids[idx]],
                ['hset', keys4savedbyhash, searchestodelete[idx], JSON.stringify savedBys[idx]],
                ['hset', savedingroupshash, searchestodelete[idx], JSON.stringify groups[idx]],
              ]
              margs = margs.concat margsi
            @addActions margs


exports.getGroupDb = (conn, lcb) ->
  return new Groupdb(conn, lcb)