isArray = `function (o) {
    return (o instanceof Array) ||
        (Object.prototype.toString.apply(o) === '[object Array]');
};`


#TODO: custom replies and errorss, not just whats sent back by REDIS
class Savedb
  constructor: (client, lastcallback) ->
    @connection = client
    @lastcallback = lastcallback
    @transaction=[]

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

  getSavedItems: (savetype, savedBy, cb=null, lcb=null) ->
    savedtype="saved#{savetype}"
    savedset="saved#{savetype}:#{savedBy}"
    lcallb = if lcb then lcb else @lastcallback
    callb = if cb then cb else @lastcallback
    getSortedElementsAndScores false, savedset, (err, searches) ->
      #console.log err, searches, '--------------------------------------'
      if err
        return lcallb err, searches
      return callb err, searches

  getArchetypesForSavedItems: (archetypefield, sortedsearches, cb=null, lcb=null) ->
    lcallb = if lcb then lcb else @lastcallback
    callb = if cb then cb else @lastcallback
    @connection.hmget archetypefield, sortedsearches.elements..., (err, archetypes) ->
      if err
        return lcallb err, archetypes
      return callb err, archetypes

  #currently we do not delete metadata associated with the item
  removeItems: (itemkeys, itemtype, savedBy) ->
    # In Redis 2.4 zrem and hdel can be sent multiple keys
    savedtype="saved#{itemtype}"
    savedset="saved#{itemtype}:#{savedBy}"
    margs1 = (['zrem', savedset, theid] for theid in itemkeys)
    #margs2 = (['hdel', titlekey, docid] for docid in docids)
    #margs3 = (['hdel', bibkey, docid] for docid in docids)
    #actions = margs1.concat margs2, margs3
    actions=margs1
    #@clear()
    @addActions actions

exports.getSaveDb = (conn, lcb) ->
  return new Savedb(conn, lcb)