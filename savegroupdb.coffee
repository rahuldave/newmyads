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
  constructor: (client, lastcallback, itransaction=null) ->
    @connection = client
    @lastcallback = lastcallback
    if itransaction is null
      @transaction=[]
    else
      @transaction=itransaction
    #botton two only used as gets, so no need to share transactions
    @gdb = groupdb.getDb client, lastcallback
    @sdb = savedb.getDb client, lastcallback

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
  #since its only people in this group, this is not a sb query
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
    @connection.multi(margs).exec (err, replies) =>
      if err2
        return lcallb err, replies
      else
        groups = (lstorempty ele  for ele in replies)
        callb err, groups

  getGroupsSavedInForItemsAndUser: (authorizedEntity, searchtype, saveditems, cb=null, lcb=null) ->
    lcallb = if lcb then lcb else @lastcallback
    callb = if cb then cb else @lastcallback
    @gdb.member_of_groups authorizedEntity, (err, groups) =>
      @getGroupsSavedInForItems searchtype, saveditems, (err2, groupssavedin) ->
        groupssavedinvisibletouser = _.map groupssavedin, (grlist) ->
          return _.intersection grlist, groups
        callb err2, groupssavedinvisibletouser
    
  #BUG: how are we making sure an item has really already been saved?
  saveItemsToGroup: (authorizedEntity, fqGroupName, savedhashlist, searchtype) ->
    saveTime = new Date().getTime()
    savedtype="saved#{searchtype}"
    savedSearches=(savedhashlist[idx][savedtype] for idx in [0...savedhashlist.length])
    @gdb.is_member_of_group_p authorizedEntity, fqGroupName, (err, is_member) =>
      if is_member
        @getSavedBysForItems fqGroupName, searchtype, savedSearches, (err2, savedbys) =>
          @getGroupsSavedInForItems searchtype, savedSearches, (err2, groups) =>
            margs=[]
            for idx in [0...savedSearches.length]
              savedSearch=savedSearches[idx]
              savedbys[idx].push(authorizedEntity)
              groups[idx].push(fqGroupName)
              savedbys[idx] = _.uniq savedbys[idx]
              groupss[idx] = _.uniq groupss[idx]
              margsi = [
                ['zadd', "saved#{searchtype}:#{authorizedEntity}:#{fqGroupName}", saveTime, savedSearch],
                ['zadd', "saved#{searchtype}:#{fqGroupName}", saveTime, savedSearch],
                ['zadd', "grouped#{searchtype}:#{authorizedEntity}", saveTime, savedSearch],
                ['hset', "savedby:#{fqGroupName}", savedSearch, JSON.stringify savedbys[idx]],
                ['hset', "savedInGroups:#{searchtype}", savedSearch, JSON.stringify groups[idx]],
              ]
              margs = margs.concat margsi
              #No tagstuff is currently done
            @addActions margs

  #upstream this used to union with groups you were a member of to prevent leakage
  #BUG/TODO: this must now be done somewhere else. Also dosent return tags. That
  getSavedItemsForGroup: (authorizedEntity, fqGroupName, searchtype, cb=null, lcb=null) ->
    nowDate = new Date().getTime()
    lcallb = if lcb then lcb else @lastcallback
    callb = if cb then cb else @lastcallback
    @gdb.is_member_of_group_p authorizedEntity, fqGroupName, (err, is_member)=>
      if is_member
        getSortedElementsAndScores false, "saved#{searchtype}:#{fqGroupName}", (err2, searches) =>
          if err
            return lcallb err, searches
          return callb err, searches

  getSavedItemsForUserAndGroup: (authorizedEntity, fqGroupName, searchtype, cb=null, lcb=null) ->
    nowDate = new Date().getTime()
    lcallb = if lcb then lcb else @lastcallback
    callb = if cb then cb else @lastcallback
    @gdb.is_member_of_group_p authorizedEntity, fqGroupName, (err, is_member)=>
      if is_member
        getSortedElementsAndScores false, "saved#{searchtype}:#{authorizedEntity}:#{fqGroupName}", (err2, searches) =>
          if err
            return lcallb err, searches
          return callb err, searches

  getGroupedItemsForUser: (authorizedEntity,  searchtype, cb=null, lcb=null) ->
    nowDate = new Date().getTime()
    lcallb = if lcb then lcb else @lastcallback
    callb = if cb then cb else @lastcallback
    getSortedElementsAndScores false, "grouped#{searchtype}:#{authorizedEntity}", (err2, searches) =>
      if err
        return lcallb err, searches
      return callb err, searches


  removeItemsFromGroup = (authorizedEntity, group, searchtype, searchids) ->
    #Tags are not handled BUG
    keyauthorizedEntity = "saved#{searchtype}:#{authorizedEntity}"
    grpauthorizedEntity = "grouped#{searchtype}:#{authorizedEntity}"
    keygroup = "saved#{searchtype}:#{group}"
    keyauthorizedEntitygroup = "saved#{searchtype}:#{authorizedEntity}:#{group}"
    keys4savedbyhash = "savedby:#{group}"
    savedingroupshash = "savedInGroups:#{searchtype}"
    #I can only emove stuff I have saved
    @getSavedItemsForUserAndGroup authorizedEntity, group, searchtype, (err, replies) =>
      @getSavedItemsForGroup authorizedEntity, group, searchtype, (err2, replies2) =>
        @getGroupedItemsForUser authorizedEntity, searchtype, (err2, replies3) =>
          deletablesearches=replies.elements
          allgroupsearches=replies2.elements
          allsavedbyuseringroups=replies3.elements
          #Surely this intersection can be done faster and more idiomatically
          rids=[]
          grids=[]
          ugrids=[]
          searchestodelete=[]
          for jdx in [0...deletablesearches]
            if deletablesearches[jdx] in searchids
              rids.push(jdx)
              searchestodelete.push(deletablesearches[jdx])
              for kdx in [0...allgroupsearches]
                #should happen once per group if group addition was uniqie which it will be being a set
                if deletablesearches[jdx] is allgroupsearches[kdx]
                  grids.push(kdx)
              for ldx in [0...allsavedbyuseringroups]
                if deletablesearches[jdx] is allsavedbyuseringroups[ldx]
                  ugrids.push(ldx)
        #searchestodelete = _.intersection deletablesearches, searchids
        @getSavedBysForItems fqGroupName, searchtype, searchesodelete, (errb, savedbys) =>
          @getGroupsSavedInForItems searchtype, searchestodelete, (errc, groups) =>
            margs=[]
            for idx in [0...searchestodelete]
              groups[idx] = _.without groups[idx], group
              savedbys[idx] = _.without savedbys[idx], authorizedEntity
              margsi = [
                ['zremrangebyrank', keyauthorizedEntitygroup, rids[idx], rids[idx]],
                ['zremrangebyrank', keygroup,  grids[idx], grids[idx]],
                ['zremrangebyrank', grpauthorizedEntity,  ugrids[idx], ugrids[idx]],
                ['hset', keys4savedbyhash, searchestodelete[idx], JSON.stringify savedbys[idx]],
                ['hset', savedingroupshash, searchestodelete[idx], JSON.stringify groups[idx]],
              ]
              margs = margs.concat margsi
            @addActions margs


exports.getDb = (conn, lcb, itransaction=null) ->
  return new Savegroupdb(conn, lcb, itransaction)