isArray = `function (o) {
    return (o instanceof Array) ||
        (Object.prototype.toString.apply(o) === '[object Array]');
};`


class Userdb
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

  getUser = (credential, cb=null, ecb=null) ->
    lcallb = if lcb then lcb else @lastcallback
    callb = if cb then cb else @lastcallback
    @connection.get "email:#{credential}", (err, reply) ->
      if (err)
        lcallb err, reply
      else
        callb err, reply

  insertUser = (payload, credential) ->
    lcallb = if lcb then lcb else @lastcallback
    callb = if cb then cb else @lastcallback
    cookie = credential.cookie
    #BUG defensive coding neaded below with SOAKS or automatic error throwing elsewhere.
    email=payload.email
    mkeys = [['hset', email, 'dajson', JSON.stringify payload]
             ['hset', email, 'cookieval', cookie]
            ]
    margs = (['hset', email, key, value] for key, value of payload)
    margs = margs.concat mkeys

    # Store the user details (the unique value and email) in sets to make it
    # easier to identify them later. This may not be needed. Also, should the
    # unique value have a time-to-live associated with it (and can this be done
    # within a set)?
    #
    # Since thenext set will be the last one the others will have completed.Not that it matters as we dont error handle right now.
    # redis_client.setex('auth:' + logincookie['unique'], logincookie['expdateinsecs'], logincookie['cookie']);
    # on the fly we will have savedsearches:email and savedpubs:email
    #
    #  redis_client.setex('email:' + logincookie['unique'], logincookie['expdateinsecs'], email, responsedo);
    #
    margs2 = [
      ['sadd', 'useremails', email],
      ['sadd', 'userids', credential.unique],
      ['setex', "email:#{credential.unique}", credential.expdateinsecs, email]
    ]
    margs = margs.concat margs2
    @addActions margs

  deleteUser = (payload, credenial) ->
    #no delete user yet. All kinds of pain about the users assets, just as in groups. BUG.
    null

exports.getUserDb = (conn, lcb) ->
  return new Userdb(conn, lcb)