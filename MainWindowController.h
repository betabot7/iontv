//
//  MainWindowController.h
//  recsched
//
//  Created by Andrew Kimpton on 1/12/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "XMLParsingProgressDisplayProtocol.h"

@class Z2ITSchedule;
@class ScheduleView;
@class RBSplitView;

@interface MainWindowController : NSWindowController <XMLParsingProgressDisplay> {
  IBOutlet NSButton *mGetScheduleButton;
  IBOutlet NSProgressIndicator *mParsingProgressIndicator;
  IBOutlet NSTextField *mParsingProgressInfoField;
  IBOutlet RBSplitView *mScheduleSplitView;
  IBOutlet RBSplitView *mTopLevelSplitView;
  IBOutlet NSTableView *mViewSelectionTableView;
  IBOutlet NSView *mDetailView;
  IBOutlet NSView *mScheduleContainerView;
  IBOutlet NSView *mProgramSearchView;
  IBOutlet ScheduleView *mScheduleView;
  IBOutlet NSObjectController *mCurrentSchedule;
  IBOutlet NSArrayController *mViewSelectionArrayController;
  
  // Cells used by the Source View selector 'table'
  NSCell *mSeparatorCell;
  NSCell *mDefaultCell;

  float mDetailViewMinHeight;
  id mRecServer;
}

- (IBAction) getScheduleAction:(id)sender;
- (IBAction) cleanupAction:(id)sender;
- (IBAction) recordShow:(id)sender;
- (IBAction) recordSeasonPass:(id)sender;
- (IBAction) quitServer:(id)sender;

- (void) showViewForTableSelection:(int) selectedRow;

- (void) setCurrentSchedule:(Z2ITSchedule*)inSchedule;
- (Z2ITSchedule*) currentSchedule;
@end
