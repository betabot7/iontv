//  recsched_bkgd - Background server application retrieves schedule data, performs recordings,
//  transcodes recordings in to H.264 format for iTunes, iPod etc.
//  
//  Copyright (C) 2007 Andrew Kimpton
//  
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//  
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
//  GNU General Public License for more details.
//  
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA

#import <Cocoa/Cocoa.h>
#import <ScriptingBridge/ScriptingBridge.h>

#include "hb.h"

extern NSString *RSNotificationTranscodingFinished;

@class RSTranscoding;

@interface RSTranscodeController : NSObject <SBApplicationDelegate> {
    hb_handle_t	   *mHandbrakeHandle;		// Connection to the Handbrake libraries
	
	NSArrayController *mRecordingsArrayController;
	NSArrayController *mTranscodingsArrayController;
	
	RSTranscoding *mCurrentTranscoding;
}

- (void) updateForCompletedRecordings:(NSArray*)inArray;

@end
