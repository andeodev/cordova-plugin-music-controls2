//
//  MusicControls.m
//
//
//  Created by Juan Gonzalez on 12/16/16.
//  Updated by Gaven Henry on 11/7/17 for iOS 11 compatibility & new features
//  Updated by Eugene Cross on 14/10/19 for iOS 13 compatibility
//
//

#import "MusicControls.h"
#import "MusicControlsInfo.h"

//save the passed in info globally so we can configure the enabled/disabled commands and skip intervals
MusicControlsInfo * musicControlsSettings;

@interface MusicControls ()
// iOS 16+: session-scoped Now Playing ownership; nil on iOS 15 (uses shared singletons).
@property (nonatomic, strong) MPNowPlayingSession *nowPlayingSession API_AVAILABLE(ios(16.0));
@end

@implementation MusicControls

// Lazily creates the MPNowPlayingSession. Must be called on the main thread.
- (void) ensureNowPlayingSession API_AVAILABLE(ios(16.0)) {
    if (self.nowPlayingSession == nil) {
        self.nowPlayingSession = [[MPNowPlayingSession alloc] initWithPlayers:@[]];
    }
}

- (void) create: (CDVInvokedUrlCommand *) command {
    NSDictionary * musicControlsInfoDict = [command.arguments objectAtIndex:0];
    MusicControlsInfo * musicControlsInfo = [[MusicControlsInfo alloc] initWithDictionary:musicControlsInfoDict];
    musicControlsSettings = musicControlsInfo;

    if (!NSClassFromString(@"MPNowPlayingInfoCenter")) {
        return;
    }

    // Session must be created on the main thread before the background block captures it.
    if (@available(iOS 16, *)) {
        [self ensureNowPlayingSession];
    }

    [self.commandDelegate runInBackground:^{
        MPNowPlayingInfoCenter *nowPlayingInfoCenter;
        if (@available(iOS 16, *)) {
            nowPlayingInfoCenter = self.nowPlayingSession.nowPlayingInfoCenter;
        } else {
            nowPlayingInfoCenter = [MPNowPlayingInfoCenter defaultCenter];
        }
        NSDictionary * nowPlayingInfo = nowPlayingInfoCenter.nowPlayingInfo;
        NSMutableDictionary * updatedNowPlayingInfo = [NSMutableDictionary dictionaryWithDictionary:nowPlayingInfo];

        MPMediaItemArtwork * mediaItemArtwork = [self createCoverArtwork:[musicControlsInfo cover]];
        NSNumber * duration = [NSNumber numberWithInt:[musicControlsInfo duration]];
        NSNumber * elapsed = [NSNumber numberWithInt:[musicControlsInfo elapsed]];
        NSNumber * playbackRate = [NSNumber numberWithBool:[musicControlsInfo isPlaying]];

        if (mediaItemArtwork != nil) {
            [updatedNowPlayingInfo setObject:mediaItemArtwork forKey:MPMediaItemPropertyArtwork];
        } else {
            [updatedNowPlayingInfo removeObjectForKey:MPMediaItemPropertyArtwork];
        }

        [updatedNowPlayingInfo setObject:[musicControlsInfo artist] forKey:MPMediaItemPropertyArtist];
        [updatedNowPlayingInfo setObject:[musicControlsInfo track] forKey:MPMediaItemPropertyTitle];
        [updatedNowPlayingInfo setObject:[musicControlsInfo album] forKey:MPMediaItemPropertyAlbumTitle];
        [updatedNowPlayingInfo setObject:duration forKey:MPMediaItemPropertyPlaybackDuration];
        [updatedNowPlayingInfo setObject:elapsed forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
        [updatedNowPlayingInfo setObject:playbackRate forKey:MPNowPlayingInfoPropertyPlaybackRate];

        nowPlayingInfoCenter.nowPlayingInfo = updatedNowPlayingInfo;
    }];

    // Deregister before re-registering to prevent duplicate MPRemoteCommandCenter handlers.
    // Without this, every create() call stacks another handler set on top of the previous
    // ones; after minutes of periodic calls those duplicates fire simultaneously on each
    // lock-screen / Bluetooth button press, crashing or corrupting playback state.
    [self deregisterMusicControlsEventListener];
    [self registerMusicControlsEventListener];
}

- (void) updateIsPlaying: (CDVInvokedUrlCommand *) command {
    NSDictionary * musicControlsInfoDict = [command.arguments objectAtIndex:0];
    MusicControlsInfo * musicControlsInfo = [[MusicControlsInfo alloc] initWithDictionary:musicControlsInfoDict];
    NSNumber * elapsed = [NSNumber numberWithDouble:[musicControlsInfo elapsed]];
    NSNumber * playbackRate = [NSNumber numberWithBool:[musicControlsInfo isPlaying]];

    if (!NSClassFromString(@"MPNowPlayingInfoCenter")) {
        return;
    }

    MPNowPlayingInfoCenter *nowPlayingCenter;
    if (@available(iOS 16, *)) {
        [self ensureNowPlayingSession];
        nowPlayingCenter = self.nowPlayingSession.nowPlayingInfoCenter;
    } else {
        nowPlayingCenter = [MPNowPlayingInfoCenter defaultCenter];
    }
    NSMutableDictionary * updatedNowPlayingInfo = [NSMutableDictionary dictionaryWithDictionary:nowPlayingCenter.nowPlayingInfo];

    [updatedNowPlayingInfo setObject:elapsed forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
    [updatedNowPlayingInfo setObject:playbackRate forKey:MPNowPlayingInfoPropertyPlaybackRate];
    nowPlayingCenter.nowPlayingInfo = updatedNowPlayingInfo;
}

// this was performing the full function of updateIsPlaying and just adding elapsed time update as well
// moved the elapsed update into updateIsPlaying and made this just pass through to reduce code duplication
- (void) updateElapsed: (CDVInvokedUrlCommand *) command {
    [self updateIsPlaying:(command)];
}

- (void) destroy: (CDVInvokedUrlCommand *) command {
    [[UIApplication sharedApplication] endReceivingRemoteControlEvents];
    [self deregisterMusicControlsEventListener];
    if (@available(iOS 16, *)) {
        self.nowPlayingSession = nil;
    }
    [self setLatestEventCallbackId:nil];
}

- (void) watch: (CDVInvokedUrlCommand *) command {
    [self setLatestEventCallbackId:command.callbackId];
}

- (MPMediaItemArtwork *) createCoverArtwork: (NSString *) coverUri {
    UIImage * coverImage = nil;

    if (coverUri == nil || [coverUri isKindOfClass:[NSNull class]]) {
        return nil;
    }

    if ([coverUri hasPrefix:@"http://"] || [coverUri hasPrefix:@"https://"]) {
        NSURL * coverImageUrl = [NSURL URLWithString:coverUri];
        NSData * coverImageData = [NSData dataWithContentsOfURL: coverImageUrl];

        coverImage = [UIImage imageWithData: coverImageData];
    }
    else if ([coverUri hasPrefix:@"file://"]) {
        NSString * fullCoverImagePath = [coverUri stringByReplacingOccurrencesOfString:@"file://" withString:@""];

        if ([[NSFileManager defaultManager] fileExistsAtPath: fullCoverImagePath]) {
            coverImage = [[UIImage alloc] initWithContentsOfFile: fullCoverImagePath];
        }
    }
    else if (![coverUri isEqual:@""]) {
        NSString * baseCoverImagePath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
        NSString * fullCoverImagePath = [NSString stringWithFormat:@"%@%@", baseCoverImagePath, coverUri];

        if ([[NSFileManager defaultManager] fileExistsAtPath:fullCoverImagePath]) {
            coverImage = [UIImage imageNamed:fullCoverImagePath];
        }
    }
    else {
        coverImage = [UIImage imageNamed:@"none"];
    }

    if (![self isCoverImageValid:coverImage]) return nil;
    return [[MPMediaItemArtwork alloc] initWithBoundsSize:coverImage.size requestHandler:^UIImage * _Nonnull(CGSize size) {
        return coverImage;
    }];
}

- (bool) isCoverImageValid: (UIImage *) coverImage {
    return coverImage != nil && ([coverImage CIImage] != nil || [coverImage CGImage] != nil);
}

//Handle seeking with the progress slider on lockscreen or control center
- (MPRemoteCommandHandlerStatus)changedThumbSliderOnLockScreen:(MPChangePlaybackPositionCommandEvent *)event {
    NSString * seekTo = [NSString stringWithFormat:@"{\"message\":\"music-controls-seek-to\",\"position\":\"%f\"}", event.positionTime];
    CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:seekTo];
    pluginResult.associatedObject = @{@"position":[NSNumber numberWithDouble: event.positionTime]};
    [pluginResult setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:[self latestEventCallbackId]];
    return MPRemoteCommandHandlerStatusSuccess;
}

//Handle the skip forward event
- (MPRemoteCommandHandlerStatus) skipForwardEvent:(MPSkipIntervalCommandEvent *)event {
    NSString * action = @"music-controls-skip-forward";
    NSString * jsonAction = [NSString stringWithFormat:@"{\"message\":\"%@\"}", action];
    CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:jsonAction];
    [pluginResult setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:[self latestEventCallbackId]];
    return MPRemoteCommandHandlerStatusSuccess;
}

//Handle the skip backward event
- (MPRemoteCommandHandlerStatus) skipBackwardEvent:(MPSkipIntervalCommandEvent *)event {
    NSString * action = @"music-controls-skip-backward";
    NSString * jsonAction = [NSString stringWithFormat:@"{\"message\":\"%@\"}", action];
    CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:jsonAction];
    [pluginResult setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:[self latestEventCallbackId]];
    return MPRemoteCommandHandlerStatusSuccess;
}

//If MPRemoteCommandCenter is enabled for any function we must enable it for all and register a handler
//So if we want to use the new scrubbing support in the lock screen we must implement dummy handlers
//for those functions that we already deal with through notifications (play, pause, skip etc)
//otherwise those remote control actions will be disabled
- (MPRemoteCommandHandlerStatus) remoteEvent:(MPRemoteCommandEvent *)event {
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus) nextTrackEvent:(MPRemoteCommandEvent *)event {
    NSString * action = @"music-controls-next";
    NSString * jsonAction = [NSString stringWithFormat:@"{\"message\":\"%@\"}", action];
    CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:jsonAction];
    [pluginResult setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:[self latestEventCallbackId]];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus) prevTrackEvent:(MPRemoteCommandEvent *)event {
    NSString * action = @"music-controls-previous";
    NSString * jsonAction = [NSString stringWithFormat:@"{\"message\":\"%@\"}", action];
    CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:jsonAction];
    [pluginResult setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:[self latestEventCallbackId]];
    return MPRemoteCommandHandlerStatusSuccess;

}

- (MPRemoteCommandHandlerStatus) pauseEvent:(MPRemoteCommandEvent *)event {
    NSString * action = @"music-controls-pause";
    NSString * jsonAction = [NSString stringWithFormat:@"{\"message\":\"%@\"}", action];
    CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:jsonAction];
    [pluginResult setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:[self latestEventCallbackId]];
    return MPRemoteCommandHandlerStatusSuccess;

}

- (MPRemoteCommandHandlerStatus) playEvent:(MPRemoteCommandEvent *)event {
    NSString * action = @"music-controls-play";
    NSString * jsonAction = [NSString stringWithFormat:@"{\"message\":\"%@\"}", action];
    CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:jsonAction];
    [pluginResult setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:[self latestEventCallbackId]];
    return MPRemoteCommandHandlerStatusSuccess;

}

- (MPRemoteCommandHandlerStatus) togglePlayPauseEvent:(MPRemoteCommandEvent *)event {
    NSString * action = @"music-controls-toggle-play-pause";
    NSString * jsonAction = [NSString stringWithFormat:@"{\"message\":\"%@\"}", action];
    CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:jsonAction];
    [pluginResult setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:[self latestEventCallbackId]];
    return MPRemoteCommandHandlerStatusSuccess;
}

//Handle all other remote control events
- (void) handleMusicControlsNotification: (NSNotification *) notification {
    UIEvent * receivedEvent = notification.object;

    if ([self latestEventCallbackId] == nil) {
        return;
    }

    if (receivedEvent.type == UIEventTypeRemoteControl) {
        NSString * action;

        switch (receivedEvent.subtype) {
            case UIEventSubtypeRemoteControlTogglePlayPause:
                action = @"music-controls-toggle-play-pause";
                break;

            case UIEventSubtypeRemoteControlPlay:
                action = @"music-controls-play";
                break;

            case UIEventSubtypeRemoteControlPause:
                action = @"music-controls-pause";
                break;

            case UIEventSubtypeRemoteControlPreviousTrack:
                action = @"music-controls-previous";
                break;

            case UIEventSubtypeRemoteControlNextTrack:
                action = @"music-controls-next";
                break;

            case UIEventSubtypeRemoteControlStop:
                action = @"music-controls-destroy";
                break;

            default:
                action = nil;
                break;
        }

        if(action == nil){
            return;
        }

        NSString * jsonAction = [NSString stringWithFormat:@"{\"message\":\"%@\"}", action];
        CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:jsonAction];
        [pluginResult setKeepCallbackAsBool:YES];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:[self latestEventCallbackId]];
    }
}

- (void) viewDidAppear:(BOOL)animated
{
    if ([[UIApplication sharedApplication] respondsToSelector:@selector(beginReceivingRemoteControlEvents)]){
        [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
        [self becomeFirstResponder];
    }
}

- (void) viewWillDisappear:(BOOL)animated
{
    [[UIApplication sharedApplication] endReceivingRemoteControlEvents];
    [self resignFirstResponder];
}

//There are only 3 button slots available so next/prev track and skip forward/back cannot both be enabled
//skip forward/back will take precedence if both are enabled
- (void) registerMusicControlsEventListener {
    // MPRemoteCommandCenter is the sole event pathway on modern iOS (13+).
    // beginReceivingRemoteControlEvents is managed by viewDidAppear/viewWillDisappear
    // and destroy — calling it here caused the end/begin cycle on every create() call
    // to redeliver a buffered UIEvent mid-navigation, producing a double-skip.

    MPRemoteCommandCenter *commandCenter;
    if (@available(iOS 16, *)) {
        // Session is guaranteed non-nil here: create: calls ensureNowPlayingSession before
        // calling deregister/register, and dealloc returns early if session is nil.
        commandCenter = self.nowPlayingSession.remoteCommandCenter;
    } else {
        commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
    }

    //register required event handlers for standard controls
    [commandCenter.playCommand setEnabled:true];
    [commandCenter.playCommand addTarget:self action:@selector(playEvent:)];
    [commandCenter.pauseCommand setEnabled:true];
    [commandCenter.pauseCommand addTarget:self action:@selector(pauseEvent:)];
    [commandCenter.togglePlayPauseCommand setEnabled:true];
    [commandCenter.togglePlayPauseCommand addTarget:self action:@selector(togglePlayPauseEvent:)];
    if(musicControlsSettings.hasNext){
        [commandCenter.nextTrackCommand setEnabled:true];
        [commandCenter.nextTrackCommand addTarget:self action:@selector(nextTrackEvent:)];
    }
    if(musicControlsSettings.hasPrev){
        [commandCenter.previousTrackCommand setEnabled:true];
        [commandCenter.previousTrackCommand addTarget:self action:@selector(prevTrackEvent:)];
    }

    //Some functions are not available in earlier versions
    if(floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_9_0){
        if(musicControlsSettings.hasSkipForward){
            commandCenter.skipForwardCommand.preferredIntervals = @[@(musicControlsSettings.skipForwardInterval)];
            [commandCenter.skipForwardCommand setEnabled:true];
            [commandCenter.skipForwardCommand addTarget: self action:@selector(skipForwardEvent:)];
        } else {
            if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_9_0) {
                [commandCenter.skipForwardCommand removeTarget:self];
            }
        }
        if(musicControlsSettings.hasSkipBackward){
            commandCenter.skipBackwardCommand.preferredIntervals = @[@(musicControlsSettings.skipBackwardInterval)];
            [commandCenter.skipBackwardCommand setEnabled:true];
            [commandCenter.skipBackwardCommand addTarget: self action:@selector(skipBackwardEvent:)];
        } else {
            if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_9_0) {
                [commandCenter.skipBackwardCommand removeTarget:self];
            }
        }
        if(musicControlsSettings.hasScrubbing){
            [commandCenter.changePlaybackPositionCommand setEnabled:true];
            [commandCenter.changePlaybackPositionCommand addTarget:self action:@selector(changedThumbSliderOnLockScreen:)];
        } else {
            if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_9_0) {
                [commandCenter.changePlaybackPositionCommand setEnabled:false];
                [commandCenter.changePlaybackPositionCommand removeTarget:self action:NULL];
            }
        }
    }
}

- (void) deregisterMusicControlsEventListener {
    MPRemoteCommandCenter *commandCenter;
    if (@available(iOS 16, *)) {
        // Session is nil before the first create() call or after destroy() — nothing to deregister.
        if (self.nowPlayingSession == nil) return;
        commandCenter = self.nowPlayingSession.remoteCommandCenter;
    } else {
        commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
    }

    [commandCenter.playCommand removeTarget:self];
    [commandCenter.pauseCommand removeTarget:self];
    [commandCenter.togglePlayPauseCommand removeTarget:self];
    [commandCenter.nextTrackCommand removeTarget:self];
    [commandCenter.previousTrackCommand removeTarget:self];

    if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_9_0) {
        [commandCenter.changePlaybackPositionCommand setEnabled:false];
        [commandCenter.changePlaybackPositionCommand removeTarget:self action:NULL];
        [commandCenter.skipForwardCommand removeTarget:self];
        [commandCenter.skipBackwardCommand removeTarget:self];
    }
}

- (void) dealloc {
    [self deregisterMusicControlsEventListener];
}

@end
