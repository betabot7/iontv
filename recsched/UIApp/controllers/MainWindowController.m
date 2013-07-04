//  Copyright (c) 2007, Andrew Kimpton
//  
//  All rights reserved.
//  
//  Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following
//  conditions are met:
//  
//  Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
//  Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer
//  in the documentation and/or other materials provided with the distribution.
//  The names of its contributors may not be used to endorse or promote products derived from this software without specific prior
//  written permission.
//  
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
//  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
//  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
//  A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
//  CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
//  EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
//  PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
//  PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
//  LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
//  NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
//  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#import "HDHomeRunChannelStationMap.h"
#import "MainWindowController.h"
#import "ScheduleView.h"
#import "Preferences.h"
#import "RSError.h"
#import "RSRecording.h"
#import "RSNotifications.h"
#import "RSScheduleConflictController.h"
#import "RSSeasonPass.h"
#import "RSSeasonPassCalendarViewController.h"
#import "Z2ITSchedule.h"
#import "Z2ITProgram.h"
#import "Z2ITStation.h"
#import "recsched_AppDelegate.h"
#import "HDHomeRunTuner.h"
#import "RecSchedProtocol.h"
#import "ScheduleViewController.h"
#import "ProgramSearchViewController.h"
#import "NSStringAdditions.h"
#import "NSManagedObjectContextAdditions.h"
#import "recsched_AppDelegate.h"

@interface MainWindowController(Private)
- (BOOL) addRecordingOfSchedule:(Z2ITSchedule*)schedule error:(NSError**) error;
- (BOOL) addSeasonPassForProgram:(Z2ITProgram*)schedule onStation:(Z2ITStation*)station;
- (void) showScheduleConflict:(NSError*)error;
@end

@implementation MainWindowController

const CGFloat kSourceListMaxWidth = 250;
const CGFloat kSourceListMinWidth = 150;

NSString *RSSSchedulePBoardType = @"RSSchedulePasteboardType";
NSString *RSSourceListPBoardType = @"RSSourceListPasteboardType";

NSString *RSSourceListNodeProgramsType = @"PROGRAMS";
NSString *RSSourceListNodeFutureRecordingsType = @"FUTURE RECORDINGS";
NSString *RSSourceListNodePastRecordingsType = @"PAST RECORDINGS";
NSString *RSSourceListNodeSeasonPassesType = @"SEASON PASSES";

NSString *RSSourceListExpandableKey = @"expandable";
NSString *RSSourceListHeadingKey = @"heading";
NSString *RSSourceListLabelKey = @"label";
NSString *RSSourceListChildrenKey = @"children";
NSString *RSSourceListTypeKey = @"type";
NSString *RSSourceListPriorityKey = @"priority";
NSString *RSSourceListActionMessageNameKey = @"actionMessageName";
NSString *RSSourceListCanAcceptDropKey = @"canAcceptDrop";
NSString *RSSourceListObjectIDKey = @"objectID";
NSString *RSSourceListDeletableKey = @"deletable";
NSString *RSSourceListDeleteMessageNameKey = @"deleteMessageName";

#pragma mark Source List Management

- (void) updateSourceListForRecordings
{
  NSArray *treeNodes = [mViewSelectionTreeController content];
  NSMutableDictionary *aSourceListNode = nil;

  for (aSourceListNode in treeNodes)
  {
    if ([aSourceListNode valueForKey:RSSourceListTypeKey] == RSSourceListNodeFutureRecordingsType)
    {
      NSArray *schedulesToBeRecorded = [NSArray arrayWithArray:[RSRecording fetchRecordingsInManagedObjectContext:[[NSApp delegate]managedObjectContext] afterDate:[NSDate date] withStatus:RSRecordingNotYetStartedStatus]];
      NSMutableArray *sourceListNodes = [NSMutableArray arrayWithCapacity:[schedulesToBeRecorded count]];
      [schedulesToBeRecorded makeObjectsPerformSelector:@selector(buildSourceListNodeAndAddTo:) withObject:sourceListNodes];
      [aSourceListNode setValue:sourceListNodes forKey:RSSourceListChildrenKey];
    }
    else if ([aSourceListNode valueForKey:RSSourceListTypeKey] == RSSourceListNodePastRecordingsType)
    {
      NSMutableArray *pastRecordings = [NSMutableArray arrayWithArray:[RSRecording fetchRecordingsInManagedObjectContext:[[NSApp delegate]managedObjectContext] beforeDate:[NSDate date]]];
      NSMutableArray *sourceListNodes = [NSMutableArray arrayWithCapacity:[pastRecordings count]];
      [pastRecordings makeObjectsPerformSelector:@selector(buildSourceListNodeAndAddTo:) withObject:sourceListNodes];
      [aSourceListNode setValue:sourceListNodes forKey:RSSourceListChildrenKey];
    }
  }
}

- (void) updateSourceListForSeasonPasses
{
	NSArray *treeNodes = [mViewSelectionTreeController content];
	NSMutableDictionary *aSourceListNode = nil;
	for (aSourceListNode in treeNodes)
	{
		if ([aSourceListNode valueForKey:RSSourceListTypeKey] == RSSourceListNodeSeasonPassesType)
		{
      NSArray *seasonPasses = [mSeasonPassArrayController arrangedObjects];
      NSMutableArray *sourceListNodes = [NSMutableArray arrayWithCapacity:[seasonPasses count]];
      [seasonPasses makeObjectsPerformSelector:@selector(buildSourceListNodeAndAddTo:) withObject:sourceListNodes];
      [aSourceListNode setValue:sourceListNodes forKey:RSSourceListChildrenKey];
    }
	}
}

- (void) addSourceListNodes
{
	NSMutableArray *treeNodes = [[NSMutableArray alloc] initWithCapacity:3];
	
	NSMutableDictionary *aSourceListNode = [[NSMutableDictionary alloc] init];
	[aSourceListNode setValue:@"PROGRAMS" forKey:RSSourceListLabelKey];
	[aSourceListNode setValue:[NSNumber numberWithBool:NO] forKey:RSSourceListExpandableKey];
	[aSourceListNode setValue:[NSNumber numberWithBool:YES] forKey:RSSourceListHeadingKey];
	[aSourceListNode setValue:[NSNumber numberWithInt:1] forKey:RSSourceListPriorityKey];
	[aSourceListNode setValue:[[[NSMutableSet alloc] initWithCapacity:2] autorelease] forKey:RSSourceListChildrenKey];
	[aSourceListNode setValue:RSSourceListNodeProgramsType forKey:RSSourceListTypeKey];
	[treeNodes addObject:aSourceListNode];
	
	NSMutableDictionary *aChildSourceListNode = [[NSMutableDictionary alloc] init];
	[aChildSourceListNode setValue:@"Schedule" forKey:RSSourceListLabelKey];
//	[aChildSourceListNode setValue:aSourceListNode forKey:@"parent"];
	[aChildSourceListNode setValue:@"showSchedule:" forKey:RSSourceListActionMessageNameKey];
	[aChildSourceListNode setValue:[NSNumber numberWithInt:1] forKey:RSSourceListPriorityKey];
	[[aSourceListNode valueForKey:RSSourceListChildrenKey] addObject:aChildSourceListNode];
	[aChildSourceListNode release];
	
	aChildSourceListNode = [[NSMutableDictionary alloc] init];
	[aChildSourceListNode setValue:@"Search" forKey:RSSourceListLabelKey];
//	[aChildSourceListNode setValue:aSourceListNode forKey:@"parent"];
	[aChildSourceListNode setValue:@"showSearch:" forKey:RSSourceListActionMessageNameKey];
	[aChildSourceListNode setValue:[NSNumber numberWithInt:2] forKey:RSSourceListPriorityKey];
	[[aSourceListNode valueForKey:RSSourceListChildrenKey] addObject:aChildSourceListNode];
	[aChildSourceListNode release];
	[aSourceListNode release];
	
	aSourceListNode = [[NSMutableDictionary alloc] init];
	[aSourceListNode setValue:@"FUTURE RECORDINGS" forKey:RSSourceListLabelKey];
	[aSourceListNode setValue:[NSNumber numberWithBool:YES] forKey:RSSourceListExpandableKey];
	[aSourceListNode setValue:[NSNumber numberWithBool:YES] forKey:RSSourceListHeadingKey];
	[aSourceListNode setValue:[NSNumber numberWithInt:2] forKey:RSSourceListPriorityKey];
	[aSourceListNode setValue:[NSNumber numberWithBool:YES] forKey:RSSourceListCanAcceptDropKey];
	[aSourceListNode setValue:RSSourceListNodeFutureRecordingsType forKey:RSSourceListTypeKey];
	[treeNodes addObject:aSourceListNode];
	[aSourceListNode release];
	
	aSourceListNode = [[NSMutableDictionary alloc] init];
	[aSourceListNode setValue:@"PAST RECORDINGS" forKey:RSSourceListLabelKey];
	[aSourceListNode setValue:[NSNumber numberWithBool:YES] forKey:RSSourceListExpandableKey];
	[aSourceListNode setValue:[NSNumber numberWithBool:YES] forKey:RSSourceListHeadingKey];
	[aSourceListNode setValue:[NSNumber numberWithInt:3] forKey:RSSourceListPriorityKey];
	[aSourceListNode setValue:[NSNumber numberWithBool:NO] forKey:RSSourceListCanAcceptDropKey];
	[aSourceListNode setValue:RSSourceListNodePastRecordingsType forKey:RSSourceListTypeKey];
	[treeNodes addObject:aSourceListNode];
	[aSourceListNode release];

	aSourceListNode = [[NSMutableDictionary alloc] init];
	[aSourceListNode setValue:@"SEASON PASSES" forKey:RSSourceListLabelKey];
	[aSourceListNode setValue:[NSNumber numberWithBool:YES] forKey:RSSourceListExpandableKey];
	[aSourceListNode setValue:[NSNumber numberWithBool:YES] forKey:RSSourceListHeadingKey];
	[aSourceListNode setValue:[NSNumber numberWithInt:4] forKey:RSSourceListPriorityKey];
	[aSourceListNode setValue:[NSNumber numberWithBool:YES] forKey:RSSourceListCanAcceptDropKey];
	[aSourceListNode setValue:RSSourceListNodeSeasonPassesType forKey:RSSourceListTypeKey];
	[treeNodes addObject:aSourceListNode];
	[aSourceListNode release];
	
	[mViewSelectionTreeController setContent:treeNodes];
	[treeNodes release];
}

- (void) futureRecordingSelected:(id)anArgument
{
	NSManagedObjectID *anObjectID = [anArgument valueForKey:RSSourceListObjectIDKey];
	RSRecording *aRecording = (RSRecording*) [[[NSApp delegate] managedObjectContext] objectWithID:anObjectID];
	if (aRecording)
		[self setCurrentSchedule:aRecording.schedule];
}

- (void) seasonPassSelected:(id)anArgument
{
  NSManagedObjectID *anObjectID = [anArgument valueForKey:RSSourceListObjectIDKey];
  RSSeasonPass *aSeasonPass = (RSSeasonPass*) [[[NSApp delegate] managedObjectContext] objectWithID:anObjectID];
  if (aSeasonPass)
  {
    [mScheduleContainerView setHidden:YES];
    mProgramSearchViewController.searchViewHidden = YES;
    mSeasonPassCalendarViewController.seasonPassCalendarViewHidden = NO;
  }
}

- (void) deleteFutureRecording:(id)anArgument
{
	NSManagedObjectID *anObjectID = [anArgument valueForKey:RSSourceListObjectIDKey];
	RSRecording *aRecording = (RSRecording*) [[[NSApp delegate] managedObjectContext] objectWithID:anObjectID];
	
	NSError *error = nil;
	[[[NSApp delegate] recServer] cancelRecordingWithObjectID:[aRecording objectID] error:&error];
}

- (void) deleteSeasonPass:(id)anArgument
{
	NSManagedObjectID *anObjectID = [anArgument valueForKey:RSSourceListObjectIDKey];
	RSSeasonPass *aSeasonPass = (RSSeasonPass*) [[[NSApp delegate] managedObjectContext] objectWithID:anObjectID];
	
	NSError *error = nil;
	[[[NSApp delegate] recServer] deleteSeasonPassWithObjectID:[aSeasonPass objectID] error:&error];
}

#pragma mark Initialization/Startup

- (void) awakeFromNib
{
  // Don't cause resizing when items are expanded
  [mViewSelectionOutlineView setAutoresizesOutlineColumn:NO];
  [self addSourceListNodes];
  
  // Sort based on the 'priority' of the node
  NSSortDescriptor *aSortDescriptor = [[[NSSortDescriptor alloc] initWithKey:RSSourceListPriorityKey ascending:YES] autorelease];
  [mViewSelectionTreeController setSortDescriptors:[NSArray arrayWithObject:aSortDescriptor]];
  
  // Start with the very first (Programs) item expanded
  [mViewSelectionOutlineView reloadItem:nil reloadChildren:YES];
  [mViewSelectionOutlineView expandItem:nil expandChildren:NO];
  
  [mViewSelectionTreeController addObserver:self forKeyPath:@"selection" options:0 context:nil];		// Watch for changes to view selection
  NSIndexPath *anIndexPath = [NSIndexPath indexPathWithIndex:0];
  anIndexPath = [anIndexPath indexPathByAddingIndex:0];
  [mViewSelectionTreeController setSelectionIndexPath:anIndexPath];
  
  // Vertical mouse motion can begin a drag.
  [mViewSelectionOutlineView setVerticalMotionCanBeginDrag:YES];
  
  // Register for drag-n-drop on the outline view
  [mViewSelectionOutlineView registerForDraggedTypes:[NSArray arrayWithObject:RSSSchedulePBoardType]];

	// Observe the arranged list of future recordings and season passes- changes to this mean that there are new recordings
	// or some have been removed and we should update the UI.
	[mRecordingsArrayController addObserver:self forKeyPath:@"arrangedObjects" options:0 context:nil];
	[mSeasonPassArrayController addObserver:self forKeyPath:@"arrangedObjects" options:0 context:nil];

  mDetailViewMinHeight = [mDetailView frame].size.height;
  NSView *bottomContainerView = [[mScheduleSplitView subviews] objectAtIndex:1];
  [bottomContainerView addSubview:mScheduleContainerView];
  [bottomContainerView addSubview:[mProgramSearchViewController view]];
  [bottomContainerView addSubview:[mSeasonPassCalendarViewController view]];
  
  NSSize scheduleSize = [bottomContainerView frame].size;
  NSRect newFrame = [mScheduleContainerView frame];
  newFrame.size = scheduleSize;
  [mScheduleContainerView setFrame:newFrame];
  [mScheduleContainerView setHidden:NO];
  newFrame = [[mProgramSearchViewController view] frame];
  newFrame.size = scheduleSize;
  [[mProgramSearchViewController view] setFrame:newFrame];
  mProgramSearchViewController.searchViewHidden=YES;
  [[mSeasonPassCalendarViewController view] setFrame:newFrame];
  mSeasonPassCalendarViewController.seasonPassCalendarViewHidden = YES;
  
  [mTopLevelSplitView setDividerStyle:NSSplitViewDividerStyleThin];
  [mTopLevelSplitView setPosition:kSourceListMinWidth + ((kSourceListMaxWidth - kSourceListMinWidth) / 2) ofDividerAtIndex:0];
  
  [[[mScheduleSplitView subviews] objectAtIndex:0] addSubview:mDetailView];
  newFrame = [mDetailView frame];
  newFrame.size = [[[mScheduleSplitView subviews] objectAtIndex:0] frame].size;
  [mDetailView setFrame:newFrame];

  [mScheduleSplitView setDividerStyle:NSSplitViewDividerStyleThin];
  [mScheduleSplitView setPosition:mDetailViewMinHeight ofDividerAtIndex:0];

  [mScheduleSplitView adjustSubviews];
  [mTopLevelSplitView adjustSubviews];
  
  [mCurrentSchedule setContent:nil];

  // Watch for the RSScheduleUpdateCompleteNotification to reset our object controllers
  [[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(scheduleUpdateCompleteNotification:) name:RSScheduleUpdateCompleteNotification object:RSBackgroundApplication];
  
	// Watch for RSRecordingAdded and RSRecordingRemoved notification to update the recordings array controller
	[[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(recordingAddedNotification:) name:RSRecordingAddedNotification object:RSBackgroundApplication];
	[[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(recordingRemovedNotification:) name:RSRecordingRemovedNotification object:RSBackgroundApplication];
  
	// Watch for RSSeasonPassAdded and RSSeasonPassRemoved notification to update the season pass array controller
	[[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(seasonPassAddedNotification:) name:RSSeasonPassAddedNotification object:RSBackgroundApplication];
	[[NSDistributedNotificationCenter defaultCenter] addObserver:self selector:@selector(seasonPassRemovedNotification:) name:RSSeasonPassRemovedNotification object:RSBackgroundApplication];
  
  // Restore our previous lineup choice
  NSString *lineupObjectURIString = [[NSUserDefaults standardUserDefaults] stringForKey:kCurrentLineupURIKey];
  NSURL *lineupObjectURI = nil;
  if (lineupObjectURIString)
  {
	lineupObjectURI = [NSURL URLWithString:lineupObjectURIString];
	NSManagedObjectID *lineupObjectID = [[[NSApp delegate] persistentStoreCoordinator] managedObjectIDForURIRepresentation:lineupObjectURI];
	Z2ITLineup *aLineup = nil;
        if (lineupObjectID)
          aLineup = (Z2ITLineup*) [[[NSApp delegate] managedObjectContext] objectWithID:lineupObjectID];
        if (aLineup)
          [mCurrentLineup setContent:aLineup];
  }

  if ([mCurrentLineup content] == nil)    // No lineup prefs choice - just go with the first item we can find
  {
	NSError *error = nil;
	[mLineupsArrayController fetchWithRequest:[mLineupsArrayController defaultFetchRequest] merge:NO error:&error];
	if ((error == nil) && ([[mLineupsArrayController arrangedObjects] count] > 0))
		[mCurrentLineup setContent:[[mLineupsArrayController arrangedObjects] objectAtIndex:0]];
  }
  
  // Restore our previous schedule choice
  NSString *scheduleObjectURIString = [[NSUserDefaults standardUserDefaults] stringForKey:kCurrentScheduleURIKey];
  NSURL *scheduleObjectURI = nil;
  if (scheduleObjectURIString)
  {
	scheduleObjectURI = [NSURL URLWithString:scheduleObjectURIString];
	NSManagedObjectID *scheduleObjectID = [[[NSApp delegate] persistentStoreCoordinator] managedObjectIDForURIRepresentation:scheduleObjectURI];
	Z2ITSchedule *aSchedule = nil;
	if (scheduleObjectID)
	  aSchedule = (Z2ITSchedule*) [[[NSApp delegate] managedObjectContext] objectWithID:scheduleObjectID];
	if (aSchedule)
	{
		// Use a try/catch block here - the old objectURI/ObjectID may have become invalid if it points to an object that has been
		// deleted on cleanup.
		@try {
		  // Use the prior schedule choice to pick the channel to select from this time, we'll actually select whatever program is
		  // currently being shown on that channel 'now'
		  NSEntityDescription *entityDescription = [NSEntityDescription entityForName:@"Schedule" inManagedObjectContext:[[NSApp delegate] managedObjectContext]];
		  NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
		  [request setEntity:entityDescription];
		   
		  NSDate *nowDate = [NSDate date];
		  NSPredicate *predicate = [NSPredicate predicateWithFormat:@"station == %@ AND time <= %@ AND endTime > %@", aSchedule.station, nowDate, nowDate];
		  [request setPredicate:predicate];
		   
		  NSError *error = nil;
		  NSArray *array = [[[NSApp delegate] managedObjectContext] executeFetchRequest:request error:&error];
		  if (array && ([array count] > 0))
				[mCurrentSchedule setContent:[array objectAtIndex:0]];
		}
		@catch (NSException * e) {
			// No need to log anything
		}
	}
  }
	// If we don't have a current schedule selected - just pick one for 'now' on the lowest numbered channel
	if ([mCurrentSchedule content] == nil)
	{
	  NSError *error = nil;

	  // Fetch the lineup maps
	  NSEntityDescription *lineupEntityDescription = [NSEntityDescription entityForName:@"LineupMap" inManagedObjectContext:[[NSApp delegate] managedObjectContext]];
	  NSFetchRequest *lineupRequest = [[[NSFetchRequest alloc] init] autorelease];
	  [lineupRequest setEntity:lineupEntityDescription];
	  NSArray *lineupArray = [[[NSApp delegate] managedObjectContext] executeFetchRequest:lineupRequest error:&error];

		// We have to sort them seperately from the fetch because CoreData doesn't support using 'custom' selectors in a sort desriptor executed during a fetch.
	  NSSortDescriptor *channelSortDescriptor = [[[NSSortDescriptor alloc] initWithKey:@"channel" ascending:YES selector:@selector(numericCompare:)] autorelease];
	  NSSortDescriptor *channelMinorSortDescriptor = [[[NSSortDescriptor alloc] initWithKey:@"channelMinor" ascending:YES] autorelease];
	  NSArray *sortedLineupArray = [lineupArray sortedArrayUsingDescriptors:[NSArray arrayWithObjects:channelSortDescriptor, channelMinorSortDescriptor, nil]];
		
	  // Now fetch a schedule with matching lineup map
	  NSEntityDescription *entityDescription = [NSEntityDescription entityForName:@"Schedule" inManagedObjectContext:[[NSApp delegate] managedObjectContext]];
	  NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
	  [request setEntity:entityDescription];
	   
	  NSDate *nowDate = [NSDate date];
	  NSPredicate *predicate;
		if (sortedLineupArray && ([sortedLineupArray count] > 0))
			predicate = [NSPredicate predicateWithFormat:@"%@ IN station.lineupMaps AND time <= %@ AND endTime > %@", [sortedLineupArray objectAtIndex:0], nowDate, nowDate];
		else
			predicate = [NSPredicate predicateWithFormat:@"time <= %@ AND endTime > %@", nowDate, nowDate];
	  [request setPredicate:predicate];
	   
	  NSArray *array = [[[NSApp delegate] managedObjectContext] executeFetchRequest:request error:&error];
	  if (array && ([array count] > 0))
	  {
			[mCurrentSchedule setContent:[array objectAtIndex:0]];
	  }
	}
}

- (void) dealloc
{
  [[NSDistributedNotificationCenter defaultCenter] removeObserver:self name:RSScheduleUpdateCompleteNotification object:RSBackgroundApplication];
	[[NSDistributedNotificationCenter defaultCenter] removeObserver:self name:RSRecordingAddedNotification object:RSBackgroundApplication];
	[[NSDistributedNotificationCenter defaultCenter] removeObserver:self name:RSRecordingRemovedNotification object:RSBackgroundApplication];

  // Store the current schedule into the preferences
  [[NSUserDefaults standardUserDefaults] setObject:[[[[mCurrentSchedule content] objectID] URIRepresentation] absoluteString] forKey:kCurrentScheduleURIKey];
  [[NSUserDefaults standardUserDefaults] synchronize];  
  
  // Store the current lineup into the preferences
  NSManagedObjectID *lineupObjectID = [[mCurrentLineup content] objectID];
  NSURL* lineupObjectURI = [lineupObjectID URIRepresentation];

  [[NSUserDefaults standardUserDefaults] setObject:[lineupObjectURI absoluteString] forKey:kCurrentLineupURIKey];
  [[NSUserDefaults standardUserDefaults] synchronize];  
  [super dealloc];
}

#pragma mark Action Methods

- (void) setGetScheduleButtonEnabled:(BOOL)enabled
{
  [mGetScheduleButton setEnabled:enabled forSegment:0];
}

- (IBAction) recordShow:(id)sender
{
  NSError *error;
  BOOL status = [self addRecordingOfSchedule:[mCurrentSchedule content] error:&error];
  if (status == NO)
  {
    if (([[error domain] compare:RSErrorDomain] == NSOrderedSame) && ([error code] == kRSErrorSchedulingConflict))
    {
      [self showScheduleConflict:error];
    }
    else
    {
      [[self window] presentError:error];
    }
  }
}

- (IBAction) recordSeasonPass:(id)sender
{
	[self addSeasonPassForProgram:[[mCurrentSchedule content] program] onStation:[[mCurrentSchedule content] station]];
}

- (IBAction) watchStation:(id)sender
{
	// Find the HDHRTuner for the station/lineup pair
	Z2ITStation *aStation = [mCurrentStation content];
	Z2ITLineup *aLineup = [mCurrentLineup content];

	NSSet *hdhrStations = [aStation hdhrStations];
	HDHomeRunStation *aHDHRStation;
	for (aHDHRStation in hdhrStations)
	{
		if ((aHDHRStation.z2itStation == aStation) && (aHDHRStation.channel.channelStationMap.lineup == aLineup))
		{
			[(recsched_AppDelegate *)[[NSApplication sharedApplication] delegate] launchVLCAction:sender withParentWindow:[self window] startStreaming:aHDHRStation];
			break;
		}
	}
}

- (IBAction) createWishlist:(id)sender
{
	[NSApp beginSheet:mPredicatePanel modalForWindow:[self window] modalDelegate:mWishlistController didEndSelector:nil contextInfo:nil];
	[NSApp runModalForWindow:[self window]];
	[NSApp endSheet:mPredicatePanel];
	[mPredicatePanel orderOut:self];
}

#pragma mark Responder Methods

- (void)flagsChanged:(NSEvent *)theEvent
{
//    NSLog(@"MainWindowController - flagsChanged - %@", theEvent);
}

#pragma mark Callback Methods

- (void) setCurrentSchedule:(Z2ITSchedule*)inSchedule
{
  [mCurrentSchedule setContent:inSchedule];
}

- (Z2ITSchedule *)currentSchedule
{
  return [mCurrentSchedule content];
}

- (void) showSchedule:(id)anArgument
{
	[mScheduleContainerView setHidden:NO];
        mSeasonPassCalendarViewController.seasonPassCalendarViewHidden = YES;
	[mProgramSearchViewController setSearchViewHidden:YES];
}

- (void) showSearch:(id)anArgument
{
	[mScheduleContainerView setHidden:YES];
        mSeasonPassCalendarViewController.seasonPassCalendarViewHidden = YES;
	[mProgramSearchViewController setSearchViewHidden:NO];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
			ofObject:(id)object 
			change:(NSDictionary *)change
			context:(void *)context
{
  if ((object == mViewSelectionTreeController) && ([keyPath isEqual:@"selection"]))
	{
		if ([[mViewSelectionTreeController selection] valueForKey:RSSourceListActionMessageNameKey] != NSNoSelectionMarker)
		{
			SEL actionSelector = NSSelectorFromString([[mViewSelectionTreeController selection] valueForKey:RSSourceListActionMessageNameKey]);
			if ([self respondsToSelector:actionSelector])
				[self performSelector:actionSelector withObject:[mViewSelectionTreeController selection]];
		}
    }
	if ((object == mRecordingsArrayController) && ([keyPath isEqual:@"arrangedObjects"]))
	{
		// The list of future recordings has changed - update the UI.
		[self updateSourceListForRecordings];
	}
	if ((object == mSeasonPassArrayController) && ([keyPath isEqual:@"arrangedObjects"]))
	{
		// The list of future recordings has changed - update the UI.
		[self updateSourceListForSeasonPasses];
	}
}

- (BOOL)validateUserInterfaceItem:(id < NSValidatedUserInterfaceItem >)anItem
{
	BOOL enableItem = NO;
	
	if (([anItem action] == @selector(watchStation:)) || ([anItem action] == @selector(recordShow:)) || ([anItem action] == @selector(recordSeasonPass:)))
	{
		if ([mCurrentStation content] != nil)
		{
			enableItem = [[mCurrentStation content] hasValidTunerForLineup:[mCurrentLineup content]];
		}
	}
	
	if ([anItem action] == @selector(delete:))
	{
		// Do we have a selection
		NSTreeNode *theSelection = [mViewSelectionTreeController selection];
		if (theSelection)
		{
			// Is it 'deletable' ?
			if ([theSelection valueForKey:RSSourceListDeletableKey] != nil)
			{
				enableItem = [[theSelection valueForKey:RSSourceListDeletableKey] boolValue];
			}
		}
	}
	
	if ([anItem action] == @selector(createWishlist:))
		enableItem = YES;
		
	return enableItem;
}

#pragma mark Notifications

- (void) scheduleUpdateCompleteNotification:(NSNotification*)aNotification
{
	// Store the current lineup selection (if there is one)
	Z2ITLineup *currentLineup = [mCurrentLineup content];
	NSError *error = nil;
	[mLineupsArrayController fetchWithRequest:[mLineupsArrayController defaultFetchRequest] merge:NO error:&error];
	
	if (error)
	{
		NSLog(@"scheduleUpdateCompleteNotification - fetchWithRequest got error %@", error);
	}
	if (!currentLineup)
	{
		if ([[mLineupsArrayController arrangedObjects] count] > 0)
			currentLineup = [[mLineupsArrayController arrangedObjects] objectAtIndex:0];
	}

	[mCurrentLineup setContent:currentLineup];
	
	// Trigger the schedule view to redraw
	[[mScheduleView delegate] setStartTime:[[mScheduleView delegate] startTime]];
}

- (void) recordingAddedNotification:(NSNotification*)aNotification
{
	NSError *error = nil;
	
	// Refetch the current schedule to update it's 'recording dot'
  NSArray *newRecordings = [[aNotification userInfo] valueForKey:RSRecordingAddedRecordingsURIKey];
  
  for (NSString *recordingURIString in newRecordings)
  {
    NSURL *newRecordingURI = [NSURL URLWithString:recordingURIString];
    NSManagedObjectID *newRecordingID = [[[NSApp delegate] persistentStoreCoordinator] managedObjectIDForURIRepresentation:newRecordingURI];
    RSRecording *newRecording = (RSRecording *) [[[NSApp delegate] managedObjectContext] objectWithID:newRecordingID];
    if (newRecording.schedule == self.currentSchedule)
    {
      [[[NSApp delegate] managedObjectContext] refreshObjectWithoutCache:self.currentSchedule mergeChanges:YES];
    }
  }
	// Reload the recordings array controller to add the new recording
	[mRecordingsArrayController fetchWithRequest:[mRecordingsArrayController defaultFetchRequest] merge:NO error:&error];
}

- (void) recordingRemovedNotification:(NSNotification*)aNotification
{
	NSError *error = nil;

	// Refetch the current schedule to update it's 'recording dot'
	NSURL *removedRecordingOfScheduleURI = [NSURL URLWithString:[[aNotification userInfo] valueForKey:RSRecordingRemovedRecordingOfScheduleURIKey]];
	NSManagedObjectID *removedRecordingOfScheduleID = [[[NSApp delegate] persistentStoreCoordinator] managedObjectIDForURIRepresentation:removedRecordingOfScheduleURI];
	Z2ITSchedule *removedRecordingOfSchedule = (Z2ITSchedule *) [[[NSApp delegate] managedObjectContext] objectWithID:removedRecordingOfScheduleID];
	if (removedRecordingOfSchedule == self.currentSchedule)
	{
		[[[NSApp delegate] managedObjectContext] refreshObjectWithoutCache:self.currentSchedule mergeChanges:YES];
	}

	// Reload the recordings array controller to remove the recording
	[mRecordingsArrayController fetchWithRequest:[mRecordingsArrayController defaultFetchRequest] merge:NO error:&error];
}

- (void) seasonPassAddedNotification:(NSNotification*)aNotification
{
	NSError *error = nil;
	NSArray *newRecordings = [[aNotification userInfo] valueForKey:RSSeasonPassNewRecordingsURIKey];
  if ([newRecordings count] > 0)
  {
    for (NSString *recordingURI in newRecordings)
    {
      NSManagedObjectID *newRecordingID = [[[NSApp delegate] persistentStoreCoordinator] managedObjectIDForURIRepresentation:[NSURL URLWithString:recordingURI]];
      RSRecording *newRecording = (RSRecording *) [[[NSApp delegate] managedObjectContext] objectWithID:newRecordingID];
      if (newRecording.schedule == self.currentSchedule)
      {
        [[[NSApp delegate] managedObjectContext] refreshObjectWithoutCache:self.currentSchedule mergeChanges:YES];
      }
    }
    
    // Reload the recordings array controller to add the new recordings
    [mRecordingsArrayController fetchWithRequest:[mRecordingsArrayController defaultFetchRequest] merge:NO error:&error];
  }
  
	// Reload the season pass array controller to add the new season pass
	[mSeasonPassArrayController fetchWithRequest:[mSeasonPassArrayController defaultFetchRequest] merge:NO error:&error];
}

- (void) seasonPassRemovedNotification:(NSNotification*)aNotification
{
	NSError *error = nil;
  NSArray *cancelledRecordings = [[aNotification userInfo] valueForKey:RSSeasonPassCancelledRecordingsURIKey];
  if ([cancelledRecordings count] > 0)
  {
    for (NSString *removedRecordingOfScheduleURI in cancelledRecordings)
    {
      NSManagedObjectID *removedRecordingOfScheduleID = [[[NSApp delegate] persistentStoreCoordinator] managedObjectIDForURIRepresentation:[NSURL URLWithString:removedRecordingOfScheduleURI]];
      Z2ITSchedule *removedRecordingOfSchedule = (Z2ITSchedule *) [[[NSApp delegate] managedObjectContext] objectWithID:removedRecordingOfScheduleID];
      if (removedRecordingOfSchedule == self.currentSchedule)
      {
        [[[NSApp delegate] managedObjectContext] refreshObjectWithoutCache:self.currentSchedule mergeChanges:YES];
      }
    }
    // Reload the recordings array controller to remove the recordings
    [mRecordingsArrayController fetchWithRequest:[mRecordingsArrayController defaultFetchRequest] merge:NO error:&error];
  }
  
	// Reload the season pass array controller to remove the new season pass
	[mSeasonPassArrayController fetchWithRequest:[mSeasonPassArrayController defaultFetchRequest] merge:NO error:&error];
}

#pragma mark Window Delegate Methods

/**
    Returns the NSUndoManager for the window.  In this case, the manager
    returned is that of the managed object context for the application.
 */
 
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window {
    return [[[NSApp delegate] managedObjectContext] undoManager];
}

- (void) windowWillClose:(NSNotification*)aNotification
{
  [self autorelease];
}

#pragma mark Split View Delegate Methods

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMaximumPosition ofSubviewAt:(NSInteger)dividerIndex
{
	if (splitView == mTopLevelSplitView)
	{
		if (proposedMaximumPosition > kSourceListMaxWidth)
			return kSourceListMaxWidth;
		else
			return proposedMaximumPosition;
	}
	if (splitView == mScheduleSplitView)
	{
		if (proposedMaximumPosition > mDetailViewMinHeight)
			return mDetailViewMinHeight;
		else
			return proposedMaximumPosition;
	}
	return proposedMaximumPosition;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMinimumPosition ofSubviewAt:(NSInteger)dividerIndex
{
	if (splitView == mTopLevelSplitView)
	{
		if (proposedMinimumPosition < kSourceListMinWidth)
			return kSourceListMinWidth;
		else
			return proposedMinimumPosition;
	}
	return proposedMinimumPosition;
}

#pragma mark View Selection Table Delegate Methods


- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item
{
	if (item == nil)
		return NO;
	NSMutableDictionary *aTreeNode = [item representedObject];
	NSNumber *headingFlag = [aTreeNode valueForKey:RSSourceListHeadingKey];
	if (headingFlag && ([headingFlag boolValue] == YES))
		return NO;
	else
		return YES;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldShowCellExpansionForTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
	NSMutableDictionary *aTreeNode = [item representedObject];
	NSNumber *expandableFlag = [aTreeNode valueForKey:RSSourceListExpandableKey];
	if (expandableFlag && ([expandableFlag boolValue] == NO))
		return NO;
	else
		return YES;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldCollapseItem:(id)item
{
	NSMutableDictionary *aTreeNode = [item representedObject];
	NSNumber *expandableFlag = [aTreeNode valueForKey:RSSourceListExpandableKey];
	if (expandableFlag && ([expandableFlag boolValue] == NO))
		return NO;
	else
		return YES;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isGroupItem:(id)item
{
	NSMutableDictionary *aTreeNode = [item representedObject];
	NSNumber *headingFlag = [aTreeNode valueForKey:RSSourceListHeadingKey];
	if (headingFlag && ([headingFlag boolValue] == YES))
		return YES;
	else
		return NO;
}

- (BOOL) outlineView:(NSOutlineView*)outlineView shouldShowDisclosureTriangleForItem:(id)item
{
	NSMutableDictionary *aTreeNode = [item representedObject];
	NSNumber *expandableFlag = [aTreeNode valueForKey:RSSourceListExpandableKey];
	if (expandableFlag && ([expandableFlag boolValue] == NO))
		return NO;
	else
		return YES;
}

- (void) deleteSelectedRowsOfOutlineView:(NSOutlineView *) aOutlineView
{
	NSMutableDictionary *aTreeNode = [mViewSelectionTreeController selection];
	if (aTreeNode && ([aTreeNode valueForKey:RSSourceListDeleteMessageNameKey] != nil))
	{
		// If we have a delete message name then see if we respond to it and call it with the selection
		SEL deleteSelector = NSSelectorFromString([[mViewSelectionTreeController selection] valueForKey:RSSourceListDeleteMessageNameKey]);
		if ([self respondsToSelector:deleteSelector])
			[self performSelector:deleteSelector withObject:aTreeNode];
	}
}

#pragma mark NSOutlineView Delegate messages for Drag and Drop

- (BOOL)outlineView:(NSOutlineView *)outlineView writeItems:(NSArray *)items toPasteboard:(NSPasteboard *)pboard 
{
    mDraggedNodes = items; // Don't retain since this is just holding temporaral drag information, and it is only used during a drag!  We could put this in the pboard actually.
    
    // Provide data for our custom type, and simple NSStrings.
    [pboard declareTypes:[NSArray arrayWithObjects:RSSourceListPBoardType, nil] owner:self];

    // the actual data doesn't matter since RSSourceListPasteboardType drags aren't recognized by anyone but us!.
    [pboard setData:[NSData data] forType:RSSourceListPBoardType]; 
    
    return YES;
}

- (BOOL) proposedItemCanAcceptDrop:(id)item
{
	BOOL canAcceptDrop = NO;
	if (item)
	{
		NSMutableDictionary *nodeDictionary = ([[item representedObject] isKindOfClass:[NSMutableDictionary class]] ? [item representedObject] : nil);
		if (nodeDictionary)
		{
			if ([nodeDictionary valueForKey:RSSourceListCanAcceptDropKey] && ([[nodeDictionary valueForKey:RSSourceListCanAcceptDropKey] boolValue] == YES))
				canAcceptDrop = YES;
		}
	}
	return canAcceptDrop;
}

- (NSDragOperation)outlineView:(NSOutlineView *)outlineView validateDrop:(id < NSDraggingInfo >)info proposedItem:(id)item proposedChildIndex:(NSInteger)index
{
	if ([self proposedItemCanAcceptDrop:item])
	{
		[outlineView setDropItem:item dropChildIndex:-1];	// Retarget all drops to the 'group' heading.
		return NSDragOperationGeneric;
	}
	return NSDragOperationNone;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView acceptDrop:(id < NSDraggingInfo >)info item:(id)item childIndex:(NSInteger)index
{
	NSMutableDictionary *nodeDictionary = ([[item representedObject] isKindOfClass:[NSMutableDictionary class]] ? [item representedObject] : nil);
    NSPasteboard *pboard = [info draggingPasteboard];

	if (nodeDictionary && [self proposedItemCanAcceptDrop:item])
	{
		if  (([nodeDictionary valueForKey:RSSourceListTypeKey] == RSSourceListNodeFutureRecordingsType) && ([pboard availableTypeFromArray:[NSArray arrayWithObject:RSSSchedulePBoardType]] != nil))
		{
				NSDictionary *dragInfoDict = [pboard propertyListForType:RSSSchedulePBoardType];
				NSPersistentStoreCoordinator *storeCoordinator = [[NSApp delegate] persistentStoreCoordinator];
				NSManagedObjectContext *MOC = [[NSApp delegate] managedObjectContext];
				
				Z2ITSchedule *aSchedule = (Z2ITSchedule*) [MOC objectWithID:[storeCoordinator managedObjectIDForURIRepresentation:[NSURL URLWithString:[dragInfoDict valueForKey:@"scheduleObjectURI"]]]];
                                NSError *error;
                                BOOL status = [self addRecordingOfSchedule:aSchedule error:&error];
                                if (status == NO)
                                {
                                  [[self window] presentError:error];
                                }
                                return status;
		}
		else
		{
				return NO;
		}
	}
	else
		return NO;
}

#pragma mark Private Internal Methods

- (BOOL) addRecordingOfSchedule:(Z2ITSchedule*)schedule error:(NSError**)error;
{
  if ([[NSApp delegate] recServer])
  {
    if (error)
    {
      *error = nil;
    }
    return [[[NSApp delegate] recServer] addRecordingOfScheduleWithObjectID:[schedule objectID] error:error];
  }
  else
  {
    if (error)
    {
      NSArray *optionsArray = [NSArray arrayWithObjects:@"Continue", @"Quit and Restart", nil];
      RSNoConnectionErrorRecovery *recoveryAttempter = [[[RSNoConnectionErrorRecovery alloc] init] autorelease];
      NSDictionary *eDict = [NSDictionary dictionaryWithObjectsAndKeys:@"There is no connection to the background application.", NSLocalizedDescriptionKey,
                                                                       @"Quit and restart this application to recreate the connection.",  NSLocalizedRecoverySuggestionErrorKey,
                                                                       optionsArray, NSLocalizedRecoveryOptionsErrorKey,
                                                                       recoveryAttempter,  NSRecoveryAttempterErrorKey,
                                                                       nil];
      *error = [NSError errorWithDomain:RSErrorDomain code:kRSErrorNoServerConnection userInfo:eDict];
    }
    return NO;
  }
}

- (BOOL) addSeasonPassForProgram:(Z2ITProgram*)program onStation:(Z2ITStation*)station
{
	NSError *error = nil;
	if ([[NSApp delegate] recServer])
	{
		if ([[[NSApp delegate] recServer] addSeasonPassForProgramWithObjectID:[program objectID] onStation:[station objectID] error:&error] == NO)
		{
			[[NSAlert alertWithError:error] runModal];
			return NO;
		}
		else
		{
			return YES;
		}
	}
	else
	{
		return NO;
	}
}

- (void) showScheduleConflict:(NSError*)error
{
  RSScheduleConflictController *conflictController = [[RSScheduleConflictController alloc] initWithWindowNibName:@"ScheduleConflictWindow"];
  [conflictController loadWindow];
  [conflictController setScheduleToBeRecordedObjectID:[[error userInfo] valueForKey:kRSErrorScheduleToBeRecorded]];
  [conflictController setConflictingSchedulesObjectIDs:[[error userInfo] valueForKey:kRSErrorConflictingSchedules]];
  [[conflictController window] center];
  [[NSApplication sharedApplication] runModalForWindow:[conflictController window]];
  [conflictController release];
}

@end
