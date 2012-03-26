
CONNECTION = require("redis").createClient()
isArray = `function (o) {
    return (o instanceof Array) ||
        (Object.prototype.toString.apply(o) === '[object Array]');
};`

class Groupdb
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

    #the current user creates a group, with himself in it
    #sets up a group hash and a group set and an invitations set param=groupname
    #sets it to email/groupname

  create_group = (email, rawGroupName) ->
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

  add_invitation_to_group = (email, fqGroupName, userNames, lcb=null)->
    changeTime = new Date().getTime()
    lcallb = if lcb then lcb else @lastcallback
    @connection.hget "group:#{fqGroupName}", 'owner', (err, reply) -> 
        if err
            return lcallb err, reply
        if reply is email
            @clear()
            margs1=( ['sadd', "invitations:#{fqGroupName}", user] for user in userNames)
            #bit loose and fast here as users may not exist
            margs2=(['sadd', "invitationsto:#{user}", fqGroupName] for user in userNames)
            margs=margs1.concat margs2
            @addActions margs
        else
            return lcallb err, reply

  remove_invitation_from_group = (email, fqGroupName, userNames, lcb=null) ->
    changeTime = new Date().getTime()
    lcallb = if lcb then lcb else @lastcallback
    @connection.hget "group:#{fqGroupName}", 'owner', (err, reply) -> 
        if err
            return lcallb err, reply
        if reply is email
            margs1=( ['srem', "invitations:#{fqGroupName}", user] for user in userNames)
            #bit loose and fast here as users may not exist
            margs2=(['srem', "invitationsto:#{user}", fqGroupName] for user in userNames)
            margs=margs1.concat margs2
            @addActions margs
        else
            return lcallb err, reply
        

  accept_invitation_to_group = (email, fqGroupName, lcb=null) ->
    changeTime = new Date().getTime()
    lcallb = if lcb then lcb else @lastcallback
    @connection.sismember "invitations:#{fqGroupName}", email, (err, reply)->
        if err
            return lcallb err, reply
        if reply
            margs = [
                ['sadd', "members:#{fqGroupName}", email],
                ['srem', "invitations:#{fqGroupName}", email],
                ['sadd', "memberof:#{email}", fqGroupName],
                ['srem', "invitationsto:#{email}", fqGroupName]
            ]
            @addActions margs
        else
            return lcallb err, reply


  decline_invitation_to_group = (email, fqGroupName, lcb=null) ->
    changeTime = new Date().getTime()
    lcallb = if lcb then lcb else @lastcallback

    @connection.sismember "invitations:#{fqGroupName}", email, (err, reply)->
        if err
            return lcallb err, reply
        if reply
            margs = [
                ['srem', "invitations:#{fqGroupName}", email],
                ['srem', "invitationsto:#{email}", fqGroupName]
            ]
            @addActions margs
        else
            return lcallb err, reply

  #GET
  pending_invitation_to_groups = (email, cb=null, lcb=null) -> 
    lcallb = if lcb then lcb else @lastcallback
    callb = if cb then cb else @lastcallback
    @connection.smembers "invitationsto:#{email}", callb

  #GET                    
  member_of_groups = (email, cb=null, lcb=null) -> 
    lcallb = if lcb then lcb else @lastcallback
    callb = if cb then cb else @lastcallback
    @connection.smembers "memberof:#{email}", callb
      
  #GET                    
  owner_of_groups = (email, cb=null, lcb=null) ->
    lcallb = if lcb then lcb else @lastcallback
    callb = if cb then cb else @lastcallback
    @connection.smembers "ownerof:#{email}", callb   
  #only owner of group can do this   params=groupname, username
  #BUG: currently not checking if any random people are being tried to be removed
  #will silently fail

  #Also we wont remove anything the user added to group

  remove_user_from_group = (email, fqGroupName, userNames, lcb=null) ->
    lcallb = if lcb then lcb else @lastcallback
    @connection.hget "group:#{fqGroupName}", 'owner', (err, reply) -> 
        if err
            return lcallb err, reply
        if reply is email
            margs1=(['srem', "members:#{fqGroupName}", user] for user in userNames)
            margs2=(['srem', "memberof:#{user}", fqGroupName] for user in userNames)
            margs=margs1.concat margs2
            @addActions margs
        else
            return lcallb err, reply
                  


  #current owner if logged on can set someone else as owner param=newOwner, group
  change_ownership_of_group = (email, fqGroupName, newOwner, lcb=null) ->
    changeTime = new Date().getTime()
    lcallb = if lcb then lcb else @lastcallback
    @connection.hget "group:#{fqGroupName}", 'owner', (err, reply) -> 
        if err
            return lcallb err, reply
        if reply is email
            margs=[
                ['hset', "group:#{fqGroupName}", 'owner', newOwner],
                ['hset', "group:#{fqGroupName}", 'changedAt', changeTime],
                ['srem', "owner:#{email}", fqGroupName],
                ['sadd', "owner:#{newOwner}", fqGroupName]
            ]
            @addActions margs
        else
            return lcallb err, reply
      

  #remove currently logged in user from group. param=group
  #this will not affext one's existing assets in group
  #Stuff you saved in group should remain (does now) TODO

  #BUG: should stop you from doing this if you are the owner
  remove_oneself_from_group = (email, fqGroupName, lcb=null) ->
    changeTime = new Date().getTime()
    lcallb = if lcb then lcb else @lastcallback
    @connection.sismember "members:#{fqGroupName}", email, (err, reply)->
        if err
            return lcallb err, reply
        if reply
            CONNECTION.hget "group:#{fqGroupName}", 'owner', (err2, reply2) -> 
                if err2
                    return lcallb err2, reply2
                if reply2 isnt email
                    margs = [
                        ['srem', "members:#{fqGroupName}", email],
                        ['srem', "memberof:#{email}", fqGroupName]
                    ]
                    @addActions margs
                else
                    console.log "here", email, err2, reply2
                    return lcallb err2, reply2
        else
            return lcallb err, reply


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
  delete_group=(email, fqGroupName, lcb=null)->
    lcallb = if lcb then lcb else @lastcallback
    @connection.hget "group:#{fqGroupName}", 'owner', (err, reply) -> 
      if err
          return lcallb err, reply
      if reply is email
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
          return lcallb err, reply



  #GET
  get_members_of_group = (email, wantedGroup, cb=null, lcb=null) ->
    lcallb = if lcb then lcb else @lastcallback
    callb = if cb then cb else @lastcallback
    CONNECTION.sismember "members:#{wantedGroup}", email, (err, reply) ->
      if err
          return lcallb err, reply
      if reply    
          CONNECTION.smembers "members:#{wantedGroup}", callb
      else
          return lcallb err, reply 

  #GET currently let anyone get BUG later impose owner
  get_invitations_to_group = (email, wantedGroup, cb=null, lcb=null) ->
    lcallb = if lcb then lcb else @lastcallback
    callb = if cb then cb else @lastcallback
    CONNECTION.hget "group:#{wantedGroup}", 'owner', (err, reply) ->
      if err
          return lcallb err, reply
      if reply is email    
          CONNECTION.smembers "invitations:#{wantedGroup}", callb
      else
          return lcallb err, reply                
  #GET
  get_group_info = (email, wantedGroup, cb=null, lcb=null) ->
    lcallb = if lcb then lcb else @lastcallback
    callb = if cb then cb else @lastcallback
    CONNECTION.sismember "members:#{wantedGroup}", email, (err, reply) ->
      if err
          return lcallb err, reply
      if reply    
          CONNECTION.hgetall "group:#{wantedGroup}", callb
      else
          CONNECTION.sismember "invitations:#{wantedGroup}", email, (err2, reply2) ->
              if err2
                  return lcallb err2, reply2
              if reply2    
                  CONNECTION.hgetall "group:#{wantedGroup}", callb
              else
                  return lcallb err2, reply2
        


elt={}

elt.create_group=create_group
elt.delete_group=delete_group
elt.add_invitation_to_group=add_invitation_to_group
elt.remove_invitation_from_group=remove_invitation_from_group
#exports.consolecallbackmaker=consolecallbackmaker
