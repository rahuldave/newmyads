requests = require("./requests-myads")
failedRequest = requests.failedRequest
successfulRequest = requests.successfulRequest
ifLoggedIn = requests.ifLoggedIn

httpcallbackmaker = requests.httpcallbackmaker
#consolecallbackmaker=requests.consolecallbackmaker
connectutils = require('connect').utils
url = require 'url'

groupdb = require("./groupdb")
utils = require("./utils")
CONNECTION = utils.getRedisClient()
ifHavePermissions = utils.ifHavePermissions
ifHaveAuth = utils.ifHaveAuth
ifHavePermissions = utils.ifHavePermissions
getSortedElements = utils.getSortedElements
getSortedElementsAndScores = utils.getSortedElementsAndScores
timeToText = utils.timeToText
searchToText = utils.searchToText

        

createGroup = ({rawGroupName}, req, res, next) ->
  console.log __fname="createGroup:"
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (email) ->
    gdb=groupdb.getDb(CONNECTION, lastcb)
    gdb.create_group email, rawGroupName
    gdb.execute()
                     
#you have to be added by somebody else to a group    
#add another users comma seperated emails to the invitation set param=emails
#TODO: no retraction of invitation as yet

            
addInvitationToGroup = ({fqGroupName, userNames}, req, res, next) ->
  console.log __fname="addInvitationToGroup"
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (email) ->
      gdb=groupdb.getDb(CONNECTION, lastcb)
      gdb.add_invitation_to_group email, fqGroupName, userNames
      gdb.execute()

        
removeInvitationFromGroup = ({fqGroupName, userNames}, req, res, next) ->
  console.log __fname="removeUserFromGroup"
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (email) ->
      gdb=groupdb.getDb(CONNECTION, lastcb)
      gdb.remove_invitation_from_group email, fqGroupName, userNames
      gdb.execute()
        

#move the currently logged in user from invitations set to groups set. param=group    
acceptInvitationToGroup = ({fqGroupName}, req, res, next) -> 
  console.log __fname="acceptInvitationToGroup"
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (email) -> 
    gdb=groupdb.getDb(CONNECTION, lastcb)
    gdb.accept_invitation_to_group email, fqGroupName
    gdb.execute()


#move the currently logged in user from invitations set to groups set. param=group    
declineInvitationToGroup = ({fqGroupName}, req, res, next) -> 
    console.log __fname="declineInvitationToGroup"
    lastcb = httpcallbackmaker(__fname, req, res, next)
    ifHavePermissions req, res, lastcb, (email) -> 
        gdb=groupdb.getDb(CONNECTION, lastcb)
        gdb.decline_invitation_to_group email, fqGroupName
        gdb.execute()
#GET
pendingInvitationToGroups = (req, res, next) -> 
  console.log __fname="pendingInvitationToGroups"
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (email) ->
    gdb=groupdb.getDb(CONNECTION, lastcb)  
    gdb.pending_invitation_to_groups email

#GET                    
memberOfGroups = (req, res, next) -> 
  console.log __fname="memberOfGroups"
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (email) ->
    gdb=groupdb.getDb(CONNECTION, lastcb)
    gdb.member_of_groups email
    
#GET                    
ownerOfGroups = (req, res, next) -> 
  console.log __fname="ownerOfGroups"
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (email) ->
    gdb=groupdb.getDb(CONNECTION, lastcb)
    gdb.owner_of_groups email    
#only owner of group can do this   params=groupname, username
#BUG: currently not checking if any random people are being tried to be removed
#will silently fail

#Also we wont remove anything the user added to group

                
removeUserFromGroup = ({fqGroupName, userNames}, req, res, next) ->
  console.log __fname="removeUserFromGroup"
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (email) ->
    gdb=groupdb.getDb(CONNECTION, lastcb)
    gdb.remove_user_from_group email, fqGroupName, userNames
    gdb.execute()



#current owner if logged on can set someone else as owner param=newOwner, group

changeOwnershipOfGroup = ({fqGroupName, newOwner}, req, res, next) ->
  console.log __fname="changeOwnershipOfGroup"
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (email) ->
    gdb=groupdb.getDb(CONNECTION, lastcb)
    gdb.change_ownership_of_group email, fqGroupName, newOwner
    gdb.execute()
        
#remove currently logged in user from group. param=group
#this will not affext one's existing assets in group
#Stuff you saved in group should remain (does now) TODO

#BUG: should stop you from doing this if you are the owner


removeOneselfFromGroup = ({fqGroupName}, req, res, next) ->
    console.log __fname="removeOneselfFromGroup"
    lastcb = httpcallbackmaker(__fname, req, res, next)
    ifHavePermissions req, res, lastcb, (email) ->
        gdb=groupdb.getDb(CONNECTION, lastcb)
        gdb.remove_oneself_from_group email, fqGroupName
        gdb.execute()
              

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

#  ['del', "savedby:#{fqGroupName}"],  
deleteGroup = ({fqGroupName}, req, res, next) ->
  console.log __fname="deleteGroup:"
  lastcb = httpcallbackmaker(__fname, req, res, next)
  ifHavePermissions req, res, lastcb, (email) ->
    gdb=groupdb.getDb(CONNECTION, lastcb)
    gdb.delete_group email, fqGroupName
    gdb.execute()


#GET
getMembersOfGroup = (req, res, next) ->
    console.log __fname="getMembersOfGroup"
    changeTime = new Date().getTime()
    wantedGroup=req.query.fqGroupName
    console.log "wantedGroup", wantedGroup
    lastcb = httpcallbackmaker(__fname, req, res, next)
    ifHavePermissions req, res, lastcb, (email) ->
      gdb=groupdb.getDb(CONNECTION, lastcb)
      gdb.get_members_of_group(email, wantedGroup)

#GET currently let anyone get BUG later impose owner
getInvitationsToGroup = (req, res, next) ->
    console.log __fname="getInvitationsToGroup"
    changeTime = new Date().getTime()
    wantedGroup=req.query.fqGroupName
    console.log "wantedGroup", wantedGroup
    lastcb =  httpcallbackmaker(__fname, req, res, next)
    ifHavePermissions req, res, lastcb, (email) ->
      gdb=groupdb.getDb(CONNECTION, lastcb)
      gdb.get_invitations_to_group email, wantedGroup
                 
#GET
getGroupInfo = (req, res, next) ->
    console.log __fname="getGroupInfo"
    changeTime = new Date().getTime()
    wantedGroup=req.query.fqGroupName
    console.log "wantedGroup", wantedGroup
    lastcb =  httpcallbackmaker(__fname, req, res, next)
    ifHavePermissions req, res, lastcb, (email) ->
      gdb=groupdb.getDb(CONNECTION, lastcb)
      gdb.get_group_info email, wantedGroup
        
exports.createGroup=createGroup
exports.addInvitationToGroup=addInvitationToGroup
exports.removeInvitationFromGroup=removeInvitationFromGroup
exports.acceptInvitationToGroup=acceptInvitationToGroup
exports.declineInvitationToGroup=declineInvitationToGroup
exports.removeUserFromGroup=removeUserFromGroup
exports.changeOwnershipOfGroup=changeOwnershipOfGroup
exports.removeOneselfFromGroup=removeOneselfFromGroup
exports.deleteGroup=deleteGroup

#and the gets   
exports.getMembersOfGroup=getMembersOfGroup
exports.getInvitationsToGroup=getInvitationsToGroup
exports.getGroupInfo=getGroupInfo
exports.memberOfGroups=memberOfGroups
exports.ownerOfGroups=ownerOfGroups
exports.pendingInvitationToGroups=pendingInvitationToGroups

#exports.consolecallbackmaker=consolecallbackmaker
