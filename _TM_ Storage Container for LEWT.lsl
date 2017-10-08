/*****
Script:  :TM: Storage Container for LEWT
Creator: Tulincarchta Myhre
Version: 1.0 [2014-09-13]
*****/
string      region = "%REGION%";    // Set region to one your alliance
integer     lockDelay = 2;          // Set delay in seconds for the lock action
float       autolockDelay = 60.0;  // Set delay in seconds for max idle time

key         owner;
key         operator;
key         containerKey;           // SHA1-key identifying this chest uniquely
integer     lockState;
key         pouchKey;
string      ownerName;
string      operatorName;
string      userName;
integer     lewtChannel = %LEWTCHANNEL%;
integer     lewtHandle;
integer     diagChannel = %DIAGCHANNEL%;
integer     diagHandle;
integer     touchStart;
integer     process;
list        containerItemNames;
list        containerItems;
list        containerCount;
list        pouchItemNames;
list        pouchItems;
list        pouchCount;
key         storeReqID;
integer     storeCount;
key         getReqID;
list        nonOwnerAccess;

processLEWT(key id,string msg)
{
    list command=llParseStringKeepNulls(msg,["#"],[]);
    if(process==1) {
        if(llList2String(command,0)!="contents") return;    // pouch contents
        if(llList2Key(command,1)!=operator) return;         // belonging to owner
        if(llList2Key(command,2)!=llGetKey()) return;       // addressed at this container
        llListenRemove(lewtHandle);                         // Stop listening on LEWT channel
        if (operator==owner) llSetTimerEvent(autolockDelay);
        lewtHandle=0;
        pouchKey=id;
        pouchItemNames=llParseString2List(llToLower(llList2String(command,3)),["$"],[]);
        pouchItems=llParseString2List(llList2String(command,3),["$"],[]);
        pouchCount=llParseString2List(llList2String(command,4),["$"],[]);
        if(diagHandle) llListenRemove(diagHandle);
        diagHandle=llListen(diagChannel,"",operator,"");
        llDialog(operator
                 ,"What would you like to do, " + operatorName + "?"
                 ,["Store","Retrieve","Nothing","Contents","Lock","Inspect"]
                 ,diagChannel);
    }
}

transFromPouch(string msg)
{
    // Choose an item and a number to transfer
    if(msg=="Store") {
        llRegionSayTo(operator,0,"Please, tell me how many of which item\n"
                                +"you would like to store in the chest.");
        llListenRemove(diagHandle);
        diagHandle=llListen(0,"",operator,"");
        return;
    }
    list command=llParseString2List(msg,[" "],[""]);
    string itemName=llDumpList2String(llList2List(command,1,-1)," ");
    integer itemCount=llList2Integer(command,0);
    integer itemPos=llListFindList(pouchItemNames,[llToLower(itemName)]);
    if(itemPos==-1) {
        llRegionSayTo(operator, 0, operatorName + ", you have no " + itemName + " in your pouch.");
        process = 0;
        return;
    }
    itemName=llList2String(pouchItems,itemPos);
    if(llList2Integer(pouchCount,itemPos)<itemCount) {
        llRegionSayTo(operator, 0, operatorName 
                   + ", you do not have " 
                   + (string) itemCount + " " 
                   + itemName + "(s) in your pouch.");
        process = 0;
        return;
    }
    llWhisper(lewtChannel,"converting#"
                         +(string)operator
                         +"#"
                         +(string)itemCount + "$" + itemName
                         +"#"
                         +region);
    integer containerPos=llListFindList(containerItems,[itemName]);
    if(containerPos==-1) {
        containerItemNames+=[llToLower(itemName)];
        containerItems+=[itemName];
        containerCount+=[itemCount];
    } else {
        itemCount+=llList2Integer(containerCount,containerPos);
        containerCount=llListReplaceList(containerCount,[itemCount],containerPos,containerPos);
    }
    storeContents(containerPos);
    if(operator!=owner) {
        llRegionSayTo(operator, 0,"Your "
                             +itemName + "(s) were placed in the chest.");
    } else {
        llRegionSayTo(operator, 0,"You now have "
                             +(string) itemCount + " " 
                             +itemName + "(s) in your chest.");
    }
    process = 0;
}

transToPouch(string msg)
{
    // Choose an item and a number to transfer
    if(msg=="Retrieve") {
        llRegionSayTo(operator, 0, "Please, tell me how many of which item\n"
                                 + "you would like to retrieve from the chest.");
        llListenRemove(diagHandle);
        diagHandle=llListen(0,"",operator,"");
        return;
    }
    list command=llParseString2List(msg,[" "],[""]);
    string itemName=llDumpList2String(llList2List(command,1,-1)," ");
    integer itemCount=llList2Integer(command,0);
    integer itemPos=llListFindList(containerItemNames,[llToLower(itemName)]);
    if(itemPos==-1) {
        llRegionSayTo(operator,0,operatorName + ", you have no " + itemName + " in this chest.");
        process = 0;
        return;
    }
    itemName=llList2String(containerItems,itemPos);
    if(llList2Integer(containerCount,itemPos)<itemCount) {
       llRegionSayTo(operator, 0, operatorName 
                                + ", you do not have "
                                + (string) itemCount + " "
                                + itemName + "(s) in this chest.");
        process = 0;
        return;
    }
    llWhisper(lewtChannel,"sold#"
                         +(string)operator
                         +"#"
                         +(string)itemCount + "#" + itemName
                         +"#"
                         +region);
    integer containerPos=llListFindList(containerItems,[itemName]);
    itemCount=llList2Integer(containerCount,containerPos)-itemCount;
    containerCount=llListReplaceList(containerCount,[itemCount],containerPos,containerPos);
    storeContents(containerPos);
    if(operator==owner) {
        llRegionSayTo(operator, 0, "This chest now contains "
                             + (string) itemCount + " " 
                             + itemName + "(s).");
    }
    process = 0;
}

storeContents(integer i) {
    string url;
    url = "http://%SERVER%:%PORT%/%ENDPOINT%/balance?grid=IW"
        + "&USERKEY=" + (string) owner
        + "&USERNAME=" + llEscapeURL(userName)
        + "&DISPLAYNAME=" + llEscapeURL(ownerName)
        + "&OBJECTKEY=" + (string) containerKey 
        + "&OBJECTNAME=" + llEscapeURL(llGetObjectName())
        + "&REGIONNAME=" + llEscapeURL(region)
        + "&ITEMNAME=" + llEscapeURL(llList2String(containerItems,i))
        + "&ITEMCOUNT=" + llEscapeURL(llList2String(containerCount,i))
        + "&TRANSACTION_TS=" + llGetTimestamp();
    storeReqID=llHTTPRequest(url,[],"");
}

getContents() {
    string url;
    url = "http://%SERVER%:%PORT%/%ENDPOINT%/balance?grid=IW"
        + "&USERKEY=" + (string) owner
        + "&USERNAME=" + llEscapeURL(userName)
        + "&DISPLAYNAME=" + llEscapeURL(ownerName)
        + "&OBJECTKEY=" + (string) containerKey 
        + "&OBJECTNAME=" + llEscapeURL(llGetObjectName())
        + "&REGIONNAME=" + llEscapeURL(region)
        + "&ITEMNAME=$getContents$"
        + "&ITEMCOUNT=0"
        + "&TRANSACTION_TS=" + llGetTimestamp();
    getReqID=llHTTPRequest(url,[],"");
}

processLockState(integer num)
{
    lockState = num;
    if (!lockState)   state jammed;
    if (lockState==1) state locked;
    if (lockState==2) state open;
}

default
{
    on_rez(integer param)
    {
        llResetScript();
    }
    
    state_entry()
    {
        llSetText("",<1,1,1>,1.0);
        if(llGetObjectDesc()=="") {
            llSetObjectDesc(llSHA1String(region
                                        +(string) llGetUnixTime()
                                        +"STORAGE_CONTAINER"
                                        )
                            +"#1");
        }
        containerKey=llList2Key(llParseString2List(llGetObjectDesc(),["#"],[]),0);
        lockState=llList2Integer(llParseString2List(llGetObjectDesc(),["#"],[]),1);
        owner = llGetOwner();
        userName = llGetUsername(owner);
        ownerName = llGetDisplayName(owner);
        llSetObjectName(ownerName + "'s Storage Chest");
        llMessageLinked(LINK_THIS,lockState,"LEWTlockState",llGetKey());
    }
    
    link_message(integer sender_num,integer num, string msg, key id)
    {
        if(msg=="LEWTlockState") processLockState(num);
    }
}

state jammed
{
    on_rez(integer param)
    {
        llResetScript();
    }
    
    changed(integer change)
    {
        if(change&CHANGED_OWNER) {
            llResetScript();
        }
    }
    
    link_message(integer sender_num,integer num, string msg, key id)
    {
        if(msg=="LEWTlockState") processLockState(num);
    }
    
    state_entry()
    {
        llSetText(ownerName + "'s Chest",<1,1,1>,1.0);
        operator = "";
        operatorName = "";
        process = 0;
        if(diagHandle) llListenRemove(diagHandle);
        if(lewtHandle) llListenRemove(lewtHandle);
    }
    
    touch_start(integer num)
    {
        operator = llDetectedKey(0);
        operatorName = llGetDisplayName(operator);
    }

}

state locked
{
    on_rez(integer param)
    {
        llResetScript();
    }
    
    changed(integer change)
    {
        if(change&CHANGED_OWNER) {
            llResetScript();
        }
    }
    
    link_message(integer sender_num,integer num, string msg, key id)
    {
        if(msg=="LEWTlockState") processLockState(num);
    }
    
    state_entry()
    {
        //Store contents on server
        getContents();
        llSetText(ownerName + "'s Chest",<1,1,1>,1.0);
        operator = "";
        operatorName = "";
        process = 0;
        if(diagHandle) llListenRemove(diagHandle);
        if(lewtHandle) llListenRemove(lewtHandle);
    }
    
    http_response(key reqID, integer status, list metadata, string body)
    {
        if(reqID == storeReqID) {
            if(++storeCount<llGetListLength(containerItems)) storeContents(storeCount);
        }
        if(reqID == getReqID && pouchKey != NULL_KEY) {
            list command = llParseStringKeepNulls(body,["#"],[]);
            if(llList2Key(command,0)!=operator) return;
            if(llList2Key(command,1)!=containerKey) return;
            if(llList2String(command,4)!=region) return;
            list regItems = llParseString2List(llList2String(command,2),["$"],[]);
            integer i;
            for(i=0;i<llGetListLength(regItems);i++) {
                if (llListFindList(containerItems,llList2List(regItems,i,i))==-1) {
                    containerItems+=llList2List(regItems,i,i);
                    containerCount+=[0];
                }
            }
            storeCount=0;
            storeContents(storeCount);
        }
    }
    
    touch_start(integer num)
    {
        operator = llDetectedKey(0);
        operatorName = llGetDisplayName(operator);
    }
}

state open
{
    on_rez(integer param)
    {
        llResetScript();
    }
    
    changed(integer change)
    {
        if(change&CHANGED_OWNER) {
            //Store contents on server
            llResetScript();
        }
    }
    
    link_message(integer sender_num,integer num, string msg, key id)
    {
        if(msg=="LEWTlockState") processLockState(num);
    }

    state_entry()
    {
        //Retrieve contents on server
        llSetText(ownerName + "'s Chest",<1,1,1>,1.0);
        process = 0;
        getContents();
    }
    
    http_response(key reqID, integer status, list metadata, string body)
    {
        if(reqID == getReqID) {
            list command = llParseStringKeepNulls(body,["#"],[]);
            if(llList2Key(command,0)!=owner) return;
            if(llList2Key(command,1)!=containerKey) return;
            if(llList2String(command,4)!=region) return;
            containerItemNames = llParseString2List(llToLower(llList2String(command,2)),["$"],[]);
            containerItems = llParseString2List(llList2String(command,2),["$"],[]);
            containerCount = llParseString2List(llList2String(command,3),["$"],[]);
            llSetTimerEvent(autolockDelay);
            // The lock has been opened by a thief or the owner. Start process with operator and operatorName from locked state.
            if(lewtHandle) llListenRemove(lewtHandle);
            process=1;
            lewtHandle=llListen(lewtChannel,"","","");
            if (operator==owner) llSetTimerEvent(2.0);
            llWhisper(lewtChannel,"convertertouched#"
                                 +(string)operator
                                 +"#"
                                 +(string)llGetKey()
                                 +"#"
                                 +region);
        }
    }
    
    touch_start(integer total_num)
    {
        if (operator==owner) llSetTimerEvent(0.0);
        touchStart=llGetUnixTime();
        if (operator==owner) llSetTimerEvent(autolockDelay);
    }
    
    touch_end(integer total_num)
    {
        key currOperator = llDetectedKey(0);
        if(llGetUnixTime()-touchStart>=2) return;
        if(!process || operator==currOperator) { // Restart process
            operator = llDetectedKey(0);
            operatorName = llGetDisplayName(operator);
            if(lewtHandle) llListenRemove(lewtHandle);
            process=1;
            lewtHandle=llListen(lewtChannel,"","","");
            if (operator==owner) llSetTimerEvent(2.0);
            llWhisper(lewtChannel,"convertertouched#"
                                 +(string)operator
                                 +"#"
                                 +(string)llGetKey()
                                 +"#"
                                 +region);
        } else {
            if (currOperator==owner) {
                llRegionSayTo(operator, 0, "You were found with your hand in the chest by " + llGetDisplayName(currOperator) + ".");
                if(diagHandle) llListenRemove(diagHandle);
                diagHandle=llListen(diagChannel,"",currOperator,"");
                llDialog(operator
                         ,llGetDisplayName(llDetectedKey(0)) + " is busy in your chest.\n\n"
                         +"What would you like to do, " + llGetDisplayName(currOperator) + "?"
                         ,["Nothing","Lock"]
                         ,diagChannel);
            } else {
                llRegionSayTo(llDetectedKey(0), 0, operatorName + " is busy with this chest. Please wait until they have finished.");
            }
        }
    }
    
    listen(integer ch,string name,key id,string msg)
    {
        if(ch==lewtChannel) {
            // process LEWT message
            processLEWT(id,msg);
        }
        if(ch==diagChannel) {
            // process Dialog reply
            llListenRemove(diagHandle);
            if(msg=="Lock") {
                llWhisper(0, "The lid of " + llGetObjectName() + " drops into its lock.");
                llMessageLinked(LINK_THIS,1,"LEWTlockState",llGetKey());
            }
            if(msg=="Nothing") process = 0;
            if(process==1) {
                if(msg=="Store") {
                    process=2;
                }
                if(msg=="Retrieve") {
                    process=3;
                }
                if(msg=="Contents") {
                    process=0;
                    if(llGetListLength(containerItems)==0) {
                        llRegionSayTo(operator, 0, llGetObjectName() + " is empty.");
                    } else {
                        llRegionSayTo(operator, 0, llGetObjectName() + "'s contains:");
                        integer i;
                        for(i=0;i<llGetListLength(containerItems);i++) {
                            if(llList2Integer(containerCount,i)>0) {
                                llRegionSayTo(operator, 0
                                                      , llList2String(containerCount,i)
                                                      + " - "
                                                      + llList2String(containerItems,i));
                            }
                        }
                    }
                }
                if(msg=="Inspect") {
                    process=0;
                    llMessageLinked(LINK_THIS,0,"LEWTlockInspect",llGetKey());
                }
            }
            if(process==2) transFromPouch(msg);
            if(process==3) transToPouch(msg);
        }
        if(ch==0) {
            // process Dialog reply
            llListenRemove(diagHandle);
            if(process==2) transFromPouch(msg);
            if(process==3) transToPouch(msg);
        }
    }
    
    timer()
    {
        if(lewtHandle) {
            llSetTimerEvent(0.0);
            llListenRemove(lewtHandle);
            lewtHandle=0;
            llRegionSayTo( operator
                         , 0
                         , operatorName
                         + ", you must wear a LEWT pouch that belongs to our alliance.");
            process = 0;
            if (operator==owner) llSetTimerEvent(autolockDelay);
        } else  if (!process || operator!=owner) {
            llSetTimerEvent(0.0);
            llWhisper(0, "The lid of " + llGetObjectName() + " drops.");
            llMessageLinked(LINK_THIS,1,"LEWTlockState",llGetKey());
        } else {
            llRegionSayTo( operator
                         , 0
                         , "I didn't quite get, what you would like to do, "
                         + operatorName
                         + ". Please touch me to try again.");
            operator = "";
            operatorName = "";
            process = 0;
            if(diagHandle) llListenRemove(diagHandle);
            if(lewtHandle) llListenRemove(lewtHandle);
        }
    }
}