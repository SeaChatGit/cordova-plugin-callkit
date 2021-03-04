#import "CordovaCall.h"
#import <Cordova/CDV.h>
#import <AVFoundation/AVFoundation.h>

@implementation CordovaCall

@synthesize VoIPPushCallbackId, VoIPPushClassName, VoIPPushMethodName;

BOOL hasVideo = NO;
NSString* appName;
NSString* ringtone;
NSString* icon;
NSString* eventCallbackId;
BOOL includeInRecents = NO;
BOOL monitorAudioRouteChange = NO;
BOOL enableDTMF = NO;
NSMutableDictionary* callsMetadata;

- (BOOL)isCallKitDisabledForChina{
    BOOL isCallKitDisabledForChina = FALSE;
    
    NSLocale *currentLocale = [NSLocale currentLocale];
    
    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] isCallKitDisabledForChina: currentLocale.countryCode:'%@'", currentLocale);
    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] isCallKitDisabledForChina: currentLocale.localeIdentifier:'%@'", currentLocale.localeIdentifier);
    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] isCallKitDisabledForChina: currentLocale.countryCode:'%@'", currentLocale.countryCode);
    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] isCallKitDisabledForChina: currentLocale.languageCode:'%@'", currentLocale.languageCode);
    
    if ([currentLocale.countryCode containsString: @"CN"] || [currentLocale.countryCode containsString: @"CHN"]) {
        NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] isCallKitDisabledForChina: currentLocale is China so we CANNOT use CallKit.");
        isCallKitDisabledForChina = TRUE;
        
    } else {
        NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] isCallKitDisabledForChina: currentLocale is NOT China(CN/CHN) so we CAN use CallKit.");
        isCallKitDisabledForChina = FALSE;
    }
    
    return isCallKitDisabledForChina;
}

- (void)pluginInitialize
{
    //CALLKIT banned in china
    NSLocale *currentLocale = [NSLocale currentLocale];
    
    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] pluginInitialize: currentLocale.countryCode:'%@'", currentLocale);
    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] pluginInitialize: currentLocale.localeIdentifier:'%@'", currentLocale.localeIdentifier);
    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] pluginInitialize: currentLocale.countryCode:'%@'", currentLocale.countryCode);
    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] pluginInitialize: currentLocale.languageCode:'%@'", currentLocale.languageCode);
    
    
    
    
    CXProviderConfiguration *providerConfiguration;
    appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];
    
    providerConfiguration = [[CXProviderConfiguration alloc] initWithLocalizedName:appName];
    providerConfiguration.maximumCallGroups = 1;
    providerConfiguration.maximumCallsPerCallGroup = 1;
    
    NSMutableSet *handleTypes = [[NSMutableSet alloc] init];
    [handleTypes addObject:@(CXHandleTypePhoneNumber)];
    providerConfiguration.supportedHandleTypes = handleTypes;
    
    providerConfiguration.supportsVideo = YES;
    
    if (@available(iOS 11.0, *)) {
        providerConfiguration.includesCallsInRecents = NO;
    }
    
    //CHINA
    if ([self isCallKitDisabledForChina]) {
        NSLog(@"currentLocale is China so we cannot use CallKit.  self.provider = nil");
        //Will stop the ALERT/DECLINE VOIP UI form APPEARING
        self.provider = nil;
    } else {
        NSLog(@"currentLocale is NOT China(CN/CHN) so we cannot use CallKit.");
        
        // setup CallKit observer
        self.provider = [[CXProvider alloc] initWithConfiguration:providerConfiguration];
        [self.provider setDelegate:self queue:nil];
    }
    
    
    
    
    self.callController = [[CXCallController alloc] init];
    callsMetadata = [[NSMutableDictionary alloc]initWithCapacity:5];
    
    
    //allows user to make call from recents
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiveCallFromRecents:) name:@"RecentsCallNotification" object:nil];
   
    //detect Audio Route Changes to make speakerOn and speakerOff event handlers
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleAudioRouteChange:) name:AVAudioSessionRouteChangeNotification object:nil];
}

// CallKit - Interface
- (void)init:(CDVInvokedUrlCommand*)command
{
    eventCallbackId = command.callbackId;
}

- (void)updateProviderConfig
{
    CXProviderConfiguration *providerConfiguration;
    providerConfiguration = [[CXProviderConfiguration alloc] initWithLocalizedName:appName];
    providerConfiguration.maximumCallGroups = 1;
    providerConfiguration.maximumCallsPerCallGroup = 1;
   
    if(ringtone != nil) {
        providerConfiguration.ringtoneSound = ringtone;
    }
    
    if(icon != nil) {
        UIImage *iconImage = [UIImage imageNamed:icon];
        NSData *iconData = UIImagePNGRepresentation(iconImage);
        providerConfiguration.iconTemplateImageData = iconData;
    }
    
    NSMutableSet *handleTypes = [[NSMutableSet alloc] init];
    [handleTypes addObject:@(CXHandleTypePhoneNumber)];
    providerConfiguration.supportedHandleTypes = handleTypes;
    
    providerConfiguration.supportsVideo = hasVideo;
    
    if (@available(iOS 11.0, *)) {
        providerConfiguration.includesCallsInRecents = includeInRecents;
    }
    
    //CHINA
    if(self.provider){
        self.provider.configuration = providerConfiguration;
    }else{
        NSLog(@"self.provider is NULL - CANT SET self.provider.configuration - is user in CHINA/CN/CHN");
    }
    
}

- (void)setupAudioSession
{
    @try {
        AVAudioSession *sessionInstance = [AVAudioSession sharedInstance];
        //------------------------------------------------------------------------------------------
        [sessionInstance setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];

        //------------------------------------------------------------------------------------------
        //SPEAKERPHONE/RECEIVER(earpiece)
        //in original twilio sample but doesnt show Speaker when we tap on airplay picker
        /*! Only valid with AVAudioSessionCategoryPlayAndRecord.  Appropriate for Voice over IP
         (VoIP) applications.  Reduces the number of allowable audio routes to be only those
         that are appropriate for VoIP applications and may engage appropriate system-supplied
         signal processing.  Has the side effect of setting AVAudioSessionCategoryOptionAllowBluetooth */
        //WRONG - use AVAudioSessionModeVideoChat
        //[sessionInstance setMode:AVAudioSessionModeVoiceChat error:nil];
        //------------------------------------------------------------------------------------------

        /*! Only valid with kAudioSessionCategory_PlayAndRecord. Reduces the number of allowable audio
         routes to be only those that are appropriate for video chat applications. May engage appropriate
         system-supplied signal processing.  Has the side effect of setting
         AVAudioSessionCategoryOptionAllowBluetooth and AVAudioSessionCategoryOptionDefaultToSpeaker. */
        //SPEAKERPHONE - REQUIRED ELSE SPEAKER doesnt appear
        
        //SEE ALSO https://developer.apple.com/library/archive/qa/qa1803/_index.html
        
        [sessionInstance setMode:AVAudioSessionModeVideoChat error:nil];
        
        //------------------------------------------------------------------------------------------
        //   //https://github.com/iFLYOS-OPEN/SDK-EVS-iOS/blob/a111b7765fab62586be72199c417e2b103317e44/Pod/Classes/common/media_player/AudioSessionManager.m
        //   [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker|AVAudioSessionCategoryOptionMixWithOthers error:nil];
        //   [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:nil];
        //   [[AVAudioSession sharedInstance] setActive:YES error:nil];
        //------------------------------------------------------------------------------------------
    
        NSTimeInterval bufferDuration = .005;
        [sessionInstance setPreferredIOBufferDuration:bufferDuration error:nil];
        [sessionInstance setPreferredSampleRate:44100 error:nil];
        NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] setupAudioSession: Configured Audio");
    }
    @catch (NSException *exception) {
        NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] setupAudioSession: Unknown error returned from setupAudioSession");
    }
    return;
}

- (void)setAppName:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = nil;
    NSString* proposedAppName = [command.arguments objectAtIndex:0];
    
    if (proposedAppName != nil && [proposedAppName length] > 0) {
        appName = proposedAppName;
        [self updateProviderConfig];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"App Name Changed Successfully"];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"App Name Can't Be Empty"];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)setIcon:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = nil;
    NSString* proposedIconName = [command.arguments objectAtIndex:0];
    
    if (proposedIconName == nil || [proposedIconName length] == 0) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Icon Name Can't Be Empty"];
    } else if([UIImage imageNamed:proposedIconName] == nil) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"This icon does not exist. Make sure to add it to your project the right way."];
    } else {
        icon = proposedIconName;
        [self updateProviderConfig];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"Icon Changed Successfully"];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)setRingtone:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = nil;
    NSString* proposedRingtoneName = [command.arguments objectAtIndex:0];
    
    if (proposedRingtoneName == nil || [proposedRingtoneName length] == 0) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Ringtone Name Can't Be Empty"];
    } else {
        ringtone = [NSString stringWithFormat: @"%@.caf", proposedRingtoneName];
        [self updateProviderConfig];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"Ringtone Changed Successfully"];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)setIncludeInRecents:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = nil;
    includeInRecents = [[command.arguments objectAtIndex:0] boolValue];
    [self updateProviderConfig];
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"includeInRecents Changed Successfully"];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)setDTMFState:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = nil;
    enableDTMF = [[command.arguments objectAtIndex:0] boolValue];
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"enableDTMF Changed Successfully"];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)setVideo:(CDVInvokedUrlCommand*)command
{
    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] setVideo: CALLED");
    
    CDVPluginResult* pluginResult = nil;
    hasVideo = [[command.arguments objectAtIndex:0] boolValue];
    [self updateProviderConfig];
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"hasVideo Changed Successfully"];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

#pragma mark -
#pragma mark VOIP CALL IN - receiveCall
#pragma mark -
- (void)receiveCall:(CDVInvokedUrlCommand*)command
{
    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] receiveCall: CALLED - REMOTE USER CALLS IOS");
    
    NSDictionary *incomingCall = [command.arguments objectAtIndex:0];
    if (incomingCall == nil) {
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Call is not defined"] callbackId:command.callbackId];
    }
    
    BOOL hasId = ![incomingCall[@"callId"] isEqual:[NSNull null]];
    NSString* callName = incomingCall[@"callName"];
    NSString* callId = hasId?incomingCall[@"callId"]:callName;
    
    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] receiveCall: INCOMING callId:'%@'", callId);
    
    
    NSUUID *callUUID = [[NSUUID alloc] init];
    
    if (hasId) {
        [[NSUserDefaults standardUserDefaults] setObject:callName forKey:callId];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    
    if (callName != nil && [callName length] > 0) {
        CXHandle *handle = [[CXHandle alloc] initWithType:CXHandleTypePhoneNumber value:callId];
        CXCallUpdate *callUpdate = [[CXCallUpdate alloc] init];
        
        callUpdate.remoteHandle = handle; //<<CXHandle callId
        
        callUpdate.hasVideo = hasVideo;
        callUpdate.localizedCallerName = callName;
        callUpdate.supportsGrouping = NO;
        callUpdate.supportsUngrouping = NO;
        callUpdate.supportsHolding = NO;
        callUpdate.supportsDTMF = enableDTMF;
        
        
        //------------------------------------------------------------------------------------------
        //CHINA
        if(self.provider){
            //--------------------------------------------------------------------------------------
            //SHOWS the ANSWER/DECLINE VOIP CALL ALERT
            //--------------------------------------------------------------------------------------
            [self.provider reportNewIncomingCallWithUUID:callUUID
                                                  update:callUpdate
                                              completion:^(NSError * _Nullable error)
            {
                if(error == nil) {
                    //------------------------------------------------------------------------------
                    //RETURNS IMMEDIATELY - the Answer/Decline ui should be showing and phone ringing
                    //if user presses ANSWER it comes out in DELEGATE performAnswerCallAction:
                    //if user presses DECLINE it comes out in DELEGATE performAnswerCallAction:
                    //------------------------------------------------------------------------------
                    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                                             messageAsString:@"Incoming call successful"]
                                                callbackId:command.callbackId];
                    //------------------------------------------------------------------------------
                    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] receiveCall: INCOMING callsMetadata setValue:incomingCall forKey:UUID:%@", [callUUID UUIDString]);
                    [callsMetadata setValue:incomingCall forKey:[callUUID UUIDString]];
                    //------------------------------------------------------------------------------
                    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] receiveCall: RESPONSE 'receiveCall' payload:%@", incomingCall);
                    [self sendEvent:@"receiveCall" payload:incomingCall];
                } else {
                    //------------------------------------------------------------------------------
                    //ERROR
                    //------------------------------------------------------------------------------
                    [self logIncomingCallError: error];
                    
                    //------------------------------------------------------------------------------
                    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error localizedDescription]] callbackId:command.callbackId];
                }
            }];
            //----------------------------------------------------------------------------------
        }else{
            NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] receiveCall: self.provider is NULL");
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"provider is nil"] callbackId:command.callbackId];
        }
        //------------------------------------------------------------------------------------------
        
    } else {
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Caller id can't be empty"] callbackId:command.callbackId];
    }
}

-(void) logIncomingCallError:(NSError *) error{
    
    //----------------------------------------------------------------------------------------------
    //https://developer.apple.com/documentation/callkit/cxerrorcodeincomingcallerror?language=objc
    //----------------------------------------------------------------------------------------------
    //    CXErrorCodeIncomingCallErrorUnknown
    //    An unknown error occurred.
    
    //    CXErrorCodeIncomingCallErrorUnentitled
    //    The app isn’t entitled to receive incoming calls.
    
    //    CXErrorCodeIncomingCallErrorCallUUIDAlreadyExists
    //    The incoming call UUID already exists.
    
    //    CXErrorCodeIncomingCallErrorFilteredByDoNotDisturb
    //    The incoming call is filtered because Do Not Disturb is active and the incoming caller is not a VIP.
    
    //    CXErrorCodeIncomingCallErrorFilteredByBlockList
    //    The incoming call is filtered because the incoming caller has been blocked by the user.
    //----------------------------------------------------------------------------------------------
    
    NSInteger errorCode = [error code];
    if(CXErrorCodeIncomingCallErrorUnknown == errorCode){
        NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] receiveCall:  >> reportNewIncomingCallWithUUID FAILED error:%@ [CXErrorCodeIncomingCallErrorUnknown]", error);
        
    }else if(CXErrorCodeIncomingCallErrorUnentitled == errorCode){
        NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] receiveCall:  >> reportNewIncomingCallWithUUID FAILED error:%@ [CXErrorCodeIncomingCallErrorUnentitled]", error);
        
    }else if(CXErrorCodeIncomingCallErrorCallUUIDAlreadyExists == errorCode){
        NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] receiveCall:  >> reportNewIncomingCallWithUUID FAILED error:%@ [CXErrorCodeIncomingCallErrorCallUUIDAlreadyExists]", error);
        
    }else if(CXErrorCodeIncomingCallErrorFilteredByDoNotDisturb == errorCode){
        NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] receiveCall:  >> reportNewIncomingCallWithUUID FAILED error:%@ [CXErrorCodeIncomingCallErrorFilteredByDoNotDisturb]", error);
        
    }else if(CXErrorCodeIncomingCallErrorFilteredByBlockList == errorCode){
        NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] receiveCall:  >> reportNewIncomingCallWithUUID FAILED error:%@ [CXErrorCodeIncomingCallErrorFilteredByBlockList]", error);
        
    }else {
        NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] receiveCall:  >> reportNewIncomingCallWithUUID FAILED error:%@ [UNHANDLED]", error);
    }
}

#pragma mark -
#pragma mark sendCall
#pragma mark -
- (void)sendCall:(CDVInvokedUrlCommand*)command
{
    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] sendCall: CALLED");
    
    NSDictionary *outgoingCall = [command.arguments objectAtIndex:0];
    if(outgoingCall == nil) {
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Call is not defined"] callbackId:command.callbackId];
    }
    BOOL hasId = ![outgoingCall[@"callId"] isEqual:[NSNull null]];
    NSString* callName = outgoingCall[@"callName"];
    NSString* callId = hasId?outgoingCall[@"callId"]:callName;
    NSUUID *callUUID = [[NSUUID alloc] init];
    
    if (hasId) {
        [[NSUserDefaults standardUserDefaults] setObject:callName forKey:callId];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    
    if (callName != nil && [callName length] > 0) {
        CXHandle *handle = [[CXHandle alloc] initWithType:CXHandleTypePhoneNumber value:callId];
        CXStartCallAction *startCallAction = [[CXStartCallAction alloc] initWithCallUUID:callUUID handle:handle];
        startCallAction.contactIdentifier = callName;
        startCallAction.video = hasVideo;
        CXTransaction *transaction = [[CXTransaction alloc] initWithAction:startCallAction];
        [self.callController requestTransaction:transaction completion:^(NSError * _Nullable error) {
            if (error == nil) {
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"Outgoing call successful"] callbackId:command.callbackId];
                
                NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] sendCall: callsMetadata setValue:outgoingCall forKey:UUID:%@", [callUUID UUIDString]);
                [callsMetadata setValue:outgoingCall forKey:[callUUID UUIDString]];
            } else {
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error localizedDescription]] callbackId:command.callbackId];
            }
        }];
    } else {
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"The caller id can't be empty"] callbackId:command.callbackId];
    }
}

- (void)connectCall:(CDVInvokedUrlCommand*)command
{
    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] connectCall: CALLED");
    
    CDVPluginResult* pluginResult = nil;
    NSArray<CXCall *> *calls = self.callController.callObserver.calls;
    
    if([calls count] == 1) {
        
        //CHINA
        if(self.provider){
            //--------------------------------------------------------------------------------------
            [self.provider reportOutgoingCallWithUUID:calls[0].UUID connectedAtDate:nil];
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"Call connected successfully"];
            //--------------------------------------------------------------------------------------
        }else{
            NSLog(@"self.provider is NULL - [self.provider reportOutgoingCallWithUUID:...] FAILED - is user in CHINA/CN/CHN");
            
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"provider is null"];
        }
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"No call exists for you to connect"];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

#pragma mark -
#pragma mark END CALL - endCall
#pragma mark -
- (void)endCall:(CDVInvokedUrlCommand*)command
{
    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] endCall: START ********");
    CDVPluginResult* pluginResult = nil;
    
    if(NULL != command){
        if(NULL != command.arguments){
            if(command.arguments > 0){
                NSString *callIdToEnd = [command.arguments objectAtIndex:0];
                
                NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] endCall: CALLED callIdToEnd:%@", callIdToEnd);
                
                if(NULL != callIdToEnd){
                    //------------------------------------------------------------------------------------------
                    NSArray<CXCall *> *calls = self.callController.callObserver.calls;
                    
                    if(NULL != calls){
                        //--------------------------------------------------------------------------------------
                        if([calls count] > 0) {
                            //----------------------------------------------------------------------------------
                            //[self.provider reportCallWithUUID:calls[0].UUID endedAtDate:nil reason:CXCallEndedReasonRemoteEnded];
                            
                            //----------------------------------------------------------------------
                            //SEARCH for Call by callid
                            //----------------------------------------------------------------------
                            CXCall* callToEnd = [self findCall: callIdToEnd];

                            if(NULL != callToEnd){
                                if(callToEnd.hasEnded){
                                    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] endCall: END CALL callToEnd.hasEnded: TRUE");
                                }else{
                                    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] endCall: END CALL callToEnd.hasEnded: FALSE");
                                }
                                if(callToEnd.hasConnected){
                                    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] endCall: END CALL callToEnd.hasConnected: TRUE");
                                }else{
                                    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] endCall: END CALL callToEnd.hasConnected: FALSE");
                                }
                                
                                //----------------------------------------------------------------------------------------
                                //ISSUE - multiple endCall(callID) for the same call id can come in
                                //----------------------------------------------------------------------------------------
                                
                                if(NULL != [callToEnd UUID]){
                                    NSString * UUIDString = [[callToEnd UUID] UUIDString];
                                    if(NULL != UUIDString){
                                        //----------------------------------------------------------------------------------------
                                        NSDictionary* callDict_callsMetadata = [self findCallIn_callsMetadata: UUIDString];
                                        
                                        if(NULL != callDict_callsMetadata){
                                            //------------------------------------------------------
                                            //REMOVE ONCE
                                            //------------------------------------------------------
                                            [self removeCallFrom_callsMetadata: UUIDString];
                                            
                                            
                                            //--------------------------------------------------------------
                                            //END CALL
                                            //--------------------------------------------------------------
                                            
                                            CXEndCallAction *endCallAction = [[CXEndCallAction alloc] initWithCallUUID:callToEnd.UUID];
                                            
                                            CXTransaction *transaction = [[CXTransaction alloc] initWithAction:endCallAction];
                                            
                                            [self.callController requestTransaction:transaction completion:^(NSError * _Nullable error) {
                                                //--------------------------------------------------------------
                                                if (error == nil) {
                                                    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] endCall: END CALL requestTransaction: OK");
                                                    
                                                } else {
                                                    NSString * errorAsString = [self requestTransactionErrorString:[error code]];
                                                    
                                                    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] endCall: END CALL requestTransaction: callToEnd.UUID ERROR:%@ ERROR CODE: %@",[error localizedDescription], errorAsString);
                                                    
                                                }
                                                //--------------------------------------------------------------
                                                if(callToEnd.hasEnded){
                                                    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] endCall: END CALL callToEnd.hasEnded: TRUE");
                                                }else{
                                                    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] endCall: END CALL callToEnd.hasEnded: FALSE");
                                                }
                                                if(callToEnd.hasConnected){
                                                    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] endCall: END CALL callToEnd.hasConnected: TRUE");
                                                }else{
                                                    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] endCall: END CALL callToEnd.hasConnected: FALSE");
                                                }
                                                //    endCall: END CALL callToEnd.hasEnded: FALSE
                                                //    endCall: END CALL callToEnd.hasConnected: TRUE
                                                //--------------------------------------------------------------
                                                
                                                NSArray<CXCall *> *calls = self.callController.callObserver.calls;
                                                NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] endCall: AFTER TRANSACTION [calls count]:%ld", [calls count]);
                                                
                                                NSLog(@"");
                                                
                                            }];
                                            
                                            //------------------------------------------------------------------
                                            NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] endCall: return response:OK : 'Call ended successfully'");
                                            
                                            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                                             messageAsString:@"Call ended successfully"];
                                            //------------------------------------------------------------------
                                            
                                        }else{
                                            NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] endCall: callIn_callsMetadata is NULL - SKIP END CALL");
                                            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"End Call handled already"];
                                        }
                                        //----------------------------------------------------------------------------------------
                                    }else{
                                        NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] endCall: UUIDString is NULL");
                                    }
                                }else{
                                    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] endCall:  [callToEnd UUID]is NULL");
                                }
                                
                            }else{
                                //------------------------------------------------------------------
                                NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] endCall: callToEnd is NULL - No call exists to END for callId:'%@'", callIdToEnd);
                                
                                //WRONG CAUSES Call Decline on 2nd incoming call
                                //    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                //                                     messageAsString:[NSString stringWithFormat:@"No call exists to END for callId:'%@'", callIdToEnd]];
                                
                                //@nd incoming call can connect now
                                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                                 messageAsString:[NSString stringWithFormat:@"No call exists to END for callId:'%@'", callIdToEnd]];
                                //------------------------------------------------------------------
                            }
                        }
                        else{
                            NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] endCall: return response: : 'No call exists for you to connect' - DONT RETURN RESPONSE DUPLICATE END CALLS");
  //DONT RETURN THIS                          pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"No call exists for you to connect"];
                        }
                        //--------------------------------------------------------------------------
                    }else{
                        NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] endCall: calls is NULL - cant find call to end");
                    }
                }else{
                    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] endCall: callIdToEnd is NULL - cant find call to end");
                }
            }else{
                NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] endCall: command.arguments is 0 - callId to end not passed in");
            }
        }else{
            NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] endCall: command.arguments is NULL");
        }
    }else{
        NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] endCall: command is NULL");
    }
    
    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] endCall: END ******** WITH pluginResult:'%@'", pluginResult.message);
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}


-(NSDictionary*) findCallIn_callsMetadata:(NSString*) UUIDString{
    NSDictionary *callDictFound = NULL;
    
    if(NULL != UUIDString){
        if(NULL != callsMetadata){
            
            callDictFound = callsMetadata[UUIDString];
            
            if(NULL != callDictFound){
                NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] findCallIn_callsMetadata: callDictFound FOUND: %@", callDictFound);
            }else{
                NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] findCallIn_callsMetadata: callDictFound NOT FOUND");
            }
            
        }else{
            NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] findCallIn_callsMetadata: callsMetadata is NULL");
        }
    }else{
        NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] findCallIn_callsMetadata: UUIDString is NULL");
    }

    return callDictFound;
}

-(BOOL) removeCallFrom_callsMetadata:(NSString*) UUIDString{

    BOOL success = FALSE;
    
    if(NULL != UUIDString){
        
        if(NULL != callsMetadata){
            //----------------------------------------------------------------------------------
            NSDictionary *callFound = callsMetadata[UUIDString];
            if(NULL != callFound){
                
                [callsMetadata removeObjectForKey:UUIDString];
                
                NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] removeCallFrom_callsMetadata: SUCCESS - callsMetadata REMOVED UUID:'%@'", UUIDString);
                success = TRUE;
                
            }else{
                NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] removeCallFrom_callsMetadata: ERROR - UUID NOT FOUND IN callsMetadata:'%@'", UUIDString);
            }
            //----------------------------------------------------------------------------------
        }else{
            NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] removeCallFrom_callsMetadata: ERROR - callsMetadata is NULL");
        }
    }else{
        NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] removeCallFrom_callsMetadata: ERROR - [callToRemove UUID] is NULL");
    }
    return success;
}

-(CXCall*) findCall:(NSString *)callIdToEnd{
    CXCall* callToEnd = NULL;
    
    //----------------------------------------------------------------------------------------------
    NSArray<CXCall *> *calls = self.callController.callObserver.calls;
    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] findCall: SEARCH [calls count]:'%ld'", [calls count]);
    if(NULL != calls){
        
        if([calls count] > 0) {
            //--------------------------------------------------------------------------------------
            for (CXCall* callInCalls in calls) {
                
                NSString * call0_UUID = [callInCalls.UUID description];
                
                if(NULL != call0_UUID){
                    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] findCall: SEARCH call0_UUID:'%@'", call0_UUID);
                    
                    NSDictionary *callDictionary = callsMetadata[call0_UUID];
                    if(NULL != callDictionary){
                        
                        NSString* callIdInDict = [callDictionary objectForKey:@"callId"];
                        
                        if(NULL != callIdInDict){
                            NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] findCall: callIdInDict:'%@'", callIdInDict);
                            
                            if([callIdInDict isEqualToString: callIdToEnd]){
                                NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] findCall: MATCH: CALL FOUND");
                                
                                callToEnd = callInCalls;
                                
                                break;
                            }else{
                                //NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] findCall: NO MATCH - skip");
                            }
                            
                        }else{
                            NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] findCall: callIdInDict is NULL - cant find callId in calls[]");
                        }
                    }else{
                        NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] findCall: callDictionary is NULL - cant find callId in calls[]");
                    }
                }else{
                    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] findCall: call0_UUID is null - cant find callId in calls[]");
                }
            }
            //--------------------------------------------------------------------------------------
        }
        else{
            NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] endCall: return response:OK : 'Call ended successfully'");
        }
        //------------------------------------------------------------------------------------------
    }else{
        NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] endCall: calls is NULL - cant find call to end");
    }
    
    return callToEnd;
}
-(NSString *) requestTransactionErrorString:(NSInteger) errorCode{
    NSString * result = @"";
    
    //----------------------------------------------------------------------------------------------
    //https://developer.apple.com/documentation/callkit/cxerrorcoderequesttransactionerror?language=objc
    //----------------------------------------------------------------------------------------------
    //    typedef NS_ERROR_ENUM(CXErrorDomainRequestTransaction, CXErrorCodeRequestTransactionError) {
    //        CXErrorCodeRequestTransactionErrorUnknown = 0,
    //        CXErrorCodeRequestTransactionErrorUnentitled = 1,
    //        CXErrorCodeRequestTransactionErrorUnknownCallProvider = 2,
    //        CXErrorCodeRequestTransactionErrorEmptyTransaction = 3,
    //        CXErrorCodeRequestTransactionErrorUnknownCallUUID = 4,
    //        CXErrorCodeRequestTransactionErrorCallUUIDAlreadyExists = 5,
    //        CXErrorCodeRequestTransactionErrorInvalidAction = 6,
    //        CXErrorCodeRequestTransactionErrorMaximumCallGroupsReached = 7,
    //    } API_AVAILABLE(ios(10.0), macCatalyst(13.0), macos(11.0))  API_UNAVAILABLE(watchos, tvos);
    //----------------------------------------------------------------------------------------------
    if(CXErrorCodeRequestTransactionErrorUnknown == errorCode){
        result = @"CXErrorCodeRequestTransactionErrorUnknown";
        
    }else if(CXErrorCodeRequestTransactionErrorUnentitled == errorCode){
        result = @"CXErrorCodeRequestTransactionErrorUnentitled";
        
    }else if(CXErrorCodeRequestTransactionErrorUnknownCallProvider == errorCode){
        result = @"CXErrorCodeRequestTransactionErrorUnknownCallProvider";
        
    }else if(CXErrorCodeRequestTransactionErrorEmptyTransaction == errorCode){
        result = @"CXErrorCodeRequestTransactionErrorEmptyTransaction";
        
    }else if(CXErrorCodeRequestTransactionErrorUnknownCallUUID == errorCode){
        result = @"CXErrorCodeRequestTransactionErrorUnknownCallUUID";
        
    }else if(CXErrorCodeRequestTransactionErrorCallUUIDAlreadyExists == errorCode){
        result = @"CXErrorCodeRequestTransactionErrorCallUUIDAlreadyExists";
        
    }else if(CXErrorCodeRequestTransactionErrorInvalidAction == errorCode){
        result = @"CXErrorCodeRequestTransactionErrorInvalidAction";
        
    }else if(CXErrorCodeRequestTransactionErrorMaximumCallGroupsReached == errorCode){
        result = @"CXErrorCodeRequestTransactionErrorMaximumCallGroupsReached";
        
    }else {
        NSLog(@"ERROR UNKNOWN CXErrorCodeRequestTransactionError");
    }
    return result;
}




- (void)mute:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = nil;
    AVAudioSession *sessionInstance = [AVAudioSession sharedInstance];
    if(sessionInstance.isInputGainSettable) {
        BOOL success = [sessionInstance setInputGain:0.0 error:nil];
        if(success) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"Muted Successfully"];
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"An error occurred"];
        }
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not muted because this device does not allow changing inputGain"];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)unmute:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = nil;
    AVAudioSession *sessionInstance = [AVAudioSession sharedInstance];
    if(sessionInstance.isInputGainSettable) {
        BOOL success = [sessionInstance setInputGain:1.0 error:nil];
        if(success) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"Muted Successfully"];
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"An error occurred"];
        }
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not unmuted because this device does not allow changing inputGain"];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)speakerOn:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = nil;
    AVAudioSession *sessionInstance = [AVAudioSession sharedInstance];
    
    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m][AUDIO] speakerOn: overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker");
    
    BOOL success = [sessionInstance overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:nil];
    if(success) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"Speakerphone is on"];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"An error occurred"];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)speakerOff:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = nil;
    AVAudioSession *sessionInstance = [AVAudioSession sharedInstance];
    
    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m][AUDIO] speakerOff: overrideOutputAudioPort:AVAudioSessionPortOverrideNone");
    
    BOOL success = [sessionInstance overrideOutputAudioPort:AVAudioSessionPortOverrideNone error:nil];
    if(success) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"Speakerphone is off"];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"An error occurred"];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)callNumber:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = nil;
    NSString* phoneNumber = [command.arguments objectAtIndex:0];
    NSString* telNumber = [@"tel://" stringByAppendingString:phoneNumber];
    if (@available(iOS 10.0, *)) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:telNumber]
                                           options:nil
                                 completionHandler:^(BOOL success) {
            if(success) {
                CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"Call Successful"];
                [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            } else {
                CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Call Failed"];
                [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            }
        }];
    } else {
        BOOL success = [[UIApplication sharedApplication] openURL:[NSURL URLWithString:telNumber]];
        if(success) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"Call Successful"];
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Call Failed"];
        }
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }
    
}

- (void)reportCallEndedReason:(CDVInvokedUrlCommand *)command
{
    NSString* callId = [command.arguments objectAtIndex:0];
    NSString* reason = [command.arguments objectAtIndex:1];
    if ([reason isEqualToString:@"CallAnsweredElsewhere"]) {
        NSUUID* callUUID = [self getCallUUID:callId];
        if(callUUID != nil) {
            NSArray<CXCall *> *calls = self.callController.callObserver.calls;
            if([calls count] == 1 && [calls[0].UUID isEqual:callUUID] && !calls[0].hasConnected && !calls[0].hasEnded) {
                [self.provider reportCallWithUUID:calls[0].UUID endedAtDate:[[NSDate alloc] init] reason:CXCallEndedReasonAnsweredElsewhere];
            }
        }
    } else if ([reason isEqualToString:@"CallDeclinedElsewhere"]) {
        NSUUID* callUUID = [self getCallUUID:callId];
        if(callUUID != nil) {
            NSArray<CXCall *> *calls = self.callController.callObserver.calls;
            if([calls count] == 1 && [calls[0].UUID isEqual:callUUID] && !calls[0].hasEnded) {
                [self.provider reportCallWithUUID:calls[0].UUID endedAtDate:[[NSDate alloc] init] reason:CXCallEndedReasonDeclinedElsewhere];
            }
        }
    } else if ([reason isEqualToString:@"CallMissed"]) {
        NSUUID* callUUID = [self getCallUUID:callId];
        if(callUUID != nil) {
            NSArray<CXCall *> *calls = self.callController.callObserver.calls;
            if([calls count] == 1 && [calls[0].UUID isEqual:callUUID] && !calls[0].hasEnded) {
                [self.provider reportCallWithUUID:calls[0].UUID endedAtDate:[[NSDate alloc] init] reason:CXCallEndedReasonUnanswered];
            }
        }
    } else if ([reason isEqualToString:@"CallCompleted"]) {
        NSUUID* callUUID = [self getCallUUID:callId];
        if(callUUID != nil) {
            NSArray<CXCall *> *calls = self.callController.callObserver.calls;
            if([calls count] == 1 && [calls[0].UUID isEqual:callUUID] && !calls[0].hasEnded) {
                [self.provider reportCallWithUUID:calls[0].UUID endedAtDate:[[NSDate alloc] init] reason:CXCallEndedReasonRemoteEnded];
            }
        }
    }

    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)receiveCallFromRecents:(NSNotification *) notification
{
    NSString* callID = notification.object[@"callId"];
    NSString* callName = notification.object[@"callName"];
    NSUUID *callUUID = [[NSUUID alloc] init];
    CXHandle *handle = [[CXHandle alloc] initWithType:CXHandleTypePhoneNumber value:callID];
    CXStartCallAction *startCallAction = [[CXStartCallAction alloc] initWithCallUUID:callUUID handle:handle];
    startCallAction.video = [notification.object[@"isVideo"] boolValue]?YES:NO;
    startCallAction.contactIdentifier = callName;
    CXTransaction *transaction = [[CXTransaction alloc] initWithAction:startCallAction];
    [self.callController requestTransaction:transaction completion:^(NSError * _Nullable error) {
        if (error == nil) {
        } else {
            NSLog(@"%@",[error localizedDescription]);
        }
    }];
}

- (void)handleAudioRouteChange:(NSNotification *) notification
{
    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m][AUDIO] handleAudioRouteChange: START ********");
    
    //NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m][AUDIO] handleAudioRouteChange: notification:\r%@", notification);
    
    
    //    if(monitorAudioRouteChange) {
    //
    //        NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m][AUDIO] handleAudioRouteChange: notification.userInfo:\r%@", notification.userInfo);
    //
    //
    //        NSNumber* reasonValue = notification.userInfo[@"AVAudioSessionRouteChangeReasonKey"];
    //        AVAudioSessionRouteDescription* previousRouteKey = notification.userInfo[@"AVAudioSessionRouteChangePreviousRouteKey"];
    //        NSArray* outputs = [previousRouteKey outputs];
    //        if([outputs count] > 0) {
    //            AVAudioSessionPortDescription *output = outputs[0];
    //
    //            //--------------------------------------------------------------------------------------
    //            //SPEAKERPHONE
    //            //--------------------------------------------------------------------------------------
    //            //BC - if you change from Speaker to iPhone in the AirPLay picker this tell cordova
    //            //'Speaker' > speakerOn     - AVAudioSessionPortBuiltInSpeaker constant maps to string 'Speaker'
    //            //NOT'Speaker' > speakerOff - 'Receiver' //AVAudioSessionPortBuiltInReceiver
    //            //--------------------------------------------------------------------------------------
    //            if(![output.portType isEqual: @"Speaker"] && [reasonValue isEqual:@4]) {
    //
    //                // The route has been overridden (e.g. category is AVAudioSessionCategoryPlayAndRecord and
    //                // the output has been changed from the receiver, which is the default, to the speaker).
    //                //        AVAudioSessionRouteChangeReasonOverride = 4,
    //
    //                [self sendEvent:@"speakerOn" payload:@{}];
    //
    //            } else if([output.portType isEqual: @"Speaker"] && [reasonValue isEqual:@3]) {
    //
    //                [self sendEvent:@"speakerOff" payload:@{}];
    //
    //            }else{
    //                NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m][AUDIO] handleAudioRouteChange: monitorAudioRouteChange is off - do nothing");
    //
    //            }
    //        }
    //    }else{
    //        NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m][AUDIO] handleAudioRouteChange: monitorAudioRouteChange is off - do nothing");
    //
    //    }
    
    
    
    

    if(NULL != notification){
        //------------------------------------------------------------------------------------------
        //Name
        //------------------------------------------------------------------------------------------
        if(NULL != notification.name){
            NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m][AUDIO] handleAudioRouteChange: notification.name:%@", notification.name);
        }else{
            NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] handleAudioRouteChange: handleAudioRouteChange is NULL");
        }
        
        //------------------------------------------------------------------------------------------
        //RouteChangeReason
        //------------------------------------------------------------------------------------------
        NSNumber* reasonValueNumber = notification.userInfo[@"AVAudioSessionRouteChangeReasonKey"];
        if(NULL != reasonValueNumber){
            NSString * reasonString = [self stringForAVAudioSessionRouteChangeReason:[reasonValueNumber intValue]];
            
            NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m][AUDIO] handleAudioRouteChange: RouteChangeReason: %@", reasonString);
            
        }else{
            NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m][AUDIO] handleAudioRouteChange: reasonValueNumberis NULL");
        }
        
        AVAudioSessionRouteDescription* previousRoute = notification.userInfo[@"AVAudioSessionRouteChangePreviousRouteKey"];
        if(NULL != previousRoute){
            //--------------------------------------------------------------------------------------
            NSArray* inputs = [previousRoute inputs];
            NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m][AUDIO] handleAudioRouteChange: [inputs count]: %ld", [inputs count]);
            for (AVAudioSessionPortDescription *input in inputs) {
                NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m][AUDIO] handleAudioRouteChange: INPUT: %@", input);
            }
            //--------------------------------------------------------------------------------------
            NSArray* outputs = [previousRoute outputs];
            NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m][AUDIO] handleAudioRouteChange: [outputs count]: %ld", [outputs count]);
            for (AVAudioSessionPortDescription *output in outputs) {
                NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m][AUDIO] handleAudioRouteChange: OUTPUT: %@", output);
            }

            NSString * reasonString = [self stringForAVAudioSessionRouteChangeReason:[reasonValueNumber intValue]];
            NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m][AUDIO] handleAudioRouteChange: RouteChangeReason: %@", reasonString);
            
        }else{
            NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m][AUDIO] handleAudioRouteChange: reasonValueNumberis NULL");
        }
        
        //------------------------------------------------------------------------------------------
    }else{
        NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] handleAudioRouteChange: handleAudioRouteChange is NULL");
    }
    
    

    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m][AUDIO] handleAudioRouteChange: END ********");

}
- (NSString *) stringForAVAudioSessionRouteChangeReason:(int) reasonValue{
    NSString * reason = @"ERROR_UNHANDLED_RouteChangeReason";

    
    //----------------------------------------------------------------------------------------------
    //    typedef NS_ENUM(NSUInteger, AVAudioSessionRouteChangeReason) {
    //        /// The reason is unknown.
    //        AVAudioSessionRouteChangeReasonUnknown = 0,
    //
    //        /// A new device became available (e.g. headphones have been plugged in).
    //        AVAudioSessionRouteChangeReasonNewDeviceAvailable = 1,
    //
    //        /// The old device became unavailable (e.g. headphones have been unplugged).
    //        AVAudioSessionRouteChangeReasonOldDeviceUnavailable = 2,
    //
    //        /// The audio category has changed (e.g. AVAudioSessionCategoryPlayback has been changed to
    //        /// AVAudioSessionCategoryPlayAndRecord).
    //        AVAudioSessionRouteChangeReasonCategoryChange = 3,
    //
    //        /// The route has been overridden (e.g. category is AVAudioSessionCategoryPlayAndRecord and
    //        /// the output has been changed from the receiver, which is the default, to the speaker).
    //        AVAudioSessionRouteChangeReasonOverride = 4,
    //
    //        /// The device woke from sleep.
    //        AVAudioSessionRouteChangeReasonWakeFromSleep = 6,
    //
    //        /// Returned when there is no route for the current category (for instance, the category is
    //        /// AVAudioSessionCategoryRecord but no input device is available).
    //        AVAudioSessionRouteChangeReasonNoSuitableRouteForCategory = 7,
    //
    //        /// Indicates that the set of input and/our output ports has not changed, but some aspect of
    //        /// their configuration has changed.  For example, a port's selected data source has changed.
    //        /// (Introduced in iOS 7.0, watchOS 2.0, tvOS 9.0).
    //        AVAudioSessionRouteChangeReasonRouteConfigurationChange = 8
    //    };
    //----------------------------------------------------------------------------------------------
    
    if(AVAudioSessionRouteChangeReasonUnknown == reasonValue){
        reason = @"AVAudioSessionRouteChangeReasonUnknown";
        
    }
    else if(AVAudioSessionRouteChangeReasonNewDeviceAvailable == reasonValue){
        reason = @"AVAudioSessionRouteChangeReasonNewDeviceAvailable";
        
    }
    else if(AVAudioSessionRouteChangeReasonOldDeviceUnavailable == reasonValue){
        reason = @"AVAudioSessionRouteChangeReasonOldDeviceUnavailable";
        
    }
    else if(AVAudioSessionRouteChangeReasonCategoryChange == reasonValue){
        reason = @"AVAudioSessionRouteChangeReasonCategoryChange";
        
    }
    else if(AVAudioSessionRouteChangeReasonOverride == reasonValue){
        reason = @"AVAudioSessionRouteChangeReasonOverride";
        
    }
    else if(AVAudioSessionRouteChangeReasonWakeFromSleep == reasonValue){
        reason = @"AVAudioSessionRouteChangeReasonWakeFromSleep";
        
    }
    else if(AVAudioSessionRouteChangeReasonUnknown == reasonValue){
        reason = @"AVAudioSessionRouteChangeReasonUnknown";
        
    }
    else if(AVAudioSessionRouteChangeReasonRouteConfigurationChange == reasonValue){
        reason = @"AVAudioSessionRouteChangeReasonRouteConfigurationChange";
        
    }
    else {
        NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] endCall: is NULL");
    }
    
    return reason;
}

#pragma mark -
#pragma mark
// CallKit - Provider
#pragma mark -

- (void)providerDidReset:(CXProvider *)provider
{
    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] providerDidReset: - do nothing");
}

- (void)provider:(CXProvider *)provider performStartCallAction:(CXStartCallAction *)action
{
    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] performStartCallAction: action:'%@'", action);
    
    [self setupAudioSession];
    CXCallUpdate *callUpdate = [[CXCallUpdate alloc] init];
    callUpdate.remoteHandle = action.handle;
    callUpdate.hasVideo = action.video;
    callUpdate.localizedCallerName = action.contactIdentifier;
    callUpdate.supportsGrouping = NO;
    callUpdate.supportsUngrouping = NO;
    callUpdate.supportsHolding = NO;
    callUpdate.supportsDTMF = enableDTMF;
    
    [self.provider reportCallWithUUID:action.callUUID updated:callUpdate];
    [action fulfill];
    NSDictionary *data  = callsMetadata[[action.callUUID UUIDString]];
    if(data == nil) {
        return;
    }
    [self sendEvent:@"sendCall" payload:data];
}

- (void)provider:(CXProvider *)provider didActivateAudioSession:(AVAudioSession *)audioSession
{
    NSLog(@"activated audio");
    monitorAudioRouteChange = YES;
}

- (void)provider:(CXProvider *)provider didDeactivateAudioSession:(AVAudioSession *)audioSession
{
    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] didDeactivateAudioSession: deactivated audio");
}

#pragma mark -
#pragma mark performAnswerCallAction - USER PRESSES ANSWER on INCOMING CALL
#pragma mark -

- (void)provider:(CXProvider *)provider performAnswerCallAction:(CXAnswerCallAction *)action
{
    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] ANSWER CALL - performAnswerCallAction: action:'%@'", action);

    [self setupAudioSession];
    [action fulfill];
    NSDictionary *call = callsMetadata[[action.callUUID UUIDString]];
    if(call == nil) {
        NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] ANSWER CALL - performAnswerCallAction: call is NULL - skip");
        //can happen if debugging slowly can call times out
        return;
    }
    
    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] ANSWER CALL - performAnswerCallAction: send RESPONSE :'answer'");
    [self sendEvent:@"answer" payload:call];
    //will cause Cordova to respond by triggering answerCall:
}


//IF USERS PRESSES REJECT when INCOMING CALL Answer/Decline showed
//IF 2nd INCOMING call comes AND USER PRESSES "END and SELECT" in this is called to close the first by returning 'hangup'
//IF 2nd INCOMING call comes AND USER PRESSES "REJECT" in this is called - this returns 'reject'
- (void)provider:(CXProvider *)provider performEndCallAction:(CXEndCallAction *)action
{
    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] performEndCallAction: action:'%@'", action);
    
    //----------------------------------------------------------------------------------------------
   
    //----------------------------------------------------------------------------------------------
//    NSDictionary *call = callsMetadata[[action.callUUID UUIDString]];
//    if(NULL != call){
//        if([calls count] == 0){
//            NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] performEndCallAction: [calls count] == 0");
//        }
//        else if([calls count] == 1 && call != nil) {
//            if(calls[0].hasConnected) {
//                NSDictionary *payload = @{@"callId":call[@"callId"], @"callName": call[@"callName"]};
//                [self sendEvent:@"hangup" payload:payload];
//            } else {
//                [self sendEvent:@"reject" payload:call];
//            }
//            //--------------------------------------------------------------------------------------
//            NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] receiveCall: callsMetadata removeObjectForKey:UUID:%@", [action.callUUID UUIDString]);
//            [callsMetadata removeObjectForKey:[action.callUUID UUIDString]];
//            //--------------------------------------------------------------------------------------
//        }
//        else if([calls count] == 2 && call != nil) {
//            if(calls[0].hasConnected) {
//                NSDictionary *payload = @{@"callId":call[@"callId"], @"callName": call[@"callName"]};
//                [self sendEvent:@"hangup" payload:payload];
//            } else {
//                [self sendEvent:@"reject" payload:call];
//            }
//            [callsMetadata removeObjectForKey:[action.callUUID UUIDString]];
//        }
//        else{
//            NSLog(@"[VIDEOPLUGIN][CordovaCall.m] UNHNADLED CALL COUNT:%ld", [calls count]);
//        }
//
//
//
//    }else{
//        NSLog(@"call is NULL");
//    }
    
    //----------------------------------------------------------------------------------------------
    //v2 - support MULTIPLE INCOMING CALLs
    //----------------------------------------------------------------------------------------------
    //<CXEndCallAction 0x283dfa200
    //        UUID=2E5ABC7C-EC14-41B4-BAAB-E6A9C1FC712B
    //        state=0 commitDate=2021-03-03 20:06:34 +0000
    //        callUUID=CDE80182-F4A8-461C-BC8B-C5715D468E41 dateEnded=(null)>'
    
    NSDictionary *callToEndDict = callsMetadata[[action.callUUID UUIDString]];
    if(NULL != callToEndDict){
        
        NSString * callId = callToEndDict[@"callId"];
        
        if(NULL != callId){
            //--------------------------------------------------------------------------------------
            //find the CXCall for this callID
            //--------------------------------------------------------------------------------------
            CXCall* cxCallToEnd = [self findCall:callId];
            if(NULL != cxCallToEnd){
                if(cxCallToEnd.hasConnected) {
                    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] performEndCallAction: cxCallToEnd.hasConnected:TRUE return 'hangup'");
                    
                    NSDictionary *payload = @{@"callId"  : callToEndDict[@"callId"],
                                              @"callName": callToEndDict[@"callName"]};
                    [self sendEvent:@"hangup" payload:payload];
                } else {
                    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] performEndCallAction: cxCallToEnd.hasConnected:TRUE return 'reject'");
                    [self sendEvent:@"reject" payload:callToEndDict];
                }
            }else{
                NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] performEndCallAction: cxCallToEnd is NULL");
            }
        }else{
            NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] performEndCallAction: callId is NULL");
        }
    }else{
        NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] performEndCallAction: callToEndDict is NULL");
    }
    
    
    monitorAudioRouteChange = NO;
    [action fulfill];
}

- (void)provider:(CXProvider *)provider performSetMutedCallAction:(CXSetMutedCallAction *)action
{
    [action fulfill];
    BOOL isMuted = action.muted;
    [self sendEvent:isMuted?@"mute":@"unmute" payload:@{}];
}

- (void)provider:(CXProvider *)provider performPlayDTMFCallAction:(CXPlayDTMFCallAction *)action
{
    NSLog(@"DTMF Event");
    NSString *digits = action.digits;
    NSDictionary *payload = @{@"digits":digits};
    [action fulfill];
    [self sendEvent:@"DTMF" payload:payload];
}

- (void)sendEvent:(NSString*)eventName payload:(NSDictionary*)payload
{
    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] RESPONSE START *************************");
    if(eventCallbackId == nil) {
        NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] RESPONSE >> sendEvent: ERROR eventCallbackId == nil > return");
        return;
    }
    
    NSDictionary *event = @{@"eventName":eventName, @"data":payload};
    
    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] RESPONSE >> sendEvent:event:'%@'", event);
    NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] RESPONSE END  ***************************");
    
    CDVPluginResult* pluginResult = nil;
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:event];
    [pluginResult setKeepCallbackAsBool:YES];
    
    //NSLog(@"[VOIPCALLKITPLUGIN][CordovaCall.m] sendEvent: pluginResult:'%@'", pluginResult);
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:eventCallbackId];
}

// PushKit
- (void)initVoip:(CDVInvokedUrlCommand*)command
{
    if ([self isCallKitDisabledForChina]) {
        return;
    }

    self.VoIPPushCallbackId = command.callbackId;
    NSLog(@"[objC] callbackId: %@", self.VoIPPushCallbackId);
    //http://stackoverflow.com/questions/27245808/implement-pushkit-and-test-in-development-behavior/28562124#28562124
    PKPushRegistry *pushRegistry = [[PKPushRegistry alloc] initWithQueue:dispatch_get_main_queue()];
    pushRegistry.delegate = self;
    pushRegistry.desiredPushTypes = [NSSet setWithObject:PKPushTypeVoIP];
}

- (void)pushRegistry:(PKPushRegistry *)registry didUpdatePushCredentials:(PKPushCredentials *)credentials forType:(NSString *)type{
    if([credentials.token length] == 0) {
        NSLog(@"[objC] No device token!");
        return;
    }
    
    //http://stackoverflow.com/a/9372848/534755
    NSLog(@"[objC] Device token: %@", credentials.token);
    const unsigned *tokenBytes = [credentials.token bytes];
    NSString *sToken = [NSString stringWithFormat:@"%08x%08x%08x%08x%08x%08x%08x%08x",
                        ntohl(tokenBytes[0]), ntohl(tokenBytes[1]), ntohl(tokenBytes[2]),
                        ntohl(tokenBytes[3]), ntohl(tokenBytes[4]), ntohl(tokenBytes[5]),
                        ntohl(tokenBytes[6]), ntohl(tokenBytes[7])];
    
    NSMutableDictionary* results = [NSMutableDictionary dictionaryWithCapacity:2];
    [results setObject:sToken forKey:@"deviceToken"];
    [results setObject:@"true" forKey:@"registration"];
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:results];
    [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]]; //[pluginResult setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:self.VoIPPushCallbackId];
}

- (void)pushRegistry:(PKPushRegistry *)registry didReceiveIncomingPushWithPayload:(PKPushPayload *)payload forType:(NSString *)type
{
    NSDictionary *payloadDict = payload.dictionaryPayload[@"aps"];
    NSLog(@"[objC] didReceiveIncomingPushWithPayload: %@", payloadDict);
    
    NSString *message = payloadDict[@"alert"];
    NSLog(@"[objC] received VoIP message: %@", message);
    
    NSDictionary *data = payload.dictionaryPayload[@"data"];
    NSLog(@"[objC] received data: %@", data);
    
    NSMutableDictionary* results = [NSMutableDictionary dictionaryWithCapacity:2];
    [results setObject:message forKey:@"function"];
    [results setObject:data forKey:@"extra"];
    
    @try {
        NSDictionary *content = data[@"content"];
        NSArray* args = [NSArray arrayWithObjects:content,nil];
        CDVInvokedUrlCommand* newCommand = [[CDVInvokedUrlCommand alloc] initWithArguments:args callbackId:@"" className:self.VoIPPushClassName methodName:self.VoIPPushMethodName];
        [self receiveCall:newCommand];
    }
    @catch (NSException *exception) {
       NSLog(@"[objC] error: %@", exception.reason);
    }
    @finally {
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:results];
        [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.VoIPPushCallbackId];
    }
}

- (NSUUID*)getCallUUID:(NSString*)callId
{
    __block NSString* callUUIDString = nil;
    [callsMetadata enumerateKeysAndObjectsUsingBlock:^(NSString*  _Nonnull key, NSDictionary*  _Nonnull obj, BOOL * _Nonnull stop) {
        if([obj[@"callId"] isEqualToString:callId]) {
            callUUIDString = key;
            *stop = YES;
        }
    }];
    return callUUIDString != nil ? [[NSUUID alloc] initWithUUIDString:callUUIDString] : nil;
}

@end
