//
//  recsched_bkgd_AppDeleggate.m
//  recsched
//
//  Created by Andrew Kimpton on 6/18/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import "recsched_bkgd_AppDelegate.h"
#import "RecSchedServer.h"
#import "RSRecording.h"
#import "RecordingThread.h"

NSString *kRecSchedUIAppBundleID = @"org.awkward.recsched";
NSString *kRecSchedServerBundleID = @"org.awkward.recsched-server";

NSString *kWebServicesSDUsernamePrefStr = @"SDUsername";			// Here because we don't link Preferences.m into the server

@implementation recsched_bkgd_AppDelegate

- (void) startTimersForRecordings
{
	NSArray *futureRecordings = [RSRecording fetchRecordingsInManagedObjectContext:[[NSApp delegate] managedObjectContext] afterDate:[NSDate date]];
	for (RSRecording *aRecording in futureRecordings)
	{
		[[RecordingThreadController alloc] initWithRecording:aRecording recordingServer:mRecSchedServer];
	}
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification 
{
	NSLog(@"recsched_bkgd_AppDelegate - applicationDidFinishLaunching");
#if USE_SYNCSERVICES
	[[self syncClient] setSyncAlertHandler:self selector:@selector(client:mightWantToSyncEntityNames:)];
#endif // USE_SYNCSERVICES
	
	[mRecSchedServer updateSchedule];
	[self startTimersForRecordings];
}

- (id) init {
  self = [super init];
  if (self != nil) 
  {
	// Now register the server
    NSConnection *theConnection;

    theConnection = [NSConnection defaultConnection];
    mRecSchedServer = [[RecSchedServer alloc] init];
    [theConnection setRootObject:mRecSchedServer];
    if ([theConnection registerName:kRecServerConnectionName] == NO) 
    {
            /* Handle error. */
            NSLog(@"Error registering connection");
            return nil;
    }
  }
  return self;
}

- (NSURL *)urlForPersistentStore {
	return [NSURL fileURLWithPath: [[self applicationSupportFolder] stringByAppendingPathComponent: @"recsched_bkgd.dat"]];
}

#if USE_SYNCSERVICES
- (NSURL*)urlForFastSyncStore {
	return [NSURL fileURLWithPath:[[self applicationSupportFolder] stringByAppendingPathComponent:@"org.awkward.recsched-server.fastsyncstore"]];
}

#pragma mark Sync

- (ISyncClient *)syncClient
{
    NSString *clientIdentifier = kRecSchedServerBundleID;
    NSString *reason = @"unknown error";
    ISyncClient *client;

    @try {
        client = [[ISyncManager sharedManager] clientWithIdentifier:clientIdentifier];
        if (nil == client) {
//            if (![[ISyncManager sharedManager] registerSchemaWithBundlePath:[[NSBundle mainBundle] pathForResource:@"recsched" ofType:@"syncschema"]]) {
//                reason = @"error registering the recsched sync schema";
//            } 
//			else 
			{
                client = [[ISyncManager sharedManager] registerClientWithIdentifier:clientIdentifier descriptionFilePath:[[NSBundle mainBundle] pathForResource:@"ClientDescription_Server" ofType:@"plist"]];
                [client setShouldSynchronize:YES withClientsOfType:ISyncClientTypeApplication];
                [client setShouldSynchronize:YES withClientsOfType:ISyncClientTypeDevice];
                [client setShouldSynchronize:YES withClientsOfType:ISyncClientTypeServer];
                [client setShouldSynchronize:YES withClientsOfType:ISyncClientTypePeer];
            }
        }
    }
    @catch (id exception) {
        client = nil;
        reason = [exception reason];
    }

    if (nil == client) {
        NSRunAlertPanel(@"You can not sync your recsched data.", [NSString stringWithFormat:@"Failed to register the sync client: %@", reason], @"OK", nil, nil);
    }
    
    return client;
}
#endif // USE_SYNCSERVICES

#pragma mark Actions

- (IBAction) saveAction:(id)sender {

    NSError *error = nil;
    if (![[self managedObjectContext] save:&error]) {
        [[NSApplication sharedApplication] presentError:error];
    }
}

#if USE_SYNCSERVICES
- (void)syncAction:(id)sender
{
    NSError *error = nil;
    ISyncClient *client = [self syncClient];
    if (nil != client) {
        [[[self managedObjectContext] persistentStoreCoordinator] syncWithClient:client inBackground:YES handler:self error:&error];
    }
    if (nil != error) {
        NSLog(@"syncAction - error occured - %@", error);
    }
}
#endif // USE_SYNCSERVICES

@end
