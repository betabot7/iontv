//
//  Preferences.m
//  recsched
//
//  Created by Andrew Kimpton on 1/28/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import "AKColorCell.h"
#import "Preferences.h"
#import "PreferenceKeys.h"
#import "hdhomerun.h"
#import "HDHomeRunMO.h"
#import "HDHomeRunTuner.h"
#import "recsched_AppDelegate.h"
#import "RecSchedProtocol.h"
#import "RSColorDictionary.h"
#import "HDHomeRunMO.h"
#import "Z2ITLineup.h"
#import <Security/Security.h>

#define SCAN_DISABLED 0

const float kDurationSliderMinValue = 1.0;
const float kDurationSliderMaxValue = 772.0;
const int k1HourTick = 0;   // Tick mark indices are zero based
const int k3HourTick = 2;
const int k12HoursTick = 5;
const int k24HoursTick   = 9;   // 1 day
const int k168HoursTick = 15;   // 1 week
const int k336HoursTick = 17;   // 2 weeks

NSString *kSDPreferencesToolbarIdentifier = @"SD";
NSString *kTunersPreferencesToolbarIdentifier = @"Tuners";
NSString *kChannelsPreferencesToolbarIdentifier = @"Channels";
NSString *kColorsPreferencesToolbarIdentifier = @"Colors";
NSString *kStorageTranscodingToolbarIdentifier = @"StorageTranscoding";
NSString *kAdvancedIdentifier = @"Advanced";
NSString *kSchedulesDirectURL = @"http://schedulesdirect.org/signup";

struct discreteSliderMarks
{
  int tickMark;
  float timeValue;
};

const int kNumberDurationSliderTicks = 6;
struct discreteSliderMarks kDownloadDurationSliderMarks[] = { {0, 1.0}, {2, 3.0}, {5, 12.0}, {9, 24.0}, {15, 168.0}, {17, 336} };

// All NSToolbarItems have a unique identifer associated with them, used to tell your delegate/controller what 
// toolbar items to initialize and return at various points.  Typically, for a given identifier, you need to 
// generate a copy of your "master" toolbar item, and return it autoreleased.  The function below takes an
// NSMutableDictionary to hold your master NSToolbarItems and a bunch of NSToolbarItem paramenters,
// and it creates a new NSToolbarItem with those parameters, adding it to the dictionary.  Then the dictionary
// can be used from -toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar: to generate a new copy of the 
// requested NSToolbarItem (when the toolbar wants to redraw, for instance) by simply duplicating and returning
// the NSToolbarItem that has the same identifier in the dictionary.  Plus, it's easy to call this function
// repeatedly to generate lots of NSToolbarItems for your toolbar.
// -------
// label, palettelabel, toolTip, action, and menu can all be NULL, depending upon what you want the item to do
static void addToolbarItem(NSMutableDictionary *theDict,NSString *identifier,NSString *label,NSString *paletteLabel,NSString *toolTip,id target,SEL settingSelector, id itemContent,SEL action, NSMenu * menu)
{
    NSMenuItem *mItem;
    // here we create the NSToolbarItem and setup its attributes in line with the parameters
    NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];
    [item setLabel:label];
    [item setPaletteLabel:paletteLabel];
    [item setToolTip:toolTip];
    [item setTarget:target];
    // the settingSelector parameter can either be @selector(setView:) or @selector(setImage:).  Pass in the right
    // one depending upon whether your NSToolbarItem will have a custom view or an image, respectively
    // (in the itemContent parameter).  Then this next line will do the right thing automatically.
    [item performSelector:settingSelector withObject:itemContent];
    [item setAction:action];
    // If this NSToolbarItem is supposed to have a menu "form representation" associated with it (for text-only mode),
    // we set it up here.  Actually, you have to hand an NSMenuItem (not a complete NSMenu) to the toolbar item,
    // so we create a dummy NSMenuItem that has our real menu as a submenu.
    if (menu!=NULL)
    {
		// we actually need an NSMenuItem here, so we construct one
		mItem=[[[NSMenuItem alloc] init] autorelease];
		[mItem setSubmenu: menu];
		[mItem setTitle: [menu title]];
		[item setMenuFormRepresentation:mItem];
    }
    // Now that we've setup all the settings for this new toolbar item, we add it to the dictionary.
    // The dictionary retains the toolbar item for us, which is why we could autorelease it when we created
    // it (above).
    [theDict setObject:item forKey:identifier];
}


@implementation Preferences

@synthesize recordedProgramsLocation;
@synthesize transcodedProgramsLocation;
@synthesize handbrakePresetsArrayController;

static Preferences *sSharedInstance = nil;

+ (Preferences *)sharedInstance {
    return sSharedInstance ? sSharedInstance : [[self alloc] init];
}

+ (void)setupDefaults
{
    NSString *userDefaultsValuesPath;
    NSDictionary *userDefaultsValuesDict;
    NSDictionary *initialValuesDict;
    NSArray *resettableUserDefaultsKeys;
    
    // load the default values for the user defaults
    userDefaultsValuesPath=[[NSBundle mainBundle] pathForResource:@"UserDefaults" 
                               ofType:@"plist"];
    userDefaultsValuesDict=[NSDictionary dictionaryWithContentsOfFile:userDefaultsValuesPath];
    
	// Set up the default location for the recorded (and transcoded) programs location.
	NSString *homeDir = NSHomeDirectory();
	NSString *moviesDir = [homeDir stringByAppendingPathComponent:@"Movies"];
	NSURL *moviesFolderURL = [[NSURL alloc] initFileURLWithPath:moviesDir isDirectory:YES];
	NSString *moviesFolder = [moviesFolderURL absoluteString];
	[userDefaultsValuesDict setValue:moviesFolder forKey:kRecordedProgramsLocationKey];
	[userDefaultsValuesDict setValue:moviesFolder forKey:kTranscodedProgramsLocationKey];

    // set them in the standard user defaults
    [[NSUserDefaults standardUserDefaults] registerDefaults:userDefaultsValuesDict];
    
    // if your application supports resetting a subset of the defaults to 
    // factory values, you should set those values 
    // in the shared user defaults controller
    resettableUserDefaultsKeys=[NSArray arrayWithObjects:kScheduleDownloadDurationKey, kWebServicesSDUsernameKey, nil];
    initialValuesDict=[userDefaultsValuesDict dictionaryWithValuesForKeys:resettableUserDefaultsKeys];
    
    // Set the initial values in the shared user defaults controller 
    [[NSUserDefaultsController sharedUserDefaultsController] setInitialValues:initialValuesDict];
}

- (id)init
{
    if (sSharedInstance)
    {		// We just have one instance of the Preferences class, return that one instead
        [self release];
    }
    else if (self = [super init])
    {
		[Preferences setupDefaults];
        sSharedInstance = self;
        [[NSUserDefaultsController sharedUserDefaultsController] addObserver:self forKeyPath:@"values.scheduleDownloadDuration" options:NSKeyValueObservingOptionNew context:nil];
        [[NSUserDefaultsController sharedUserDefaultsController] setAppliesImmediately:NO];
		
		// Build the list of handbrake presets
		NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
		NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : NSTemporaryDirectory();
		NSString *presetsPath = [basePath stringByAppendingPathComponent:@"HandBrake/UserPresets.plist"];
		
		handbrakePresetsArrayController = [[NSArrayController alloc] initWithContent:[NSArray arrayWithContentsOfFile:presetsPath]];
		[handbrakePresetsArrayController setObjectClass:[NSMutableDictionary class]];
    }
    return sSharedInstance;
}

- (void)dealloc
{
    if (self != sSharedInstance)
    {
      [super dealloc];	// Don't free the shared instance
	  [recordedProgramsLocation release];
	  [transcodedProgramsLocation release];
	  [handbrakePresetsArrayController release];
    }
}

- (NSManagedObjectContext *)managedObjectContext
{
	return [[[NSApplication sharedApplication] delegate] managedObjectContext];
}

- (void) showPrefsView:(NSView*)inViewToBeShown
{
	if (mCurrentPrefsView == inViewToBeShown)
		return;	// Nothing to do - we're already showing the right view
		
	// Get the containers current size
	NSSize sizeChange;
	sizeChange.width = [inViewToBeShown frame].size.width - [mPrefsContainerView frame].size.width ;
	sizeChange.height = [inViewToBeShown frame].size.height - [mPrefsContainerView frame].size.height;
	
	// Animate the window to the new size (and location - remember the co-ordinate system is zero,zero bottom left
	// so we have to move the top of the window as well as changing it's size)
	NSRect newFrame = [mPanel frame];
	newFrame.size.height += sizeChange.height;
	newFrame.size.width += sizeChange.width;
	newFrame.origin.y -= sizeChange.height;

	[mPanel setFrame:newFrame display:YES animate:YES];

	if (mCurrentPrefsView)
	{
		[mPrefsContainerView replaceSubview:mCurrentPrefsView with:inViewToBeShown];
	}
	else
		[mPrefsContainerView addSubview:inViewToBeShown];
	
	mCurrentPrefsView = inViewToBeShown;
	[inViewToBeShown setFrameOrigin:NSMakePoint(0,0)];
	[inViewToBeShown setNeedsDisplay:YES];
	[mPrefsContainerView setFrameSize:[inViewToBeShown frame].size];
}

// When we launch, we have to get our NSToolbar set up.  This involves creating a new one, adding the NSToolbarItems,
// and installing the toolbar in our window.
-(void)awakeFromNib
{
//    NSFont *theFont;
    NSToolbar *toolbar=[[[NSToolbar alloc] initWithIdentifier:@"myToolbar"] autorelease];
    
    // Here we create the dictionary to hold all of our "master" NSToolbarItems.
    mToolbarItems=[[NSMutableDictionary dictionary] retain];

    // often using an image will be your standard case.  You'll notice that a selector is passed
    // for the action (blueText:), which will be called when the image-containing toolbar item is clicked.
    addToolbarItem(mToolbarItems,kSDPreferencesToolbarIdentifier,@"SchedulesDirect",@"SchedulesDirect",@"SchedulesDirect User ID & Schedule",self,@selector(setImage:), [NSImage imageNamed:NSImageNameUserAccounts],@selector(showSDPrefs:),NULL);
    addToolbarItem(mToolbarItems,kTunersPreferencesToolbarIdentifier,@"Tuner",@"Tuner",@"Tuner Selection",self,@selector(setImage:), nil /* image */,@selector(showTunerPrefs:),NULL);
    addToolbarItem(mToolbarItems,kChannelsPreferencesToolbarIdentifier,@"Channels",@"Channels",@"Customize Channels you recieve",self,@selector(setImage:), nil /* image */,@selector(showChannelPrefs:),NULL);
    addToolbarItem(mToolbarItems,kColorsPreferencesToolbarIdentifier,@"Colors",@"Colors",@"Colors for program genres",self,@selector(setImage:), [NSImage imageNamed:NSImageNameColorPanel], @selector(showColorPrefs:),NULL);
    addToolbarItem(mToolbarItems,kStorageTranscodingToolbarIdentifier,@"Storage and Conversion",@"Storage and Conversion",@"Customize where programs are stored and how they are converted.",self,@selector(setImage:), [NSImage imageNamed:@"HardDrive.tiff"],@selector(showStorageTranscodingPrefs:),NULL);
    addToolbarItem(mToolbarItems,kAdvancedIdentifier,@"Advanced",@"Advanced",@"Advanced Preferences.",self,@selector(setImage:), [NSImage imageNamed:NSImageNameAdvanced],@selector(showAdvancedPrefs:),NULL);
     
    // the toolbar wants to know who is going to handle processing of NSToolbarItems for it.  This controller will.
    [toolbar setDelegate:self];
    // If you pass NO here, you turn off the customization palette.  The palette is normally handled automatically
    // for you by NSWindow's -runToolbarCustomizationPalette: method; you'll notice that the "Customize Toolbar"
    // menu item is hooked up to that method in Interface Builder.  Interface Builder currently doesn't automatically 
    // show this action (or the -toggleToolbarShown: action) for First Responder/NSWindow (this is a bug), so you 
    // have to manually add those methods to the First Responder in Interface Builder (by hitting return on the First Responder and 
    // adding the new actions in the usual way) if you want to wire up menus to them.
    [toolbar setAllowsUserCustomization:NO];

    // tell the toolbar that it should save any configuration changes to user defaults.  ie. mode changes, or reordering will persist. 
    // specifically they will be written in the app domain using the toolbar identifier as the key. 
    [toolbar setAutosavesConfiguration: YES]; 
    
    // tell the toolbar to show icons only by default
    [toolbar setDisplayMode: NSToolbarDisplayModeIconAndLabel];
	
	// Start with the SchedulesDirect prefs
	[toolbar setSelectedItemIdentifier:kSDPreferencesToolbarIdentifier];
	[self showPrefsView:mSDPrefsView];
	
    // install the toolbar.
    [mPanel setToolbar:toolbar];
    
	// Set the sort order for the colors list
	NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"numberOfPrograms" ascending:NO];
	[mGenreArrayController setSortDescriptors:[NSArray arrayWithObject:sortDescriptor]];
	[sortDescriptor release];
	
	// Set the custom cell for the colors table
	AKColorCell *aColorCell = [[[AKColorCell alloc] init] autorelease];	// create the special color well cell
    [aColorCell setEditable: YES];						// allow user to change the color
	[aColorCell setTarget: self];						// set colorClick as the method to call
	[aColorCell setAction: @selector (colorClickAction:)];		// when the color well is clicked on
	[[[mColorsTable tableColumns] objectAtIndex:1] setDataCell: aColorCell];					// sets the columns cell to the color well cell
}

- (void)showPanel:(id)sender
{
    if (!mPanel) {
        if (![NSBundle loadNibNamed:@"Preferences" owner:self]) 
        {
            NSLog(@"Failed to load Preferences.nib");
            NSBeep();
            return;
        }
	[mPanel setHidesOnDeactivate:NO];
	[mPanel setExcludedFromWindowsMenu:YES];
	[mPanel setMenu:nil];
        [mPanel center];
    }
    [self updateUI];
    [mPanel makeKeyAndOrderFront:nil];
}

- (void)updateUI
{
  [mDurationTextField setHidden:YES];
        
        // Now update the slider position for the default value
        float currDuration = [[[[NSUserDefaultsController sharedUserDefaultsController] values] valueForKey:kScheduleDownloadDurationKey] floatValue];
        float newSliderValue = 0.0;
        int i=0;
        for (i=1; i < kNumberDurationSliderTicks; i++)
        {
          if (currDuration <= kDownloadDurationSliderMarks[i].timeValue)
          {
            newSliderValue = (currDuration - kDownloadDurationSliderMarks[i-1].timeValue)  / 
              ( kDownloadDurationSliderMarks[i].timeValue - kDownloadDurationSliderMarks[i-1].timeValue) 
              * ([mDurationSlider tickMarkValueAtIndex:kDownloadDurationSliderMarks[i].tickMark] - [mDurationSlider tickMarkValueAtIndex:kDownloadDurationSliderMarks[i-1].tickMark])
                + [mDurationSlider tickMarkValueAtIndex:kDownloadDurationSliderMarks[i-1].tickMark];
            break;
          }
        }
        if (newSliderValue >= 0.0)
          [mDurationSlider setDoubleValue:newSliderValue];
          
          
    // Attempt to retrieve the Username and password fields for the SchedulesDirect site
    NSString* SDUsernameString = [[[NSUserDefaultsController sharedUserDefaultsController] values] valueForKey:kWebServicesSDUsernameKey];
    if (SDUsernameString)
    {
      [mSDUsernameField setStringValue:SDUsernameString];

      const char *serverNameUTF8 = [kWebServicesSDHostname UTF8String];
      const char *accountNameUTF8 = [SDUsernameString UTF8String];
      const char *pathUTF8 = [kWebServicesSDPath UTF8String];
      UInt32 passwordLength;
      void *passwordData;
      OSStatus status = SecKeychainFindInternetPassword(NULL,strlen(serverNameUTF8),serverNameUTF8, 0, NULL, strlen(accountNameUTF8), accountNameUTF8, strlen(pathUTF8), pathUTF8, 80, kSecProtocolTypeHTTP, kSecAuthenticationTypeDefault, &passwordLength, &passwordData, &mSDKeychainItemRef);
      
      if (status == noErr)
      {
		NSString *passwordString = [NSString stringWithCString:passwordData length:passwordLength];
        [mSDPasswordField setStringValue:passwordString];
        SecKeychainItemFreeContent(NULL, passwordData);
      }
    }
	
	self.recordedProgramsLocation = [[NSURL alloc] initWithString:[[NSUserDefaults standardUserDefaults] valueForKey:kRecordedProgramsLocationKey]];
	self.transcodedProgramsLocation = [[NSURL alloc] initWithString:[[NSUserDefaults standardUserDefaults] valueForKey:kTranscodedProgramsLocationKey]];
}

- (void) updateDurationLabel
{
  float newDuration = [[[[NSUserDefaultsController sharedUserDefaultsController] values] valueForKey:kScheduleDownloadDurationKey] floatValue];
  if (newDuration < 24.0)
    [mDurationTextField setStringValue:[NSString stringWithFormat:@"%d Hours", (int)(newDuration + 0.5f)]];
  else if (newDuration < 169)
    [mDurationTextField setStringValue:[NSString stringWithFormat:@"%d Days", (int)((newDuration / 24.0f) + 0.5f)]];
  else
    [mDurationTextField setStringValue:[NSString stringWithFormat:@"%.1f Weeks", (newDuration / 168.0f)]];
}

- (IBAction) durationSliderChanged:(NSSlider *)inSlider
{
  float newSliderValue = [inSlider floatValue];
  float newDuration = 1.0f;
  int i=0;
  
  // Run through the list of tick marks and time values scale the duration between the nearest two tick marks.
  for (i=1; i < kNumberDurationSliderTicks; i++)
  {
    if (newSliderValue <= [inSlider tickMarkValueAtIndex:kDownloadDurationSliderMarks[i].tickMark])
    {
        newDuration = kDownloadDurationSliderMarks[i-1].timeValue + (newSliderValue - [inSlider tickMarkValueAtIndex:kDownloadDurationSliderMarks[i-1].tickMark]) / ([inSlider tickMarkValueAtIndex:kDownloadDurationSliderMarks[i].tickMark] - [inSlider tickMarkValueAtIndex:kDownloadDurationSliderMarks[i-1].tickMark]) * (kDownloadDurationSliderMarks[i].timeValue - kDownloadDurationSliderMarks[i-1].timeValue);
        break;
    }
  }
  
  NSUserDefaultsController *theController = [NSUserDefaultsController sharedUserDefaultsController];
  [[theController values] setValue:[NSNumber numberWithFloat:newDuration] forKey:kScheduleDownloadDurationKey];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ((object == [NSUserDefaultsController sharedUserDefaultsController]) && ([keyPath isEqual:@"values.scheduleDownloadDuration"]))
    {
      [self updateDurationLabel];
    }
}

- (void) savePrefs:(id)sender
{
  NSUserDefaultsController *theDefaultsController  = [NSUserDefaultsController sharedUserDefaultsController];
  if ([mSDUsernameField stringValue])
  {
	NSUserDefaultsController *theDefaultsController  = [NSUserDefaultsController sharedUserDefaultsController];
	[[theDefaultsController values] setValue:[mSDUsernameField stringValue] forKey:kWebServicesSDUsernameKey];
    const char *serverNameUTF8 = [kWebServicesSDHostname UTF8String];
    const char *accountNameUTF8 = [[mSDUsernameField stringValue] UTF8String];
    const char *pathUTF8 = [kWebServicesSDPath UTF8String];
    UInt32 passwordLength;
    const void *passwordData;

	NSString *passwordString = [mSDPasswordField stringValue];
	passwordData = [passwordString UTF8String];
	passwordLength = strlen(passwordData);
    
    // Call AddInternetPassword - if it's already in the keychain then update it
    OSStatus status;
    if (mSDKeychainItemRef == nil)
    {
      status = SecKeychainAddInternetPassword(NULL, strlen(serverNameUTF8), serverNameUTF8,0 , NULL, strlen(accountNameUTF8), accountNameUTF8, strlen(pathUTF8), pathUTF8, 80, kSecProtocolTypeHTTP, kSecAuthenticationTypeDefault, passwordLength, passwordData, &mSDKeychainItemRef);
    }
    else
    {
      // The item already exists - we just need to change the password.
      // And the Account name
      void *accountNameAttributeData = malloc(strlen([[mSDUsernameField stringValue] UTF8String]));
      memcpy(accountNameAttributeData, [[mSDUsernameField stringValue] UTF8String], strlen([[mSDUsernameField stringValue] UTF8String]));
      
      SecKeychainAttribute accountNameAttribute;
      accountNameAttribute.tag = kSecAccountItemAttr;
      accountNameAttribute.data = accountNameAttributeData;
      accountNameAttribute.length = strlen([[mSDUsernameField stringValue] UTF8String]);
      SecKeychainAttributeList attrList;
      attrList.count = 1;
      attrList.attr = &accountNameAttribute;
      status = SecKeychainItemModifyAttributesAndData(mSDKeychainItemRef, &attrList, passwordLength, passwordData);
      free(accountNameAttributeData);
	}
  }
  
  [[theDefaultsController values] setValue:[recordedProgramsLocation absoluteString] forKey:kRecordedProgramsLocationKey];
  [[theDefaultsController values] setValue:[transcodedProgramsLocation absoluteString] forKey:kTranscodedProgramsLocationKey];
  [theDefaultsController save:sender];
}

- (NSArray *) z2itStationSortDescriptors
{
  NSSortDescriptor* callSignDescriptor = [[[NSSortDescriptor alloc] initWithKey:@"callSign" ascending:YES] autorelease];
  NSArray* sortDescriptors = [NSArray arrayWithObject:callSignDescriptor];

  return sortDescriptors;
}

- (void) pushHDHomeRunStationsOnTuner:(HDHomeRunTuner *)inTuner 
{ 
	if ([[NSApp delegate] recServer]) 
	{ 
		// Start by adding all the channels on this tuner to an array 
		NSMutableSet *channelsSet = [inTuner mutableSetValueForKey:@"channels"]; 

		// Create an array to hold the dictionaries of channel info 
		NSMutableArray *channelsOnTuner = [NSMutableArray arrayWithCapacity:[channelsSet count]]; 

		// Ask each HDHomeRunChannel in the set to add their info (in dictionary form) to the array 
		[channelsSet makeObjectsPerformSelector:@selector(addChannelInfoDictionaryTo:) withObject:channelsOnTuner]; 

		NSSortDescriptor *channelDescriptor =[[[NSSortDescriptor alloc] initWithKey:@"channelNumber" ascending:YES] autorelease]; 
		NSArray *sortDescriptors=[NSArray arrayWithObject:channelDescriptor]; 
		NSArray *sortedArray=[channelsOnTuner sortedArrayUsingDescriptors:sortDescriptors]; 

		[[[NSApp delegate] recServer] setHDHomeRunChannelsAndStations:sortedArray onDeviceID:[[[inTuner device] deviceID] intValue] forTunerIndex:[[inTuner index] intValue]]; 
	} 
}
	
#pragma mark Action Methods

- (void) showSDPrefs:(id)sender
{
	[self showPrefsView:mSDPrefsView];
}

- (void) showTunerPrefs:(id)sender
{
	[self showPrefsView:mTunerPrefsView];
}

- (void) showChannelPrefs:(id)sender
{
	[self showPrefsView:mChannelPrefsView];
}

- (void) showColorPrefs:(id)sender
{
	[self showPrefsView:mColorPrefsView];
}

- (void) showStorageTranscodingPrefs:(id)sender
{
	[self showPrefsView:mStorageTranscodingPrefsView];
}

- (void) showAdvancedPrefs:(id)sender
{
	[self showPrefsView:mAdvancedPrefsView];
}

- (IBAction) okButtonAction:(id)sender
{
  if (mChannelScanInProgress)
    mAbortChannelScan = YES;
    
  [self savePrefs:sender];
  [mPanel orderOut:sender];
  
#if USE_SYNCSERVICES
  // The CoreData store might have changes because of editting the tuner settings and channel map.
  if ([[[[NSApplication sharedApplication] delegate] managedObjectContext] hasChanges])
	[[[NSApplication sharedApplication] delegate] saveAction:nil];
#else
	
	// Walk the list of HDHomeRunDevices and send the details to the server
	NSArray *hdhomerunDevices = [mHDHomeRunDevicesArrayController arrangedObjects];
	for (HDHomeRun *anHDHomeRunDevice in hdhomerunDevices)
	{
		[[[NSApp delegate] recServer] setHDHomeRunDeviceWithID:[anHDHomeRunDevice deviceID]
			nameTo:[anHDHomeRunDevice name]
			tuner0LineupIDTo:[[[anHDHomeRunDevice tuner0] lineup] lineupID]
			tuner1LineupIDTo:[[[anHDHomeRunDevice tuner1] lineup] lineupID]];
	}
#endif // USE_SYNCSERVICES
}

- (IBAction) cancelButtonAction:(id)sender
{
  if (mChannelScanInProgress)
    mAbortChannelScan = YES;

  [[NSUserDefaultsController sharedUserDefaultsController] revert:sender];
	[mPanel orderOut:sender];
}

- (IBAction) getAccountButtonAction:(id)sender
{
  [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:kSchedulesDirectURL]];
}

- (IBAction) retrieveLineupsButtonAction:(id)sender
{
  [self savePrefs:sender];
  
  [mParsingProgressIndicator setIndeterminate:YES];
  [mParsingProgressIndicator startAnimation:self];
  [mParsingProgressIndicator setHidden:NO];
  [mRetrieveLineupsButton setEnabled:NO];

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
  
	// Register for the complete notification
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(parsingCompleteNotification:) name:RSParsingCompleteNotification object:[NSApp delegate]];
	
 	// Send the message to the background server
	NSDictionary *callData = [[NSDictionary alloc] initWithObjectsAndKeys:startDateStr, @"startDateStr", endDateStr, @"endDateStr", [NSNumber numberWithBool:YES], @"lineupsOnly", nil /* really needs to be a DO port or similar */, @"dataRecipient", nil];
	[[[NSApp delegate] recServer] performDownload:callData];
}

- (IBAction) scanDevicesButtonAction:(id)sender
{
	[mScanTunersButton setEnabled:NO];
	[mTunerScanProgressIndicator setHidden:NO];
	[mTunerScanProgressIndicator startAnimation:sender];
	
#if SCAN_DISABLED
	int count = 1;
	struct hdhomerun_discover_device_t result_list[1];
	result_list[0].device_id = 0x10100B88;
#else
	struct hdhomerun_discover_device_t result_list[64];
	int count = hdhomerun_discover_find_devices(HDHOMERUN_DEVICE_TYPE_TUNER, result_list, 64);
#endif
	
	[mTunerScanProgressIndicator stopAnimation:sender];
	[mTunerScanProgressIndicator setHidden:YES];

	if (count > 0)
	{
		int i=0;
		BOOL devicesAdded = NO;
		for (i=0; i < count; i++)
		{
			// Send a message to the background server to get it to create a matching Device
			if ([[[NSApp delegate] recServer] addHDHomeRunWithID:[NSNumber numberWithInt:result_list[i].device_id]])
				devicesAdded = YES;

			// See if an entry already exists
			HDHomeRun *anHDHomeRun = [HDHomeRun fetchHDHomeRunWithID:[NSNumber numberWithInt:result_list[i].device_id] inManagedObjectContext:[[[NSApplication sharedApplication] delegate] managedObjectContext]];
			if (!anHDHomeRun)
			{
			  // Otherwise we just create a new one
			  [HDHomeRun createHDHomeRunWithID:[NSNumber numberWithInt:result_list[i].device_id] inManagedObjectContext:[[[NSApplication sharedApplication] delegate] managedObjectContext]];
			}
		}
	}
	
	[mScanTunersButton setEnabled:YES];
}

- (void)scanChannelsConfirmationSheetDidEnd:(NSAlert *)alert returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
  [[alert window] orderOut:self];

  HDHomeRunTuner *aTuner =  (HDHomeRunTuner *)contextInfo;
  
  if (returnCode == NSAlertFirstButtonReturn)
  {

      mAbortChannelScan = NO;
      mChannelScanInProgress = YES;
      
      [mScanChannelsButton setTitle:@"Stop"];

      [mChannelScanProgressIndicator setHidden:NO];
      [mChannelScanProgressIndicator setDoubleValue:0];
	
      [aTuner scanActionReportingProgressTo:self];
  }
}

- (IBAction) scanChannelsButtonAction:(id)sender
{
  HDHomeRunTuner *aTuner =  [[mHDHomeRunTunersArrayController selectedObjects] objectAtIndex:0];

  if (mChannelScanInProgress)
  {
    mAbortChannelScan = YES;
  }
  else if (aTuner)
  {
      // Scanning can be a very lengthy process (and resets the list of current channels/stations) so put up a sheet to confirm
      NSAlert *scanningAlert = [[NSAlert alloc] init];
      [scanningAlert setMessageText:@"Do you wish to scan?"];
      [scanningAlert setInformativeText:@"Scanning can take up to 15 minutes - though it can be aborted. Scanning will also clear your current list of stations"];
      [scanningAlert addButtonWithTitle:@"Scan"];
      [scanningAlert addButtonWithTitle:@"Cancel"];
      [scanningAlert setAlertStyle:NSInformationalAlertStyle];

      [scanningAlert beginSheetModalForWindow:mPanel modalDelegate:self
        didEndSelector:@selector(scanChannelsConfirmationSheetDidEnd: returnCode: contextInfo:)
        contextInfo:aTuner];
  }
}

- (IBAction) viewHDHRStation:(id)sender
{
  HDHomeRunStation *selectedStation = [[mVisibleStationsArrayController selectedObjects] objectAtIndex:0];
  NSLog(@"viewHDHRStation selection = %@", [selectedStation callSign]);
  [[[NSApplication sharedApplication] delegate] launchVLCAction:sender withParentWindow:mPanel startStreaming:selectedStation];
}

- (IBAction) exportHDHomeRunChannelMap:(id)sender
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docPath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;

	NSSavePanel *aSavePanel = [NSSavePanel savePanel];
	[aSavePanel setAccessoryView:mExportChannelTunerSelectionView];
	[aSavePanel setRequiredFileType:@"xml"];
	[aSavePanel beginSheetForDirectory:docPath file:nil modalForWindow:mPanel modalDelegate:self didEndSelector:@selector(exportChannelPanelDidEnd: returnCode: contextInfo:)  contextInfo:nil];
}

- (IBAction) importHDHomeRunChannelMap:(id)sender
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docPath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;

	NSOpenPanel *anOpenPanel = [NSOpenPanel openPanel];
	[anOpenPanel setAccessoryView:mExportChannelTunerSelectionView];
	[anOpenPanel beginSheetForDirectory:docPath file:nil types:[NSArray arrayWithObject:@"xml"] modalForWindow:mPanel modalDelegate:self didEndSelector:@selector(importChannelPanelDidEnd: returnCode: contextInfo:) contextInfo:nil];
} 

- (void) colorClickAction: (id) sender {	// sender is the table view
	NSColorPanel* panel;				// shared color panel

	panel = [NSColorPanel sharedColorPanel];
	[panel setTarget: self];			// send the color changed messages to colorChanged
	[panel setAction: @selector (colorChangedAction:)];
//	[panel setShowsAlpha: YES];			// per ber to show the opacity slider
	NSData *colorData = [[[mGenreArrayController selectedObjects] objectAtIndex: 0] valueForKeyPath:@"genreClass.color"];
	if (colorData)
		[panel setColor: [NSUnarchiver unarchiveObjectWithData:colorData]];	// set the starting color
	[panel makeKeyAndOrderFront: self];	// show the panel
}

- (void) colorChangedAction: (id) sender {	// sender is the NSColorPanel

	[[[mGenreArrayController selectedObjects] objectAtIndex: 0] setValue:[NSArchiver archivedDataWithRootObject:[sender color]] forKeyPath:@"genreClass.color"];
}

- (IBAction)setPathAction:(id)sender
{
	NSURL *startingDirectory = nil;
	if ([sender tag] == 1)
		startingDirectory = [self recordedProgramsLocation];
	else if ([sender tag] == 2)
		startingDirectory = [self transcodedProgramsLocation];
		
	NSOpenPanel* panel = [NSOpenPanel openPanel];
	[panel setAllowsMultipleSelection:NO];
	[panel setCanChooseDirectories:YES];
	[panel setCanChooseFiles:NO];
	[panel setResolvesAliases:YES];
	[panel setTitle:@"Choose an output location"];
	[panel setPrompt:@"Choose"];
	
	[panel beginSheetForDirectory:[startingDirectory path] file:nil types:nil modalForWindow:mPanel
		   modalDelegate:self
		   didEndSelector:@selector(setPathPanelDidEnd:returnCode:contextInfo:)
		   contextInfo:sender];
}

#pragma mark Channel Scan Progress Display Protocol

- (void) incrementChannelScanProgress
{
  [mChannelScanProgressIndicator incrementBy:1.0];
}

- (BOOL) abortChannelScan
{
  return mAbortChannelScan;
}

- (void) scanCompletedOnTuner:(HDHomeRunTuner*)inTuner
{
	mChannelScanInProgress = NO;
	[mScanChannelsButton setTitle:@"Scan"];
	[mChannelScanProgressIndicator setHidden:YES];

	[self pushHDHomeRunStationsOnTuner:inTuner];
}

#pragma mark Callback & Notification Methods

- (void) parsingCompleteNotification:(NSNotification *)aNotification
{
  [mParsingProgressIndicator setHidden:YES];
  [mRetrieveLineupsButton setEnabled:YES];
  
  [[NSNotificationCenter defaultCenter] removeObserver:self name:RSParsingCompleteNotification object:[NSApp delegate]];
}

#pragma mark Open/Save Panel Delegate Methods

- (void)exportChannelPanelDidEnd:(NSSavePanel *)panel returnCode:(int)returnCode  contextInfo:(void  *)contextInfo
{
	if (returnCode == NSOKButton)
	{
		// Send the selected tuner an export message with the destination file
		if ([[mHDHomeRunTunersArrayController selectedObjects] count] == 1)
			[[[mHDHomeRunTunersArrayController selectedObjects] objectAtIndex:0] exportChannelMapTo:[panel URL]];
	}
}

- (void)importChannelPanelDidEnd:(NSOpenPanel *)panel returnCode:(int)returnCode  contextInfo:(void  *)contextInfo
{
	if (returnCode == NSOKButton)
	{
		// Send the selected tuner an import message with the source file
		if ([[mHDHomeRunTunersArrayController selectedObjects] count] == 1)
		{
			[panel orderOut:self];
			NSAlert *confirmAlert = [NSAlert alertWithMessageText:@"Continue with Import?" 
				defaultButton:nil /*OK*/ alternateButton:@"Cancel" otherButton:nil
				informativeTextWithFormat:@"Importing channels will clear all channels currently present on Tuner: %@", [[[mHDHomeRunTunersArrayController selectedObjects] objectAtIndex:0] longName]];
			[confirmAlert beginSheetModalForWindow:mPanel modalDelegate:self didEndSelector:@selector(confirmImportAlertDidEnd: returnCode: contextInfo:) contextInfo:[[panel URL] copy]];
		}
	}
}

- (void) confirmImportAlertDidEnd:(NSAlert *)alert returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	NSURL *importURL = (NSURL*)contextInfo;
	if (returnCode == NSAlertDefaultReturn)
	{
		[[[mHDHomeRunTunersArrayController selectedObjects] objectAtIndex:0] importChannelMapFrom:importURL];
		[self pushHDHomeRunStationsOnTuner:[[mHDHomeRunTunersArrayController selectedObjects] objectAtIndex:0]];
	}
	[importURL release];	// Copied in the file open panel did end delegate
}

- (void)setPathPanelDidEnd:(NSOpenPanel*)panel returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	// hide the open panel
	[panel orderOut:self];
	
	// if the return code wasn't ok, don't do anything.
	if (returnCode != NSOKButton)
		return;
	
	// get the single URL
	NSArray* paths = [panel URLs];
	NSURL* url = [paths objectAtIndex: 0];
	if ([(id)contextInfo tag] == 1)
		self.recordedProgramsLocation = url;
	else if ([(id)contextInfo tag] == 2)
		self.transcodedProgramsLocation = url;
}

#pragma mark - Toolbar Delegates

// This method is required of NSToolbar delegates.  It takes an identifier, and returns the matching NSToolbarItem.
// It also takes a parameter telling whether this toolbar item is going into an actual toolbar, or whether it's
// going to be displayed in a customization palette.
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag
{
    // We create and autorelease a new NSToolbarItem, and then go through the process of setting up its
    // attributes from the master toolbar item matching that identifier in our dictionary of items.
    NSToolbarItem *newItem = [[[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier] autorelease];
    NSToolbarItem *item=[mToolbarItems objectForKey:itemIdentifier];
    
    [newItem setLabel:[item label]];
    [newItem setPaletteLabel:[item paletteLabel]];
    if ([item view]!=NULL)
    {
		[newItem setView:[item view]];
    }
    else
    {
		[newItem setImage:[item image]];
    }
    [newItem setToolTip:[item toolTip]];
    [newItem setTarget:[item target]];
    [newItem setAction:[item action]];
    [newItem setMenuFormRepresentation:[item menuFormRepresentation]];
    // If we have a custom view, we *have* to set the min/max size - otherwise, it'll default to 0,0 and the custom
    // view won't show up at all!  This doesn't affect toolbar items with images, however.
    if ([newItem view]!=NULL)
    {
		[newItem setMinSize:[[item view] bounds].size];
		[newItem setMaxSize:[[item view] bounds].size];
    }

    return newItem;
}

// This method is required of NSToolbar delegates.  It returns an array holding identifiers for the default
// set of toolbar items.  It can also be called by the customization palette to display the default toolbar.    
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar
{
    return [NSArray arrayWithObjects:kSDPreferencesToolbarIdentifier, kColorsPreferencesToolbarIdentifier, kTunersPreferencesToolbarIdentifier, kChannelsPreferencesToolbarIdentifier, kStorageTranscodingToolbarIdentifier, kAdvancedIdentifier, nil];
}

// This method is required of NSToolbar delegates.  It returns an array holding identifiers for all allowed
// toolbar items in this toolbar.  Any not listed here will not be available in the customization palette.
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar
{
    return [NSArray arrayWithObjects:kSDPreferencesToolbarIdentifier, kColorsPreferencesToolbarIdentifier, kTunersPreferencesToolbarIdentifier, kChannelsPreferencesToolbarIdentifier, kStorageTranscodingToolbarIdentifier, kAdvancedIdentifier, NSToolbarSeparatorItemIdentifier, NSToolbarSpaceItemIdentifier,NSToolbarFlexibleSpaceItemIdentifier,nil];
}

- (NSArray *)toolbarSelectableItemIdentifiers:(NSToolbar *)toolbar
{
    return [NSArray arrayWithObjects:kSDPreferencesToolbarIdentifier, kColorsPreferencesToolbarIdentifier, kTunersPreferencesToolbarIdentifier, kChannelsPreferencesToolbarIdentifier, kStorageTranscodingToolbarIdentifier, kAdvancedIdentifier, nil];
}

@end
