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

#import "RecSchedServer.h"
#import "recsched_bkgd_AppDelegate.h"
#import "HDHomeRunMO.h"
#import "hdhomerun.h"
#import "tvDataDelivery.h"
#import "Z2ITLineup.h"
#import "Z2ITProgram.h"
#import "Z2ITSchedule.h"
#import "Z2ITStation.h"
#import "RSRecording.h"
#import "XTVDParser.h"
#import "RecordingThread.h"
#import "HDHomeRunTuner.h"
#import "RSStoreUpdateProtocol.h"
#import "RSTranscodeController.h"

const int kDefaultUpdateScheduleFetchDurationInHours = 3;
const int kDefaultFutureScheduleFetchDurationInHours = 12;
NSString *RSNotificationUIActivityAvailable = @"RSNotificationUIActivityAvailable";

@interface RSActivityProxy : NSObject <RSActivityDisplay>
{
  id mUIActivity;
  NSMutableArray *mTokenList;
  NSLock  *mActivityLock;
}

- (void) setUIActivity:(id)uiActivity;

@end

@implementation RecSchedServer

- (id) init {
  self = [super init];
  if (self != nil) {
    mExitServer = NO;
    mUIActivityProxy = [[RSActivityProxy alloc] init];
    [mUIActivityProxy setUIActivity:self];    // Start with ourselves as the activity display (a text log to the console)
	
    // Setup the recording queues in a bit (after the app startup has completed and we have a delegate etc.)
    [self performSelector:@selector(initializeRecordingQueues) withObject:nil afterDelay:0];
		[self performSelector:@selector(initializeTranscodingController) withObject:nil afterDelay:0];
  }
  return self;
}

- (void) dealloc
{
  [mUIActivityProxy release];
  [super dealloc];
}

- (void) initializeRecordingQueues
{
    // Initialize our array of recording queues - we have one queue (an NSMutableArray) per tuner
    NSArray *allTuners = [HDHomeRunTuner allTunersInManagedObjectContext:[[NSApp delegate] managedObjectContext]];
    mRecordingQueues = [[NSMutableArray alloc] initWithCapacity:[allTuners count]];
    HDHomeRunTuner *aTuner;
    for (aTuner in allTuners)
    {
      // Each queue also needs a timer for when the next recording needs to be started
      RSRecordingQueue *aQueue = [[RSRecordingQueue alloc] initWithTuner:aTuner];
      [mRecordingQueues insertObject:aQueue atIndex:0];
      [aQueue release];

      // Now run through all the recordings and assign them to the right queues according to their associated HDHRstation
      for (RSRecording *aRecording in aTuner.recordings)
      {
        if (([aRecording.status intValue] == RSRecordingNotYetStartedStatus) && ([aRecording.schedule.endTime compare:[NSDate date]] == NSOrderedDescending))
				{
					aRecording.recordingThreadController = [[RecordingThreadController alloc]initWithRecording:aRecording recordingServer:self];
          [aQueue addRecording:aRecording];
				}
      }
    }
}

- (void) initializeTranscodingController
{
	if ([[[[NSUserDefaultsController sharedUserDefaultsController] values] valueForKey:kTranscodeProgramsKey] boolValue] == YES)
		mTranscodeController = [[RSTranscodeController alloc] init];
}

- (void) initializeUIActivityConnection
{
  // Connect to server
  NSConnection *uiActivityServerConnection = [NSConnection connectionWithRegisteredName:kRecUIActivityConnectionName host:nil];
  mUIActivity = [uiActivityServerConnection rootProxy];

  // check if connection worked.
  if (mUIActivity == nil) 
  {
    NSLog(@"couldn't connect with User Interface Application");
  }
  else
  {
    //
    // set protocol for the remote object & then register ourselves with the 
    // messaging server.
    [mUIActivity setProtocolForProxy:@protocol(RSActivityDisplay)];
    
    [mUIActivityProxy setUIActivity:mUIActivity];
  }
  
  // Post a notification that the activity connection is available
  [[NSNotificationCenter defaultCenter] postNotificationName:RSNotificationUIActivityAvailable object:self];
}

- (void) initializeStoreUpdateConnection
{
  // Connect to server
  mStoreUpdate = [[NSConnection rootProxyForConnectionWithRegisteredName:kRSStoreUpdateConnectionName  host:nil] retain];
   
  // check if connection worked.
  if (mStoreUpdate == nil) 
  {
    NSLog(@"couldn't connect with User Interface (store update) Application");
  }
  else
  {
    //
    // set protocol for the remote object & then register ourselves with the 
    // messaging server.
    [mStoreUpdate setProtocolForProxy:@protocol(RSStoreUpdate)];
  }
}

- (RSActivityProxy*) uiActivity
{
    return mUIActivityProxy;
}

- (id) storeUpdate
{
	return mStoreUpdate;
}

- (void) performCleanup:(id)info
{
  // Clear all old items from the store
  NSDate *cleanupDate = [NSDate dateWithTimeIntervalSinceNow:-(12 * 60 * 60)];		// 12 hours prior to now
  NSMutableDictionary *callData = [[NSMutableDictionary alloc] initWithObjectsAndKeys:cleanupDate, kCleanupDateKey, self, @"reportProgressTo", self, kReportCompletionToKey,
   [[NSApp  delegate] persistentStoreCoordinator], kPersistentStoreCoordinatorKey, nil];

	if ([info valueForKey:kTVDataDeliveryFetchFutureScheduleKey] != nil)
	{
		[callData setValue:[info valueForKey:kTVDataDeliveryFetchFutureScheduleKey] forKey:kTVDataDeliveryFetchFutureScheduleKey];
	}
	if ([info valueForKey:kTVDataDeliveryEndDateKey] != nil)
	{
		[callData setValue:[info valueForKey:kTVDataDeliveryEndDateKey] forKey:kTVDataDeliveryEndDateKey];
	}
			 
  xtvdCleanupThread *aCleanupThread = [[xtvdCleanupThread alloc] init];
  [NSThread detachNewThreadSelector:@selector(performCleanup:) toTarget:aCleanupThread withObject:callData];
  [aCleanupThread release];
  [callData release];
}

#pragma mark - Internal Methods

- (void) fetchScheduleWithDuration:(int)inHours
{
  CFAbsoluteTime currentTime = CFAbsoluteTimeGetCurrent();
  
  // Converting the current time to a Gregorian Date with no timezone gives us a GMT time that
  // SchedulesDirect expects
  CFGregorianDate startDate = CFAbsoluteTimeGetGregorianDate(currentTime,NULL);
  
  // Retrieve 'n' hours of data
  CFGregorianUnits retrieveRange;
  memset(&retrieveRange, 0, sizeof(retrieveRange));
  retrieveRange.hours = inHours;
    
  CFAbsoluteTime endTime = CFAbsoluteTimeAddGregorianUnits(currentTime, NULL, retrieveRange);
  CFGregorianDate endDate = CFAbsoluteTimeGetGregorianDate(endTime,NULL);
  
  NSString *startDateStr = [NSString stringWithFormat:@"%d-%d-%dT%d:0:0Z", startDate.year, startDate.month, startDate.day, startDate.hour];
  NSString *endDateStr = [NSString stringWithFormat:@"%d-%d-%dT%d:0:0Z", endDate.year, endDate.month, endDate.day, endDate.hour];
  
  xtvdDownloadThread *aDownloadThread = [[xtvdDownloadThread alloc] init];
  NSDictionary *callData = [[NSDictionary alloc] initWithObjectsAndKeys:startDateStr, kTVDataDeliveryStartDateKey, endDateStr, kTVDataDeliveryEndDateKey, self, kTVDataDeliveryDataRecipientKey, self, kTVDataDeliveryReportProgressToKey, nil];
  [NSThread detachNewThreadSelector:@selector(performDownload:) toTarget:aDownloadThread withObject:callData];
  [aDownloadThread release];
  [callData release];
}

- (void) recordingComplete:(NSManagedObjectID *)aRecordingObjectID
{
	RSRecording *recordingJustFinished = (RSRecording*)[[[NSApp delegate] managedObjectContext] objectRegisteredForID:aRecordingObjectID];
	[recordingJustFinished.recordingQueue recordingComplete:recordingJustFinished];
	[mTranscodeController updateForCompletedRecordings:[NSArray arrayWithObject:recordingJustFinished]];
}

#pragma mark Schedule Update Methods

// If the current schedule data is more than one hour out of date then download new
// schedule data and update the database.
- (void) autoUpdateSchedule
{
        // We maintain a file 'scheduleUpdated' in the application support/recsched folder. The last modified date
        // on this file is the last time the schedule was downloaded.
        NSString *scheduleUpdatedPath = [NSString stringWithFormat:@"%@/scheduleUpdated", [[NSApp delegate] applicationSupportFolder]];
        BOOL updateScheduleNow = YES;
        if ([[NSFileManager defaultManager] fileExistsAtPath:scheduleUpdatedPath])
        {
          NSError *error = nil;
          NSDictionary *storeAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:scheduleUpdatedPath error:&error];
          if (!error)
          {
            // -3600 is one hour in the past
            if ([[storeAttributes valueForKey:NSFileModificationDate] timeIntervalSinceNow] > -3600)
                    updateScheduleNow = NO;
          }
        }
	// Set up a timer to fire one hour before the about to be fetched schedule data 'runs out'
	[NSTimer scheduledTimerWithTimeInterval:(kDefaultUpdateScheduleFetchDurationInHours - 1) * 60 * 60 target:self selector:@selector(updateScheduleTimer:) userInfo:nil repeats:NO]; 
	
	if (updateScheduleNow)
		[self fetchScheduleWithDuration:kDefaultUpdateScheduleFetchDurationInHours];
}

- (void) updateScheduleTimer:(NSTimer*)aTimer
{
	NSLog(@"Time to update the schedule!");
	[self autoUpdateSchedule];
}

// This routine can be called repeateadly to get all the schedule data for the next 14 days, 
// each time it's called it get's the next 'tranche' of schedule data (according to the quantity
// of data to download set in the preferences. It maintains an internal value of the last starting date
// that was fetched and uses that to determine the next range to fetch. Spacing things out and breaking them
// up into chunks lessers the load on the data servers and also breaks the parsing up into slightly more managed portions.
- (BOOL) fetchFutureSchedule:(id)info
{
  if (mLastScheduleFetchEndDate == nil)
  {
    // We need to determine a reasonable starting time - the best bet is to just take the latest start date in the
    // schedule list and work from there
	Z2ITSchedule *lastSchedule = [Z2ITSchedule fetchScheduleWithLatestStartDateInMOC:[[NSApp delegate] managedObjectContext]];
	if (lastSchedule)
	{
		mLastScheduleFetchEndDate = [[NSCalendarDate alloc] initWithTimeInterval:0 sinceDate:[lastSchedule time]];
	}
	else
	{
		mLastScheduleFetchEndDate = [[NSCalendarDate alloc] initWithTimeIntervalSinceNow:0];
	}
    [mLastScheduleFetchEndDate setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
  }
  
  // If the last schedule fetch start date is sooner than 'chunk size' before two weeks from now we need to get
  // some more data.
  NSCalendarDate *twoWeeksOut = [[NSCalendarDate calendarDate] dateByAddingYears:0 months:0 days:14 hours:-kDefaultFutureScheduleFetchDurationInHours minutes:0 seconds:0];
  [twoWeeksOut setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
  
  if ([mLastScheduleFetchEndDate compare:twoWeeksOut] == NSOrderedAscending)
  {
    if ([mLastScheduleFetchEndDate compare:[NSDate date]] == NSOrderedAscending)
    {
	  [mLastScheduleFetchEndDate release];
      mLastScheduleFetchEndDate = [[NSCalendarDate alloc] initWithTimeIntervalSinceNow:0];    // No point fetching schedule data before now
      [mLastScheduleFetchEndDate setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
    }
    
    NSCalendarDate *endDate = [mLastScheduleFetchEndDate dateByAddingYears:0 months:0 days:0 hours:kDefaultFutureScheduleFetchDurationInHours minutes:0 seconds:0];
    
    NSString *startDateStr = [NSString stringWithFormat:@"%d-%d-%dT%d:0:0Z", [mLastScheduleFetchEndDate yearOfCommonEra], [mLastScheduleFetchEndDate monthOfYear], [mLastScheduleFetchEndDate dayOfMonth], [mLastScheduleFetchEndDate hourOfDay]];
    NSString *endDateStr = [NSString stringWithFormat:@"%d-%d-%dT%d:0:0Z", [endDate yearOfCommonEra], [endDate monthOfYear], [endDate dayOfMonth], [endDate hourOfDay]];
    
    NSLog(@"Fetching future schedule data for %@ to %@", startDateStr, endDateStr);
    
    NSDictionary *callData = [[NSDictionary alloc] initWithObjectsAndKeys:startDateStr, kTVDataDeliveryStartDateKey, endDateStr, kTVDataDeliveryEndDateKey, 
        self, kTVDataDeliveryDataRecipientKey, self, kTVDataDeliveryReportProgressToKey, 
        [NSNumber numberWithBool:YES], kTVDataDeliveryFetchFutureScheduleKey,
        nil];
	// We 'transfer' ownership of this dictionary to this new thread - they'll release the memory for us.
	xtvdDownloadThread *aDownloadThread = [[xtvdDownloadThread alloc] init];
    [NSThread detachNewThreadSelector:@selector(performDownload:) toTarget:aDownloadThread withObject:callData];
	[aDownloadThread release];
	[callData release];
    return YES;
  }
  
  // Otherwise we're done, return NO - no more data to retreive. SchedulesDirect maintains only approx 14 days of future
  // schedule information, so set a timer to fire in another 'fetchFuture' hours because by then another 'fetchFuture'
  // hours worth of schedule data should be available.
  NSDate *timerFireDate =  [NSDate dateWithTimeIntervalSinceNow:(kDefaultFutureScheduleFetchDurationInHours * 60 * 60)];
  [NSTimer scheduledTimerWithTimeInterval:[timerFireDate timeIntervalSinceNow] target:self selector:@selector(fetchFutureScheduleTimer:) userInfo:nil repeats:YES];
  
  return NO;
}

- (void) fetchFutureScheduleTimer:(NSTimer*)aTimer
{
  NSLog(@"Time To fetch future schedule data");
  [self fetchFutureSchedule:nil];
}


#pragma mark Callback Methods

- (void) handleDownloadData:(id)inDownloadResult
{
  NSDictionary *downloadResult = (NSDictionary*)inDownloadResult;
  NSDictionary *messages = [downloadResult valueForKey:@"messages"];
  NSDictionary *xtvd = [downloadResult valueForKey:@"xtvd"];
  NSLog(@"getScheduleAction downloadResult message = %@", [messages valueForKey:@"message"]);

  if (xtvd != nil)
  {
	id notificationProxy = [self uiActivity];
	if (notificationProxy == nil)
		notificationProxy = self;
	NSMutableDictionary *callData = [[NSMutableDictionary alloc] initWithObjectsAndKeys:[xtvd valueForKey:@"xmlFilePath"], @"xmlFilePath",
			notificationProxy, @"reportProgressTo", 
			self, kReportCompletionToKey, 
			[[NSApp  delegate] persistentStoreCoordinator], kPersistentStoreCoordinatorKey,
			nil];

	if ([downloadResult valueForKey:kTVDataDeliveryLineupsOnlyKey] != nil)
		[callData setValue:[downloadResult valueForKey:kTVDataDeliveryLineupsOnlyKey] forKey:kTVDataDeliveryLineupsOnlyKey];
		
	if ([downloadResult valueForKey:kTVDataDeliveryFetchFutureScheduleKey] != nil)
        {
		[callData setValue:[downloadResult valueForKey:kTVDataDeliveryFetchFutureScheduleKey] forKey:kTVDataDeliveryFetchFutureScheduleKey];
                [callData setValue:[downloadResult valueForKey:kTVDataDeliveryEndDateKey] forKey:kTVDataDeliveryEndDateKey];
        }

	[downloadResult release];
	
    // Start our local parsing
    xtvdParseThread *aParseThread = [[xtvdParseThread alloc] init];
    
    [NSThread detachNewThreadSelector:@selector(performParse:) toTarget:aParseThread withObject:callData];
	[aParseThread release];
	[callData release];
    }
}

#pragma mark Activity Protocol Methods

- (size_t) createActivity
{
	NSDictionary *anActivity = [[NSMutableDictionary alloc] initWithCapacity:3]; 
	return (size_t) anActivity;
}

- (void) endActivity:(size_t)activityToken
{
	[(NSDictionary *)activityToken release];
}

- (size_t) setActivity:(size_t)activityToken infoString:(NSString*)inInfoString
{
	NSLog(@"setActivityInfoString - %@", inInfoString);
        return activityToken;
}

- (size_t) setActivity:(size_t)activityToken progressIndeterminate:(BOOL) isIndeterminate
{
        return activityToken;
}

- (size_t) setActivity:(size_t)activityToken progressMaxValue:(double)inTotal
{
        return activityToken;
}

- (size_t) setActivity:(size_t)activityToken progressDoubleValue:(double)inValue
{
        return activityToken;
}

- (size_t) setActivity:(size_t)activityToken incrementBy:(double)delta
{
        return activityToken;
}

- (size_t) shouldCancelActivity:(size_t)activityToken cancel:(BOOL*)cancel
{
  if (cancel)
    *cancel = NO;
  return activityToken;
}

#pragma mark Store Update Protocol Methods

- (void) parsingComplete:(id)info
{
	NSLog(@"parsingComplete");
        
if ([info valueForKey:kTVDataDeliveryLineupsOnlyKey] && [[info valueForKey:kTVDataDeliveryLineupsOnlyKey] boolValue] == YES)
        {
          // Lineups only - no need to clean up or update anything else

        }
        else
        {
        // Update the 'scheduleUpdated' file
        NSString *scheduleUpdatedPath = [NSString stringWithFormat:@"%@/scheduleUpdated", [[NSApp delegate] applicationSupportFolder]];
        [[NSFileManager defaultManager] removeItemAtPath:scheduleUpdatedPath error:nil];
        [[NSFileManager defaultManager] createFileAtPath:scheduleUpdatedPath contents:nil attributes:nil];
		}
        
#if 1
	[self performCleanup:info];
#else
	// No cleanup performed - just send a fake cleanup complete notification
	[self cleanupComplete:info];
#endif
}

- (void) cleanupComplete:(id)info
{
	NSLog(@"cleanupComplete");
        if ([[info valueForKey:kTVDataDeliveryFetchFutureScheduleKey] boolValue] == YES)
        {
          mLastScheduleFetchEndDate = [[NSCalendarDate alloc] initWithString:[info valueForKey:kTVDataDeliveryEndDateKey] calendarFormat:@"%Y-%m-%dT%H:%M:%SZ"];
          [self performSelectorOnMainThread:@selector(fetchFutureSchedule:) withObject:nil waitUntilDone:NO];
        }
}

- (void) downloadError:(id)info
{
	NSLog(@"downloadError %@", info);
}

- (void) deviceScanComplete:(id)info
{
	NSLog(@"deviceScanComplete %@", info);
}

- (void) channelScanComplete:(id)info
{
	NSLog(@"channelScanComplete %@", info);
}

#pragma mark - Server Methods

- (void) activityDisplayAvailable
{
	[self initializeUIActivityConnection];
}

- (void) activityDisplayUnavailable
{
	[mUIActivity release];
	mUIActivity = nil;
}

- (void) storeUpdateAvailable
{
	[self initializeStoreUpdateConnection];
}

- (void) storeUpdateUnavailable
{
	[mStoreUpdate release];
	mStoreUpdate = nil;
}

- (bool) shouldExit
{
	return mExitServer;
}

- (void) findStations
{
  NSEntityDescription *entityDescription = [NSEntityDescription entityForName:@"Station" inManagedObjectContext:[[NSApp  delegate] managedObjectContext]];
  NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
  [request setEntity:entityDescription];
   
  NSPredicate *predicate = [NSPredicate predicateWithFormat:@"callSign == %@", @"WGBH"];
  [request setPredicate:predicate];
  
  NSError *error = nil;
  NSArray *array = [[[NSApp  delegate] managedObjectContext] executeFetchRequest:request error:&error];
  if (array == nil)
  {
      NSLog(@"Error executing fetch request to find latest schedule");
      return;
  }
  for (Z2ITStation *aStation in array)
  {
	NSSet *hdhrStations = [aStation hdhrStations];
	NSLog(@"Station Callsign = %@, hdhrStations = %@, hdhrStation callSign = %@, hdhrStation programNumber = %@",
		[aStation callSign], hdhrStations, [[hdhrStations anyObject] callSign], [[hdhrStations anyObject] programNumber]);
  }
}

- (BOOL) addRecordingOfSchedule:(NSManagedObjectID*)scheduleObjectID error:(NSError**)error
{
  Z2ITSchedule *mySchedule = nil;
  mySchedule = (Z2ITSchedule*) [[[NSApp delegate] managedObjectContext] objectWithID:scheduleObjectID];
  
  if (mySchedule)
  {
        NSLog(@"addRecordingOfSchedule");
	NSLog(@"  My Program title = %@, My Schedule start time = %@ channel = %@, %s", mySchedule.program.title, mySchedule.time, mySchedule.station.callSign, 
            ([mySchedule recording] == nil ? "does not have prior recording" : "has prior recording"));
	if ([mySchedule recording] == nil)
	{
                // Find out if a tuner for this recording is available.
                NSSet *candidateStations = mySchedule.station.hdhrStations;
                NSMutableArray *conflictingSchedules = [NSMutableArray arrayWithCapacity:1];
                RSRecording *aRecording = nil;
                NSLog(@"  There are %d candidate stations and %d recording queues", [candidateStations count], [mRecordingQueues count]);
                for (HDHomeRunStation *aStation in candidateStations)
                {
                  for (RSRecordingQueue *aRecordingQueue in mRecordingQueues)
                  {
                    NSLog(@"  Checking Queue for tuner %@", aRecordingQueue.tuner.longName);
                    if (aRecordingQueue.tuner == aStation.channel.tuner)
                    {
                      NSLog(@"  Tuner %@ has the station, there are %d recordings in the queue", aRecordingQueue.tuner.longName, [aRecordingQueue.queue count]);
                      // Does the Tuners queue have space/time for this recording ?
                      BOOL hasOverlaps = NO;
                      for (RSRecording *aPreviouslyScheduledRecording in aRecordingQueue.queue)
                      {
                        if ([aPreviouslyScheduledRecording.schedule overlapsWith:mySchedule])
                        {
                          NSLog(@"  Queue for tuner %@ has overlap with schedule title %@", aStation.channel.tuner.longName, aPreviouslyScheduledRecording.schedule.program.title);
                          hasOverlaps = YES;
                          [conflictingSchedules addObject:[aPreviouslyScheduledRecording.schedule objectID]];
                        }
                      }
                      if (!hasOverlaps)
                      {
                        NSLog(@"  There are no overlaps - creating a recording on tuner %@", aRecordingQueue.tuner.longName);
                        
                        // When we construct a recording we also need to associate it with the specific station on this tuner and 
                        // store that relationship. We'll use the relationship to reconstruct the queues on launch and also to use
                        // the correct station/tuner/device when recording starts. Otherwise there are no adequate guaruntees that our
                        // work schedule will actually come true.
                        aRecording = [RSRecording insertRecordingOfSchedule:mySchedule];
                        if (aRecording)
                        {
                          [aRecordingQueue addRecording:aRecording];
//                          [self addRecording:aRecording toQueue:[recordingQueueDict valueForKey:@"queue"]];
                          break;
                        }
                      }
                    }
                    if (aRecording)
                      break;
                  }
                  if (aRecording)
                    break;
                }
                
		if (aRecording)
		{
			aRecording.recordingThreadController = [[RecordingThreadController alloc]initWithRecording:aRecording recordingServer:self];
			if (![[[NSApp delegate] managedObjectContext] save:error])
                        {
				NSLog(@"addRecordingOfSchedule - error occured during save %@", *error);
                                return NO;
                        }
                        else
                          return YES;
		}
                else
                {
                  // No recording created - probably because of overlaps - we should construct an appropriate error object to return.
                  if (error != nil)
                  {
                    NSDictionary *eDict = [NSDictionary dictionaryWithObjectsAndKeys:conflictingSchedules, @"conflictingSchedules", nil];
                    *error = [[[NSError alloc] initWithDomain:@"com.iontv-app.error" code:-1 userInfo:eDict] autorelease];
                  }
                  return NO;
                }
	}
        else // Already scheduled to be recorded
          return YES;
  }
  else
  {
    NSLog(@"Could not find matching local schedule for the program");
    return NO;
  }
}

- (BOOL) cancelRecordingOfSchedule:(NSManagedObjectID*)scheduleObjectID error:(NSError**)error
{
  Z2ITSchedule *mySchedule = nil;
  mySchedule = (Z2ITSchedule*) [[[NSApp delegate] managedObjectContext] objectWithID:scheduleObjectID];
  
  if (mySchedule)
  {
	NSLog(@"My Program title = %@, My Schedule start time = %@ channel = %@, recording = %@", mySchedule.program.title, mySchedule.time, mySchedule.station.callSign, [mySchedule recording]);
	if ([mySchedule recording] != nil)
	{
          // We need to cancel/delete the recording thread controller - we can do this by setting the recordings thread controller property to nil
          mySchedule.recording.recordingThreadController = nil;
          
          // Remove the recording from the queue
					[mySchedule.recording.recordingQueue removeRecording:mySchedule.recording];

					// Remove the recording from the ManagedObjectContext
          [[[NSApp delegate] managedObjectContext] deleteObject:mySchedule.recording];
          return YES;
        }
        else
          return NO;
  }
  else
    return NO;
}

- (oneway void) updateSchedule
{
  CFAbsoluteTime currentTime = CFAbsoluteTimeGetCurrent();
  
  // Converting the current time to a Gregorian Date with no timezone gives us a GMT time that
  // SchedulesDirect expects
  CFGregorianDate startDate = CFAbsoluteTimeGetGregorianDate(currentTime,NULL);
  
  // Retrieve 'n' hours of data
  CFGregorianUnits retrieveRange;
  memset(&retrieveRange, 0, sizeof(retrieveRange));
  float hours = [[[[NSUserDefaultsController sharedUserDefaultsController] values] valueForKey:kScheduleDownloadDurationKey] floatValue];
  retrieveRange.hours = (int) hours;
    
  CFAbsoluteTime endTime = CFAbsoluteTimeAddGregorianUnits(currentTime, NULL, retrieveRange);
  CFGregorianDate endDate = CFAbsoluteTimeGetGregorianDate(endTime,NULL);
  
  NSString *startDateStr = [NSString stringWithFormat:@"%d-%d-%dT%d:0:0Z", startDate.year, startDate.month, startDate.day, startDate.hour];
  NSString *endDateStr = [NSString stringWithFormat:@"%d-%d-%dT%d:0:0Z", endDate.year, endDate.month, endDate.day, endDate.hour];
  
  // Send the message to the background server
  NSDictionary *callData = [[NSDictionary alloc] initWithObjectsAndKeys:startDateStr, kTVDataDeliveryStartDateKey, endDateStr, kTVDataDeliveryEndDateKey,
    self, kTVDataDeliveryDataRecipientKey,
    self, kTVDataDeliveryReportProgressToKey, nil];
  xtvdDownloadThread *aDownloadThread = [[xtvdDownloadThread alloc] init];
  [NSThread detachNewThreadSelector:@selector(performDownload:) toTarget:aDownloadThread withObject:callData];
  [aDownloadThread release];
  [callData release];
}

- (oneway void) updateLineups
{
  CFAbsoluteTime currentTime = CFAbsoluteTimeGetCurrent();
  
  // Converting the current time to a Gregorian Date with no timezone gives us a GMT time that
  // SchedulesDirect expects
  CFGregorianDate startDate = CFAbsoluteTimeGetGregorianDate(currentTime,NULL);
  
  // Retrieve 'n' hours of data
  CFGregorianUnits retrieveRange;
  memset(&retrieveRange, 0, sizeof(retrieveRange));

  retrieveRange.minutes = 0;
    
  CFAbsoluteTime endTime = CFAbsoluteTimeAddGregorianUnits(currentTime, NULL, retrieveRange);
  CFGregorianDate endDate = CFAbsoluteTimeGetGregorianDate(endTime,NULL);
  
  NSString *startDateStr = [NSString stringWithFormat:@"%d-%d-%dT%d:0:0Z", startDate.year, startDate.month, startDate.day, startDate.hour];
  NSString *endDateStr = [NSString stringWithFormat:@"%d-%d-%dT%d:0:0Z", endDate.year, endDate.month, endDate.day, endDate.hour];
  
  NSDictionary *callData = [[NSDictionary alloc] initWithObjectsAndKeys:startDateStr, kTVDataDeliveryStartDateKey, endDateStr, kTVDataDeliveryEndDateKey, [NSNumber numberWithBool:YES], kTVDataDeliveryLineupsOnlyKey,
      self, kTVDataDeliveryDataRecipientKey,
      self, kTVDataDeliveryReportProgressToKey, nil];
  xtvdDownloadThread *aDownloadThread = [[xtvdDownloadThread alloc] init];
  [NSThread detachNewThreadSelector:@selector(performDownload:) toTarget:aDownloadThread withObject:callData];
  [aDownloadThread release];
  [callData release];
}

- (void) scanForHDHomeRunDevices:(id)sender
{
	struct hdhomerun_discover_device_t result_list[64];
	NSMutableArray *newHDHomeRuns = [NSMutableArray arrayWithCapacity:5];
	NSMutableArray *existingHDHomeRuns = [NSMutableArray arrayWithCapacity:5];
	size_t activityToken = [[self uiActivity] createActivity];
  
	[[self uiActivity] setActivity:activityToken infoString:[NSString stringWithFormat:@"Looking for HDHomeRun Devices"]]; 
	[[self uiActivity] setActivity:activityToken progressIndeterminate:YES];
	
	int count = hdhomerun_discover_find_devices(HDHOMERUN_DEVICE_TYPE_TUNER, result_list, 64);
	
	if (count > 0)
	{
		int i=0;
		for (i=0; i < count; i++)
		{
			// See if an entry already exists
			HDHomeRun *anHDHomeRun = [HDHomeRun fetchHDHomeRunWithID:[NSNumber numberWithInt:result_list[i].device_id] inManagedObjectContext:[[[NSApplication sharedApplication] delegate] managedObjectContext]];
			if (!anHDHomeRun)
			{
			  // Otherwise we just create a new one
			  anHDHomeRun = [HDHomeRun createHDHomeRunWithID:[NSNumber numberWithInt:result_list[i].device_id] inManagedObjectContext:[[[NSApplication sharedApplication] delegate] managedObjectContext]];
			  [newHDHomeRuns addObject:anHDHomeRun];
			  [anHDHomeRun setName:[NSString stringWithFormat:@"Tuner 0x%x", result_list[i].device_id]];
                          
                          // We also need to create recording queues for the tuners on this device
                          NSSet *tuners = [anHDHomeRun tuners];
                          for (HDHomeRunTuner *aTuner in tuners)
                          {
                            RSRecordingQueue *aQueue = [[RSRecordingQueue alloc] initWithTuner:aTuner];
                            [mRecordingQueues insertObject:aQueue atIndex:0];
                            [aQueue release];
                          }
			}
			else
				[existingHDHomeRuns addObject:anHDHomeRun];
		}
	}
	[[self uiActivity] endActivity:activityToken];
	NSError *error = nil;
	if (![[[NSApp delegate] managedObjectContext] save:&error])
	{
		NSLog(@"scanForHDHomeRunDevices - saving context reported error %@", error);
	}
	NSDictionary *scanInfo = [NSDictionary dictionaryWithObjectsAndKeys:existingHDHomeRuns, @"existingHDHomeRuns", newHDHomeRuns, @"newHDHomeRuns", nil];
	[[self storeUpdate] deviceScanComplete:scanInfo];
}


- (void) scanForChannelsOnHDHomeRunDeviceID:(NSNumber*)deviceID tunerIndex:(NSNumber*)tunerIndex
{
	HDHomeRun *anHDHomeRun = [HDHomeRun fetchHDHomeRunWithID:deviceID inManagedObjectContext:[[NSApp delegate] managedObjectContext]];
	if (!anHDHomeRun)
	{
		NSLog(@"scanForChannelsOnHDHomeRunDeviceID:%@ - No Device Found !", deviceID);
		return;
	}
	HDHomeRunTuner *aTuner = [anHDHomeRun tunerWithIndex:[tunerIndex intValue]];
	if (!aTuner)
	{
		NSLog(@"scanForChannelsOnHDHomeRunDeviceID:%@ tunerIndex:%@ - No Tuner Found !", deviceID, tunerIndex);
		return;
	}
	[aTuner scanActionReportingProgressTo:[self uiActivity]];
}

- (void) setHDHomeRunDeviceWithID:(NSNumber*)deviceID nameTo:(NSString*)name tuner0LineupIDTo:(NSString*)tuner0LineupID tuner1LineupIDTo:(NSString*) tuner1LineupID
{
	// See if an entry already exists
	HDHomeRun *anHDHomeRun = [HDHomeRun fetchHDHomeRunWithID:deviceID inManagedObjectContext:[[NSApp delegate] managedObjectContext]];
	if (anHDHomeRun)
	{
		[anHDHomeRun setName:name];
		
		Z2ITLineup *aLineup = [Z2ITLineup fetchLineupWithID:tuner0LineupID inManagedObjectContext:[[NSApp delegate] managedObjectContext]];
		anHDHomeRun.tuner0.lineup = aLineup;
		aLineup = [Z2ITLineup fetchLineupWithID:tuner1LineupID inManagedObjectContext:[[NSApp delegate] managedObjectContext]];
		anHDHomeRun.tuner1.lineup = aLineup;

		NSError *error = nil;
		if (![[[NSApp delegate] managedObjectContext] save:&error])
		{
			NSLog(@"setHDHomeRunDeviceWithID - saving context reported error %@, info = %@", error, [error userInfo]);
		}
	}
	else
	{
		NSLog(@"setHDHomeRunDeviceWithID - cannot find device with ID %@", deviceID);
	}
}

- (oneway void) setHDHomeRunChannelsAndStations:(NSArray*)channelsArray onDeviceID:(int)deviceID forTunerIndex:(int)tunerIndex
{
//	NSLog(@"setHDHomeRunChannelsAndStations deviceID = %d, tunerIndex = %d", deviceID, tunerIndex); 

	HDHomeRun *anHDHomeRun = [HDHomeRun fetchHDHomeRunWithID:[NSNumber numberWithInt:deviceID] inManagedObjectContext:[[NSApp delegate] managedObjectContext]]; 
	if (anHDHomeRun) 
	{ 
		HDHomeRunTuner *aTuner = [anHDHomeRun tunerWithIndex:tunerIndex]; 
		if (aTuner) 
		{ 
			// Remove all the channels current on the tuner - we're going to replace them.
			NSArray *oldChannels = [[aTuner channels] allObjects];
			for (HDHomeRunChannel *aChannel in oldChannels)
			{
				[[[NSApp delegate] managedObjectContext] deleteObject:aChannel];
			}
			[aTuner removeChannels:[aTuner channels]];
			
			for (NSDictionary *aChannelDictionary in channelsArray) 
			{ 
//				NSLog(@"setHDHomeRunChannelsAndStations new channel number %d type %@ stations %@", [aChannelDictionary valueForKey:@"channelNumber"], [aChannelDictionary valueForKey:@"channelType"], [aChannelDictionary valueForKey:@"stations"]);
				// Create a new channel for this tuner
				HDHomeRunChannel *aChannel = [HDHomeRunChannel createChannelWithType:[aChannelDictionary valueForKey:@"channelType"] andNumber:[aChannelDictionary valueForKey:@"channelNumber"] inManagedObjectContext:[[NSApp delegate] managedObjectContext]];
				[aTuner addChannelsObject:aChannel];
				aChannel.tuner = aTuner;
				
				// Remove all the stations on the given channel - they'll be replaced with the data from the array 
				[aChannel clearAllStations]; 

				// Add all the stations in the array for this channel 
				[aChannel importStationsFrom:[aChannelDictionary valueForKey:@"stations"]]; 
			} 

			if ([channelsArray count] > 0) 
			{ 
				// processed some stations - save the MOC 
				NSError *error = nil;
				if (![[[NSApp delegate] managedObjectContext] save:&error])
					NSLog(@"setHDHomeRunChannelsAndStations - error occured during save %@", error);
				
				[[self storeUpdate] channelScanComplete:nil];
			} 
		} 
	} 
}

- (void) quitServer:(id)sender
{
	[NSApp  terminate:self];
//  if ([self applicationShouldTerminate:NSApp ])
  {
    NSLog(@"Server shutting down");
    mExitServer = YES;
  }
}

- (void) reloadPreferences:(id)sender
{
	[NSUserDefaults resetStandardUserDefaults];
	[[NSUserDefaults standardUserDefaults] addSuiteNamed:@"org.awkward.iontv"];
}

@synthesize mStoreUpdate;
@synthesize mExitServer;
@end

@implementation RSActivityProxy

- (id) init
{
  self = [super init];
  if (self != nil) {
    mTokenList = [[NSMutableArray alloc]initWithCapacity:5];
    mActivityLock  = [[NSLock alloc] init];
  }
  return self;
}

- (void) dealloc
{
  if ([mActivityLock lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:3]])
  {
    [mTokenList release];
    [mUIActivity release];
    mUIActivity = nil;
    [mActivityLock unlock];
  }
  else
    NSLog(@"RSActivityProxy - deallocating unlocked proxy !");
  [mActivityLock release];
  
  [super dealloc];
}

- (void) setUIActivity:(id)uiActivity
{
  if (mUIActivity != uiActivity)
  {
    if ([mActivityLock lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:3]])
    {
      // We need to reset our list of known tokens since none of them are valid anymore after changing the
      // UIActivity remote connection
      [mTokenList removeAllObjects];

      [mUIActivity release];
      mUIActivity = uiActivity;
      [mUIActivity retain];
      [mActivityLock unlock];
    }
    else
    {
      NSLog(@"RSActivityProxy - setUIActivity unable to obtain lock");
    }
  }
}

- (size_t) createActivity;
{
  if ([mActivityLock lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:3]])
  {
    @try {
      if (mUIActivity)
        {
          size_t newToken = [mUIActivity createActivity];
          [mTokenList addObject:[NSNumber numberWithLongLong:newToken]];
          [mActivityLock unlock];
          return newToken;
        }
    }
    @catch (NSException * e) {
      if (([e name] == NSPortTimeoutException) || ([e name] == NSInvalidReceivePortException))
      {
        [mUIActivity release];
        mUIActivity = nil;
      }
    }
    [mActivityLock unlock];
  }
  return 0;
}

- (void) endActivity:(size_t)activityToken
{
  if ([mActivityLock lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:3]])
  {
    // Drop the token from our list
    if ([mTokenList containsObject:[NSNumber numberWithLongLong:activityToken]])
      [mTokenList removeObject:[NSNumber numberWithLongLong:activityToken]];
    @try {
      if (mUIActivity)
        [mUIActivity endActivity:activityToken];
    }
    @catch (NSException * e) {
      if (([e name] == NSPortTimeoutException) || ([e name] == NSInvalidReceivePortException))
      {
        [mUIActivity release];
        mUIActivity = nil;
      }
    }
    [mActivityLock unlock];
  }
  else
    NSLog(@"RSActivityProxy - endActivity, unable to obtain lock");
}

- (size_t) setActivity:(size_t)activityToken infoString:(NSString*)inInfoString
{
  if ([mActivityLock lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:3]])
  {
    if (![mTokenList containsObject:[NSNumber numberWithLongLong:activityToken]])
    {
      [mActivityLock unlock];   // For now - we don't want to do a recursive lock for the next bit
      activityToken = [self createActivity];    // create a new activity for this (probably new) proxy connection
      [mActivityLock lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:1]];   // Retake the lock for the remained
    }
    
    @try {
      if (mUIActivity)
      {
        size_t aToken = [mUIActivity setActivity:activityToken infoString:inInfoString];
        [mActivityLock unlock];
        return aToken;
      }
    }
    @catch (NSException * e) {
      if (([e name] == NSPortTimeoutException) || ([e name] == NSInvalidReceivePortException))
      {
        [mUIActivity release];
        mUIActivity = nil;
      }
    }
    [mActivityLock unlock];
  }
  else
    NSLog(@"RSActivityProxy - setActivity:infoString:%@ unable to obtain lock", inInfoString);
  return 0;
}

- (size_t) setActivity:(size_t)activityToken progressIndeterminate:(BOOL)isIndeterminate
{
  if ([mActivityLock lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:3]])
  {
    if (![mTokenList containsObject:[NSNumber numberWithLongLong:activityToken]])
    {
      [mActivityLock unlock];
      return 0;   // Not one of our tokens
    }
    
    @try {
      if (mUIActivity)
      {
        size_t aToken =  [mUIActivity setActivity:activityToken progressIndeterminate:isIndeterminate];
        [mActivityLock unlock];
        return aToken;
      }
    }
    @catch (NSException * e) {
      if (([e name] == NSPortTimeoutException) || ([e name] == NSInvalidReceivePortException))
      {
        [mUIActivity release];
        mUIActivity = nil;
      }
    }
    [mActivityLock unlock];
  }
  else
    NSLog(@"RSActivityProxy - setActivityToken:progressIndeterminate unable to obtain lock");
  return 0;
}

- (size_t) setActivity:(size_t)activityToken progressMaxValue:(double)inTotal
{
  if ([mActivityLock lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:3]])
  {
    if (![mTokenList containsObject:[NSNumber numberWithLongLong:activityToken]])
    {
      [mActivityLock unlock];
      return 0;   // Not one of our tokens
    }
    
    @try {
      if (mUIActivity)
      {
        size_t aToken = [mUIActivity setActivity:activityToken progressMaxValue:inTotal];
        [mActivityLock unlock];
        return aToken;
      }
    }
    @catch (NSException * e) {
      if (([e name] == NSPortTimeoutException) || ([e name] == NSInvalidReceivePortException))
      {
        [mUIActivity release];
        mUIActivity = nil;
      }
    }
    [mActivityLock unlock];
  }
  else
    NSLog(@"RSActivityProxy - setActivity:progressMaxValue unable to obtain lock");
  return 0;
}

- (size_t) setActivity:(size_t)activityToken progressDoubleValue:(double)inValue
{
  if ([mActivityLock lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:3]])
  {
    if (![mTokenList containsObject:[NSNumber numberWithLongLong:activityToken]])
    {
      [mActivityLock unlock];
      return 0;   // Not one of our tokens
    }
    
    @try {
      if (mUIActivity)
      {
        size_t aToken = [mUIActivity setActivity:activityToken progressDoubleValue:inValue];
        [mActivityLock unlock];
        return aToken;
      }
    }
    @catch (NSException * e) {
      if (([e name] == NSPortTimeoutException) || ([e name] == NSInvalidReceivePortException))
      {
        [mUIActivity release];
        mUIActivity = nil;
      }
    }
    [mActivityLock unlock];
  }
  else
    NSLog(@"RSActivityProxy - setActivity:progressDoubleValue unable to obtain lock");
  return 0;
}

- (size_t) setActivity:(size_t)activityToken incrementBy:(double)delta
{
  if ([mActivityLock lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:3]])
  {
    if (![mTokenList containsObject:[NSNumber numberWithLongLong:activityToken]])
    {
      [mActivityLock unlock];
      return 0;   // Not one of our tokens
    }

    @try {
      if (mUIActivity)
      {
        size_t aToken = [mUIActivity setActivity:activityToken incrementBy:delta];
        [mActivityLock unlock];
        return aToken;
      }
    }
    @catch (NSException * e) {
      if (([e name] == NSPortTimeoutException) || ([e name] == NSInvalidReceivePortException))
      {
        [mUIActivity release];
        mUIActivity = nil;
      }
    }
    [mActivityLock unlock];
  }
  else
    NSLog(@"RSActivityProxy - setActivity:incrementBy unable to obtain lock");
  return 0;
}

- (size_t) shouldCancelActivity:(size_t)activityToken cancel:(BOOL*)cancel
{
  if ([mActivityLock lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:3]])
  {
    if (![mTokenList containsObject:[NSNumber numberWithLongLong:activityToken]])
    {
      [mActivityLock unlock];
      return 0;   // Not one of our tokens
    }
    
    @try {
      if (mUIActivity)
      {
        size_t aToken = [mUIActivity shouldCancelActivity:activityToken cancel:cancel];
        [mActivityLock unlock];
        return aToken;
      }
    }
    @catch (NSException * e) {
      if (([e name] == NSPortTimeoutException) || ([e name] == NSInvalidReceivePortException))
      {
        [mUIActivity release];
        mUIActivity = nil;
      }
    }
    if (cancel)
      *cancel = NO;
    [mActivityLock unlock];
  }
  else
    NSLog(@"RSActivityProcy - shouldCancelActivity unable to obtain lock");
  return 0;
}


@end

@implementation RSRecordingQueue

- (id) initWithTuner:(HDHomeRunTuner*)aTuner
{
  self = [super init];
  if (self != nil) {
      queue = [[NSMutableArray alloc] init];
      if (aTuner)
      {
        tuner = aTuner;
        [tuner retain];
      }
  }
  return self;
}

- (void) dealloc
{
  if ([nextRecordingStartTimer isValid])
    [nextRecordingStartTimer invalidate];
  [nextRecordingStartTimer release];
  [tuner release];
  [queue release];
  
  [super dealloc];
}

- (BOOL) addRecording:(RSRecording*)aRecording
{
  // We take the current front most item so that we can see if the new recording 'usurps it'
  RSRecording *nextRecordingDue = nil;
  if ([queue count] > 0)
    nextRecordingDue = [queue objectAtIndex:0];
    
  // The recording queue is kept sorted so that the most recent (next to be recorded) item is at the front
  if (aRecording.tuner == nil)
    aRecording.tuner = self.tuner;
  else if (aRecording.tuner != self.tuner)
  {
    NSLog(@"Attempting to add recording %@ to different tuner %@ (aRecording.tuner = %@)", aRecording, self.tuner, aRecording.tuner);
    return  NO;
  }
  [queue addObject:aRecording];
  aRecording.recordingQueue = self;
  
  NSSortDescriptor *sortDescriptor = [[[NSSortDescriptor alloc] initWithKey:@"schedule.time" ascending:YES] autorelease];
  [queue sortUsingDescriptors:[NSArray arrayWithObject:sortDescriptor]];
  
  // Sorting the array may have given us a new 'next recording due time' so compare the old vs new and update
  RSRecording *newNextRecordingDue = [queue objectAtIndex:0];
  if (newNextRecordingDue != nextRecordingDue)
  {
    // Update the timer for this queue
    if (nextRecordingStartTimer)
    {
      [nextRecordingStartTimer invalidate];
      nextRecordingStartTimer = nil;
    }
    NSDate *now = [NSDate date];
    if ([now compare:newNextRecordingDue.schedule.endTime] == NSOrderedAscending)
    {
      NSTimeInterval recordingStartTimeInterval = [newNextRecordingDue.schedule.time timeIntervalSinceNow];
      if (recordingStartTimeInterval < 0)
        recordingStartTimeInterval = 0;
      nextRecordingStartTimer = [NSTimer scheduledTimerWithTimeInterval:recordingStartTimeInterval target:self selector:@selector(startRecordingTimerFired:) userInfo:newNextRecordingDue repeats:NO];
//      [[NSRunLoop currentRunLoop] addTimer:nextRecordingStartTimer forMode:NSDefaultRunLoopMode];
    }
  }
  return YES;
}


- (BOOL) removeRecording:(RSRecording*)aRecording
{
	NSLog(@"removeRecording of %@", aRecording.schedule.program.title);
  if ([queue containsObject:aRecording])
  {
    [queue removeObjectIdenticalTo:aRecording];
		
		NSLog(@"  recording removed there are %d items still in the recording queue", [queue count]);
		// Removing this recording means that another recording on this queue could be scheduled
		if ([queue count] > 0)
		{
			NSLog(@"  nextRecordingStartTimer == %@", nextRecordingStartTimer);
				if (nextRecordingStartTimer == nil)
				{
					NSTimeInterval recordingStartTimeInterval = [[[queue objectAtIndex:0] schedule].time timeIntervalSinceNow];
					if (recordingStartTimeInterval < 0)
						recordingStartTimeInterval = 0;
					nextRecordingStartTimer = [NSTimer scheduledTimerWithTimeInterval:recordingStartTimeInterval target:self selector:@selector(startRecordingTimerFired:) userInfo:[queue objectAtIndex:0] repeats:NO];
					NSLog(@"  created new nextRecordingStartTimer == %@ to fire in %.2f seconds", nextRecordingStartTimer, recordingStartTimeInterval);
				}
		}
    return YES;
  }
  else
    return NO;
}


- (void) startRecordingTimerFired:(NSTimer*)aTimer
{
  RSRecording *recordingToStart = [aTimer userInfo];
  NSLog(@"RSRecordingQueue - time to start a recording of %@ on %@, %@", recordingToStart.schedule.program.title, self.tuner.longName, recordingToStart.schedule.station.callSign);
	nextRecordingStartTimer = nil;

	[recordingToStart.recordingThreadController startRecordingTimerFired:aTimer];
}

- (void) recordingComplete:(RSRecording *)recordingJustFinished
{
	NSLog(@"recordingFinishedNotification: %@ just finished recording, there are %d items in the queue", recordingJustFinished.schedule.program.title, [queue count]);
	
	// Remove this item from the queue
	[queue removeObjectIdenticalTo:recordingJustFinished];
	
	if ([queue count] > 0)
	{
		// Set up a timer for the next item in the queue
		RSRecording *nextRecordingDue = [queue objectAtIndex:0];
		NSTimeInterval nextRecordingStartTimeInterval = [nextRecordingDue.schedule.time timeIntervalSinceNow];
		
		// Make sure the new recording doesn't (somehow) start before this one ends
		if (nextRecordingStartTimeInterval < 0)
			nextRecordingStartTimeInterval = 0;

		NSLog(@"recordingFinishedNotification: another recording starts in %.2f seconds", nextRecordingStartTimeInterval);
		
		nextRecordingStartTimer = [NSTimer scheduledTimerWithTimeInterval:nextRecordingStartTimeInterval target:self selector:@selector(startRecordingTimerFired:) userInfo:nextRecordingDue repeats:NO];
	}
}

@synthesize queue;
@synthesize tuner;

@end
