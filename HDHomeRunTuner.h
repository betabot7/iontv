//
//  HDHomeRunTuner.h
//  recsched
//
//  Created by Andrew Kimpton on 5/25/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "hdhomerun_os.h"
#import "hdhomerun_debug.h"       // Fixes warning from undefined type in device header
#import "hdhomerun_device.h"

@class HDHomeRun;
@class HDHomeRunChannel;
@class Z2ITLineup;

@interface HDHomeRunTuner : NSManagedObject {
  struct hdhomerun_device_t *mHDHomeRunDevice;
  id mCurrentProgressDisplay;
  HDHomeRunChannel *mCurrentHDHomeRunChannel;
}

- (NSNumber *) index;
- (void) setIndex:(NSNumber*)value;
- (HDHomeRun*) device;
- (void) setDevice:(HDHomeRun *)value;

- (Z2ITLineup*)lineup;
- (void) setLineup:(Z2ITLineup*)value;

- (void) addChannel:(HDHomeRunChannel*)inChannel;

- (NSString*) longName;

- (void) scanActionReportingProgressTo:(id)progressDisplay;

@end

@interface HDHomeRunChannel : NSManagedObject
{
  
}

+ createChannelWithType:(NSString*)inChannelType andNumber:(NSNumber*)inChannelNumber inManagedObjectContext:(NSManagedObjectContext*) inMOC;

- (NSString*) channelType;
- (void) setChannelType:(NSString*)value;

- (NSNumber*) channelNumber;
- (void) setChannelNumber:(NSNumber*)value;

- (NSString*) tuningType;
- (void) setTuningType:(NSString*)value;

- (HDHomeRunTuner*)tuner;
- (void)setTuner:(HDHomeRunTuner*)value;

- (NSMutableSet *)stations;

@end
