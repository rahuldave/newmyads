errors = './errors'
RETURNSTRINGS= errors.RETURNSTRINGS
RETURNCODES = errors.RETURNCODES
#@connection = require("redis").createClient()
isArray = `function (o) {
    return (o instanceof Array) ||
        (Object.prototype.toString.apply(o) === '[object Array]');
};`

class Groupdb


  constructor: (client, lastcallback, itransaction=null) ->
    @connection = client
    @lastcallback = lastcallback
    if itransaction is null
      @transaction=[]
    else
      @transaction=itransaction

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

  #the current user creates a group, with himself in it
  #sets up a group hash and a group set and an invitations set param=groupname
  #sets it to email/groupname

  create_group: (email, rawGroupName) ->
    changeTime = new Date().getTime()
    fqGroupName="#{email}/#{rawGroupName}"
    margs = [
        ['hmset', "group:#{fqGroupName}", 'owner', email, 'initialOwner', email, 'createdAt', changeTime, 'changedAt', changeTime],
        ['sadd', "members:#{fqGroupName}", email],
        ['sadd', "memberof:#{email}", fqGroupName],
        ['sadd', "ownerof:#{email}", fqGroupName]
    ]
    @addActions margs
        

  #you have to be added by somebody else to a group    
  #add another users comma seperated emails to the invitation set param=emails
  #TODO: no retraction of invitation as yet
  #Need to distinguish between group found or not found
  add_invitation_to_group: (email, fqGroupName, userNames, lcb=null)->
    changeTime = new Date().getTime()
    lcallb = if lcb then lcb else @lastcallback
    @is_owner_of_group_p email, fqGroupName, (err, owner_p) =>
      if owner_p
        margs1=( ['sadd', "invitations:#{fqGroupName}", user] for user in userNames)
        #bit loose and fast here as users may not exist
        margs2=(['sadd', "invitationsto:#{user}", fqGroupName] for user in userNames)
        margs=margs1.concat margs2
        @addActions margs
      else
        return lcallb "ERROR: Not owner of Group", null, RETURNCODE: RETURNCODES.UNAUTHORIZED

  remove_invitation_from_group: (email, fqGroupName, userNames, lcb=null) ->
    changeTime = new Date().getTime()
    lcallb = if lcb then lcb else @lastcallback
    @is_owner_of_group_p email, fqGroupName, (err, owner_p) =>
      if owner_p
        margs1=( ['srem', "invitations:#{fqGroupName}", user] for user in userNames)
        #bit loose and fast here as users may not exist
        margs2=(['srem', "invitationsto:#{user}", fqGroupName] for user in userNames)
        margs=margs1.concat margs2
        @addActions margs
      else
        return lcallb "ERROR: Not owner of Group", null, RETURNCODE: RETURNCODES.UNAUTHORIZED
        

  accept_invitation_to_group: (email, fqGroupName, lcb=null) ->
    changeTime = new Date().getTime()
    lcallb = if lcb then lcb else @lastcallback
    @has_invitation_to_group_p email, fqGroupName, (err, invited_p) =>
      if invited_p
        margs = [
            ['sadd', "members:#{fqGroupName}", email],
            ['srem', "invitations:#{fqGroupName}", email],
            ['sadd', "memberof:#{email}", fqGroupName],
            ['srem', "invitationsto:#{email}", fqGroupName]
        ]
        @addActions margs
      else
        return lcallb "ERROR: Not invited to this group", null, RETURNCODE: RETURNCODES.UNAUTHORIZED


  decline_invitation_to_group: (email, fqGroupName, lcb=null) ->
    changeTime = new Date().getTime()
    lcallb = if lcb then lcb else @lastcallback

    @has_invitation_to_group_p email, fqGroupName, (err, invited_p) =>
      if invited_p
        margs = [
            ['srem', "invitations:#{fqGroupName}", email],
            ['srem', "invitationsto:#{email}", fqGroupName]
        ]
        @addActions margs
      else
        return lcallb "ERROR: Not invited to this group", null, RETURNCODE: RETURNCODES.UNAUTHORIZED

  #GET
  pending_invitation_to_groups: (email, cb=null, lcb=null) -> 
    lcallb = if lcb then lcb else @lastcallback
    callb = if cb then cb else @lastcallback
    @connection.smembers "invitationsto:#{email}", (err, reply) =>
      if err
        lcallb err, reply
      return callb err, reply

  #GET                    
  member_of_groups: (email, cb=null, lcb=null) -> 
    lcallb = if lcb then lcb else @lastcallback
    callb = if cb then cb else @lastcallback
    @connection.smembers "memberof:#{email}", (err, reply) =>
      if err
        lcallb err, reply
      return callb err, reply
      
  #GET                    
  owner_of_groups: (email, cb=null, lcb=null) ->
    lcallb = if lcb then lcb else @lastcallback
    callb = if cb then cb else @lastcallback
    @connection.smembers "ownerof:#{email}", (err, reply) =>
      if err
        lcallb err, reply
      return callb err, reply   
  #only owner of group can do this   params=groupname, username
  #BUG: currently not checking if any random people are being tried to be removed
  #will silently fail

  #Also we wont remove anything the user added to group. So all hat should happen with PUB/SUB
  #where? And how? other users should still have access to that stuff.


  remove_user_from_group: (email, fqGroupName, userNames, lcb=null) ->
    lcallb = if lcb then lcb else @lastcallback
    @is_owner_of_group_p email, fqGroupName, (e, owner_p) =>
      if owner_p
        margs1=(['srem', "members:#{fqGroupName}", user] for user in userNames)
        margs2=(['srem', "memberof:#{user}", fqGroupName] for user in userNames)
        margs=margs1.concat margs2
        @addActions margs
      else
        return lcallb "ERROR: Not owner of Group", null
                  


  #current owner if logged on can set someone else as owner param=newOwner, group
  #WE DO NOT do any asking of the recipient. is this a BUG?
  change_ownership_of_group: (email, fqGroupName, newOwner, lcb=null) ->
    changeTime = new Date().getTime()
    lcallb = if lcb then lcb else @lastcallback
    @is_owner_of_group_p email, fqGroupName, (e, owner_p) =>
      if owner_p
        margs=[
            ['hset', "group:#{fqGroupName}", 'owner', newOwner],
            ['hset', "group:#{fqGroupName}", 'changedAt', changeTime],
            ['srem', "owner:#{email}", fqGroupName],
            ['sadd', "owner:#{newOwner}", fqGroupName]
        ]
        @addActions margs
      else
        return lcallb "ERROR: Not owner of Group", null

  #remove currently logged in user from group. param=group
  #this will not affext one's existing assets in group
  #Stuff you saved in group should remain (does now) TODO
  #BUG: should stop you from doing this if you are the owner
  remove_oneself_from_group: (email, fqGroupName, lcb=null) ->
    changeTime = new Date().getTime()
    lcallb = if lcb then lcb else @lastcallback
    @is_member_of_group_p email, fqGroupName, (e1, member_p) => 
      if not member_p
        return lcallb "ERROR: Not member of group", null
      @is_owner_of_group_p email, fqGroupName, (e2, owner_p) =>
        if member_p and not owner_p
          margs = [
              ['srem', "members:#{fqGroupName}", email],
              ['srem', "memberof:#{email}", fqGroupName]
          ]
          @addActions margs
        else
          return lcallb "ERROR: owner cannot remove himself/herself", null


        #fqGroupName="#{email}/#{rawGroupName}"
          
  #remove a group owned by currently logged in user param=group
  #this will remove everything from anyone associated with group
  #BUG: this is incomplete and dosent delete saved searches under the user
  #specifically dosent hadle saved:user:group and savedInGroup:searchtype  yet.

  #Also, BUG: this code has now combined concerns. It should emit a deleting group
  #And saved.coffee should add events to the eventhandler loop that do the needful there.

  #BUG invitations to non-existent group not deleted yet What else?

  #BUG How about deleting in savedInGroups: delete members, invitations from the users
  #or should a group archive
  delete_group: (email, fqGroupName, lcb=null)->
    lcallb = if lcb then lcb else @lastcallback
    @is_owner_of_group_p email, fqGroupName, (e, owner_p) =>
      if owner_p
          #how about individual deletions; pubsub? or just mothball with a flag?
          margs = [
              ['del', "savedsearch:#{fqGroupName}"],
              ['del', "savedpub:#{fqGroupName}"],
              ['del', "savedobsv:#{fqGroupName}"],
              ['del', "members:#{fqGroupName}"],
              ['del', "invitations:#{fqGroupName}"],
              ['del', "savedby:#{fqGroupName}"],
              ['del', "group:#{fqGroupName}"],
              ['srem', "memberof:#{email}", fqGroupName],
              ['srem', "ownerof:#{email}", fqGroupName]
          ]
          @addActions margs
      else
          return lcallb "ERROR: Not owner of Group", null



  #GET
  #any member of group can get members of group
  get_members_of_group: (email, wantedGroup, cb=null, lcb=null) ->
    lcallb = if lcb then lcb else @lastcallback
    callb = if cb then cb else @lastcallback
    @is_member_of_group_p email, wantedGroup, (e, member_p) =>
      if member_p
        console.log '000;;;;;;;;;;;;;;;;;;;;;'
        @connection.smembers "members:#{wantedGroup}", (err, reply) =>
          if err
            lcallb err, reply
          return callb err, reply
      else
        return lcallb "ERROR: Not member of Group", null

  #GET
  #only owner can get invitations to group
  get_invitations_to_group: (email, wantedGroup, cb=null, lcb=null) ->
    lcallb = if lcb then lcb else @lastcallback
    callb = if cb then cb else @lastcallback
    @is_owner_of_group_p email, wantedGroup, (e, owner_p) =>
      if owner_p    
        @connection.smembers "invitations:#{wantedGroup}", (err, reply) =>
          if err
            lcallb err, reply
          return callb err, reply
      else
        return lcallb "ERROR: Not owner of Group", null


  #GET
  is_member_of_group_p: (email, wantedGroup, cb=null, lcb=null) ->
    lcallb = if lcb then lcb else @lastcallback
    callb = if cb then cb else @lastcallback
    @connection.sismember "members:#{wantedGroup}", email, (err, reply) =>
      if err
        return lcallb err, reply
      if reply#is
        callb null, true
      else
        callb null, false
  #GET
  has_invitation_to_group_p: (email, wantedGroup, cb=null, lcb=null) ->
    lcallb = if lcb then lcb else @lastcallback
    callb = if cb then cb else @lastcallback
    @connection.sismember "invitations:#{wantedGroup}", email, (err, reply) =>
      if err
        return lcallb err, reply
      if reply#is
        callb null, true
      else
        callb null, false
  #GET
  is_owner_of_group_p: (email, wantedGroup, cb=null, lcb=null) ->
    lcallb = if lcb then lcb else @lastcallback
    callb = if cb then cb else @lastcallback
    @connection.hget "group:#{wantedGroup}", 'owner', (err, reply) => 
      if err
        return lcallb err, reply
      if reply is email
        callb null, true
      else
        callb null, false  

  #GET
  get_group_info: (email, wantedGroup, cb=null, lcb=null) ->
    lcallb = if lcb then lcb else @lastcallback
    callb = if cb then cb else @lastcallback
    @is_member_of_group_p email, wantedGroup, (e1, member_p) =>
      if member_p  
        @connection.hgetall "group:#{wantedGroup}", (err, reply) =>
          if err
            return lcallb err, reply
          else
            return callb reply
      else
        @has_invitation_to_group_p email, wantedGroup, (e2, invited_p) =>
          if invited_p    
            @connection.hgetall "group:#{wantedGroup}", callb
          else
            return lcallb "ERROR: not member or invitee to group", null
        


exports.getDb = (conn, lcb, itransaction=null) ->
  return new Groupdb(conn, lcb, itransaction)
#exports.consolecallbackmaker=consolecallbackmaker