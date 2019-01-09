/*****
Script:  :TM: LEWT lock
Creator: Tulincarchta Myhre
Version: 1.0 [2014-10-06]
*****/
string      alliance = "%REGION%";  // Set your LEWT alliance
integer     lockDelay = 2;          // Set delay in seconds for the lock action

integer     updateChannel = %UPDATECHANNEL%;
integer     lockVersion = 14100601;
integer     pin = %UPDATEPINL%;

key         owner;
key         operator;
string      operatorName;
integer     lockState;      // 0 - jammed, 1 - locked, 2 - open
integer     informNonOwner; // 0 - inform owner of object, 1 - inform first AV on the approvedAV list

list        whiteList;
list        nonOwnerAccess;
integer     touchStart;

key         gQueryID;
integer     gLine;
string      gName = "Lock Settings";
integer     settingsFound;
integer     lockStatePos;
string      lockRepairParts = "Lock Repair Parts";

integer     lewtChannel = %LEWTCHANNEL%;
integer     lewtHandle;
integer     diagChannel = %DIAGCHANNEL%;
integer     diagHandle;

key         pouchKey;
list        pouchItemNames;
list        pouchItems;
list        pouchCount;

list        LEWTlockPickIn     =   ["Feeler Pick","Worn Feeler Pick","Damaged Feeler Pick"
                                   ,"Lock Pick","Worn Lock Pick","Damaged Lock Pick"
                                   ,"Elliptical Pick","Worn Elliptical Pick","Damaged Elliptical Pick"
                                   ,"Jiggler Pick","Worn Jiggler Pick","Damaged Jiggler Pick"];
list        LEWTlockPickOut    =   ["Worn Feeler Pick","Damaged Feeler Pick","Broken Feeler Pick"
                                   ,"Worn Lock Pick","Damaged Lock Pick","Broken Lock Pick"
                                   ,"Worn Elliptical Pick","Damaged Elliptical Pick","Broken Elliptical Pick"
                                   ,"Worn Jiggler Pick","Damaged Jiggler Pick","Broken Jiggler Pick"];
list        LEWTlockPickLevel  =   [1,1,1
                                   ,2,2,2
                                   ,3,3,3
                                   ,4,4,4];

processNotecardLine(string line)
{
    list setting = llParseString2List(line,["="],[]);
    if(llGetListLength(setting)==2) {
        if(llList2String(setting,0) == "approvedAV") whiteList += [llList2String(setting,1)];
        if(llList2String(setting,0) == "LockStateLocation") lockStatePos = llList2Integer(setting,1);
        if(llList2String(setting,0) == "informNonOwner") informNonOwner = llList2Integer(setting,1);
    }
    gLine++;
    gQueryID = llGetNotecardLine(gName,gLine);
}

registerNonOwnerAccess()
{
    if(llListFindList(whiteList,[operator])==-1) {
        integer i = llListFindList(nonOwnerAccess,[operatorName]);
        if(i) {
            nonOwnerAccess = [operatorName]
                           + llDeleteSubList(nonOwnerAccess,i,i);
        } else {
            nonOwnerAccess = [operatorName]
                           + llList2List(nonOwnerAccess,1,11);
        }
    }
}

processLEWT(key id,string msg)
{
    list command=llParseStringKeepNulls(msg,["#"],[]);
    if(llList2String(command,0)!="contents") return;    // pouch contents
    if(llList2Key(command,1)!=operator) return;         // belonging to operator
    if(llList2Key(command,2)!=llGetKey()) return;       // addressed at this container
    llListenRemove(lewtHandle);                         // Stop listening on LEWT channel
    lewtHandle=0;
    pouchKey=id;
    pouchItemNames=llParseString2List(llToLower(llList2String(command,3)),["$"],[]);
    pouchItems=llParseString2List(llList2String(command,3),["$"],[]);
    pouchCount=llParseString2List(llList2String(command,4),["$"],[]);
    if(lockState) {
        if (diagHandle) llListenRemove(diagHandle);
        diagHandle = llListen(diagChannel,"",operator,"");
        llDialog(operator
                ,"Do you want to pick this lock, " + operatorName + "?"
                ,["Pick Lock","Never Mind"]
                ,diagChannel);
    }
}

processPickLock() {
    // Finding a suitable lock pick
    string itemName;
    integer LockPickPos = -1;
    integer i;
    for (i=0;i<llGetListLength(pouchItems);i++)
    {
        //return the most worn, highest level available lock pick from your pouch
        integer foundPos = llListFindList(LEWTlockPickIn,llList2List(pouchItems,i,i));
        if ( foundPos > -1 ) LockPickPos = foundPos;
    }
    if (LockPickPos<0) {
        llRegionSayTo(operator, 0, "You cannot expect to break open the lock with your bare hands. You'll need some tool to pick the lock.");
        return;
    }
    integer pickDiceRoll = 1 + (integer) llFrand(100);
    integer pickFailRoll = 1 + (integer) llFrand(100);
    llWhisper(lewtChannel,"converting#"
                         +(string)operator
                         +"#"
                         +"1$" + llList2String(LEWTlockPickIn,LockPickPos)
                         +"#"
                         +alliance);
    if (pickDiceRoll > 90) {
        llShout(0, operatorName
               +" is trying to break open the lock on "
               + llGetObjectName()
               + ". It sounds like constables are on their way.");
    }
    if (pickDiceRoll > 80) {
        key recipientKey = owner;
        if(informNonOwner) recipientKey = llList2Key(whiteList,1); // First approvedAV
        llInstantMessage(recipientKey
                        ,operatorName
                        +" is trying to break open the lock on your "
                        + llGetObjectName()
                        +".");
    }
    integer levelBonus = 10*llList2Integer(LEWTlockPickLevel,LockPickPos);
    if (pickFailRoll > 50 + levelBonus) {
        llRegionSayTo(operator, 0, "Your " 
                                 + llList2String(LEWTlockPickIn,LockPickPos)
                                 + " gave way under the strain and broke into pieces.");
        if (pickFailRoll > 80) {
            llRegionSayTo(operator, 0, "Most unfortunately your " 
                                     + llList2String(LEWTlockPickIn,LockPickPos)
                                     + " broke off inside the lock and is now jamming the locking mechanism.");
            llMessageLinked(LINK_THIS,0,"LEWTlockState",llGetKey());
        }
        return;
    }
    if (llGetSubString(llList2String(LEWTlockPickOut,LockPickPos),0,5)=="Broken") {
        llRegionSayTo(operator, 0, "You retrieve your "
                                 + llList2String(LEWTlockPickOut,LockPickPos)
                                 + " and decide, it's not worth hanging onto anymore.");
    } else {
        llWhisper(lewtChannel,"created#"
                             +(string)pouchKey
                             +"#"
                             +llList2String(LEWTlockPickOut,LockPickPos)
                             +"#"
                             +alliance);
        llRegionSayTo(operator, 0, "You retrieve your "
                                 + llList2String(LEWTlockPickOut,LockPickPos)
                                 + " and you store it in your pouch.");
    }
    if ( pickDiceRoll > levelBonus ) {
        // Attempt failed
        llRegionSayTo(operator, 0, "You didn't succeed in picking the lock this time, "
                                 + operatorName
                                 + ". Take some time to get the nimble feeling back into your fingers."); 
    } else {
        llRegionSayTo(operator, 0, "You successfully picked the lock, "
                                 + operatorName
                                 + ". Speed be on your way, lest someone catches you in the act."); 
        llMessageLinked(LINK_THIS,2,"LEWTlockState",llGetKey());
    }
}

inspectLock()
{
    string inspectMsg;
    inspectMsg = "You inspect the lock on " + llGetObjectName() + ".";
    if(lockState==0) {
        inspectMsg += "\nThe lock is completely jammed. You'll need a locksmith, if you ever plan to open it, again.";
    } else if (lockState < 3 ) {
        inspectMsg += "\nThe lock runs smoothly.";
    } else {
        inspectMsg = "\nThe lock seems a bit stuck." 
                   + "\nPerhaps someone should have a look at it.";
    }                    
    if(llGetListLength(nonOwnerAccess)>0) {
        inspectMsg += "\nThe following people have tried to open me:");
        integer i;
        for(i=0;i<llGetListLength(nonOwnerAccess);i++) {
            inspectMsg += "\n" + llList2String(nonOwnerAccess,i));
        }
    }
    llRegionSayTo(operator,0,inspectMsg);
    llWhisper(updateChannel,(string) lockVersion);
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
        llSetRemoteScriptAccessPin( pin );
        llWhisper(updateChannel,(string) lockVersion);
        owner     = llGetOwner();
        whiteList = [owner];
        integer i;
        integer found=0;
        for(i=0;i<llGetInventoryNumber(INVENTORY_NOTECARD);i++) {
            if(llGetInventoryName(INVENTORY_NOTECARD,i)==gName) {
                settingsFound=1;
            }
        }
        if(!settingsFound) {
            llOwnerSay(gName + " notecard not found. Using default settings.");
            // Restore lock status
            lockState=llList2Integer(llParseString2List(llGetObjectDesc(),["#"],[]),lockStatePos);
            processLockState(lockState);
        } else {
            // Read notecard and register lock settings
            gLine=0;
            gQueryID = llGetNotecardLine(gName, gLine);
        }
    }
    
    dataserver(key query_id, string data)
    {
        if (query_id == gQueryID) {
            if(data != EOF) {
                processNotecardLine(data);
            } else {
                list objectState = llParseStringKeepNulls(llGetObjectDesc(),["#"],[]);
                integer i;
                if(llGetListLength(objectState)<lockStatePos) {
                    for(i=llGetListLength(objectState);i<lockStatePos;i++) {
                        if(llList2String(objectState,i)=="") objectState += [""];
                    }
                    llSetObjectDesc(llDumpList2String(objectState,"#"));
                }
                // Restore lock status
                lockState=llList2Integer(objectState,lockStatePos);
                processLockState(lockState);
            }
        }
    }
}

state jammed
{
    on_rez(integer param)
    {
        llResetScript();
    }
    
    state_entry()
    {
        lockState = 0;
        list settings = llParseStringKeepNulls(llGetObjectDesc(),["#"],[]);
        llSetObjectDesc(llDumpList2String(llListReplaceList(settings,[lockState],lockStatePos,lockStatePos),"#"));
    }
    
    link_message(integer sender_num, integer num, string str, key id)
    {
        if(str == "LEWTlockState") processLockState(num);
        if(str == "LEWTlockInspect") inspectLock();
    }
    
    changed(integer change) 
    {
        if(change&(CHANGED_INVENTORY|CHANGED_OWNER)) {
            llResetScript();
        }
    }
    
    touch_start(integer num)
    {
        touchStart   = llGetUnixTime();
        operator = llDetectedKey(0);
        operatorName = llGetDisplayName(operator);
        registerNonOwnerAccess();
    }
    
    touch_end(integer num)
    {
        if(llGetUnixTime()-touchStart<2) {
            llPlaySound("f4b0027c-e5d7-49c1-bb05-59bd3653c347",1.0);
            llWhisper(0,operatorName + " fumbles at the lock, but it remains locked.");
            return;
        }
        llRegionSayTo(operator,0,"The lock is jammed, " + operatorName + ". A locksmith might be able to free it for you.");
        llPlaySound("f4b0027c-e5d7-49c1-bb05-59bd3653c347",1.0);
        // Locksmith
        llSetTimerEvent(2.0);
        if(lewtHandle) llListenRemove(lewtHandle);
        lewtHandle=llListen(lewtChannel,"","","");
        llWhisper(lewtChannel,"convertertouched#"
                             +(string)operator
                             +"#"
                             +(string)llGetKey()
                             +"#"
                             +alliance);
    }
    
    timer()
    {
        llSetTimerEvent(0.0);
        if(lewtHandle) {
            // No timely answer from the LEWT pouch in our alliance
            llListenRemove(lewtHandle);
            lewtHandle = 0;
        }
    }
    
    listen(integer ch,string name,key id,string msg)
    {
        if(ch==lewtChannel) {
            // process LEWT message
            processLEWT(id,msg);
            if (llListFindList(pouchItems,[lockRepairParts])!=-1) {
                if (diagHandle) llListenRemove(diagHandle);
                diagHandle = llListen(diagChannel,"",operator,"");
                llDialog(operator,"Would you like to use your "
                                 +lockRepairParts
                                 +" to repair this lock?"
                                 ,["Yes","No"]
                                 ,diagChannel);
            }
        }
        if(ch==diagChannel) {
            llListenRemove(diagHandle);
            diagHandle = 0;
            if(msg == "Yes") {
                llWhisper(0,operatorName + " uses " +  lockRepairParts + " to repair the lock on " + llGetObjectName());
                llWhisper(lewtChannel,"converting#"
                                     +(string)operator
                                     +"#"
                                     +"1$" + lockRepairParts
                                     +"#"
                                     +alliance);
                llMessageLinked(LINK_THIS,2,"LEWTlockState",llGetKey());
            }
        }
    }
    
    dataserver(key query_id, string data)
    {
        if (query_id == gQueryID) {
            if(data != EOF) {
                processNotecardLine(data);
            }
        }
    }
}

state locked
{
    on_rez(integer param)
    {
        llResetScript();
    }
    
    state_entry()
    {
        lockState = 1;
        list settings = llParseStringKeepNulls(llGetObjectDesc(),["#"],[]);
        llSetObjectDesc(llDumpList2String(llListReplaceList(settings,[lockState],lockStatePos,lockStatePos),"#"));
        llPlaySound("70ebc348-e2f7-4c11-8845-0740f02555f5",1.0);
    }
    
    link_message(integer sender_num, integer num, string str, key id)
    {
        if(str == "LEWTlockState") processLockState(num);
        if(str == "LEWTlockInspect") inspectLock();
    }
    
    changed(integer change) 
    {
        if(change&(CHANGED_INVENTORY|CHANGED_OWNER)) {
            llResetScript();
        }
    }
    
    dataserver(key query_id, string data)
    {
        if (query_id == gQueryID) {
            if(data != EOF) {
                processNotecardLine(data);
            }
        }
    }
    
    touch_start(integer num)
    {
        touchStart   = llGetUnixTime();
        operator     = llDetectedKey(0);
        operatorName = llGetDisplayName(operator);
        registerNonOwnerAccess();
    }
    
    touch_end(integer num)
    {
        if(llGetUnixTime()-touchStart<2) {
            llWhisper(0,operatorName + " fumbles at the lock, but it remains locked.");
            llPlaySound("f4b0027c-e5d7-49c1-bb05-59bd3653c347",1.0);
            return;
        }
        if (llListFindList(whiteList,[operator])==-1) {
            // Thieving
            llSetTimerEvent(2.0);
            if(lewtHandle) llListenRemove(lewtHandle);
            lewtHandle=llListen(lewtChannel,"","","");
            llWhisper(lewtChannel,"convertertouched#"
                             +(string)operator
                             +"#"
                             +(string)llGetKey()
                             +"#"
                             +alliance);
        } else {
            llMessageLinked(LINK_THIS,2,"LEWTlockState",llGetKey());
        }
    }
    
    timer()
    {
        llSetTimerEvent(0.0);
        if(lewtHandle) {
            // No timely answer from the LEWT pouch in our alliance
            llListenRemove(lewtHandle);
            lewtHandle = 0;
        }
    }
    
    listen(integer ch,string name,key id,string msg)
    {
        if(ch==lewtChannel) {
            // process LEWT message
            processLEWT(id,msg);
        }
        
        if(ch==diagChannel) {
            if(msg=="Pick Lock") {
                processPickLock();
            }
        }
    }
}

state open
{
    on_rez(integer param)
    {
        llResetScript();
    }
    
    state_entry()
    {
        lockState = 2;
        list settings = llParseStringKeepNulls(llGetObjectDesc(),["#"],[]);
        llSetObjectDesc(llDumpList2String(llListReplaceList(settings,[lockState],lockStatePos,lockStatePos),"#"));
        llPlaySound("15331c0b-b26a-476c-ac92-3c3d7ac4bd78",1.0);
    }
    
    link_message(integer sender_num, integer num, string str, key id)
    {
        if(str == "LEWTlockState") processLockState(num);
        if(str == "LEWTlockInspect") inspectLock();
    }
    
    changed(integer change) 
    {
        if(change&(CHANGED_INVENTORY|CHANGED_OWNER)) {
            llResetScript();
        }
    }
    
    dataserver(key query_id, string data)
    {
        if (query_id == gQueryID) {
            if(data != EOF) {
                processNotecardLine(data);
            }
        }
    }
    
    touch_start(integer num)
    {
        touchStart   = llGetUnixTime();
        operator     = llDetectedKey(0);
        operatorName = llGetDisplayName(operator);
    }
    
    touch_end(integer num)
    {
        if(llGetUnixTime()-touchStart<2) {
            return;
        }
        if ( operator==owner ) {
            llMessageLinked(LINK_THIS,1,"LEWTlockState",llGetKey());
        }
    }
}