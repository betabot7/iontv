// libRecSchedCommon - Common code shared between UI application and background server
// Copyright (C) 2007 Andrew Kimpton
//
// This library is free software; you can redistribute it and/or
// modify it under the terms of the GNU Lesser General Public
// License as published by the Free Software Foundation; either
// version 2.1 of the License, or (at your option) any later version.
//
// This library is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
// Lesser General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public
// License along with this library; if not, write to the Free Software
// Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA

#import "Z2ITSchedule.h"
#import "Z2ITProgram.h"

@implementation Z2ITSchedule

+ (void) clearAllSchedulesInManagedObjectContext:(NSManagedObjectContext *)inMOC
{
  NSFetchRequest *fetchRequest = [[[NSFetchRequest alloc] init] autorelease];
  [fetchRequest setEntity:
          [NSEntityDescription entityForName:@"Schedule" inManagedObjectContext:inMOC]];
   
  // Execute the fetch
  NSError *error;
  NSArray *allSchedules = [inMOC executeFetchRequest:fetchRequest error:&error];
  Z2ITSchedule *aSchedule;
  for (aSchedule in allSchedules)
  {
    [inMOC deleteObject:aSchedule];
  }
}

- (void) setDurationHours:(int)inHours minutes:(int)inMinutes
{
  NSDate *startDate = [self time];
  if (startDate == nil)
    NSLog(@"setDuration - no valid start time for program %@", [[self program] title]);
  NSDate *endDate = [self endTime];
  if (endDate != nil)
    NSLog(@"setDuration - program %@ already has an end time", [[self program] title]);
  
  endDate = [startDate addTimeInterval:(inHours * 60 * 60) + (inMinutes * 60)];
  [self setEndTime:endDate];
}

- (NSString *) partNumberString
{
  if (([self partNumber] == nil) || ([self totalNumberParts] == nil))
    return nil;
  if (([[self partNumber] intValue] == 0) || ([[self totalNumberParts] intValue] == 0))
    return nil;
    
  return [NSString stringWithFormat:@"Part %@ of %@", [self partNumber], [self totalNumberParts]];
}

- (NSString *) programDetailsStr
{
  NSString *aString = nil;
  if ([[self program] descriptionStr] != nil)
  {
    NSMutableString *detailsString = [[NSMutableString alloc] initWithString:[[self program] descriptionStr]];
    if (![self new])
    {
      [detailsString appendString:@" Repeat."];
    }
    if ([self dolby] != nil)
    {
      [detailsString appendFormat:@" %@.", [self dolby]];
    }
    if ([self subtitled])
    {
      [detailsString appendFormat:@" Subtitled."];
    }
    aString = [NSString stringWithString:detailsString];
    [detailsString release];
  }
  return aString;
}

@dynamic closeCaptioned;
@dynamic dolby;
@dynamic endTime;
@dynamic hdtv;
@dynamic new;
@dynamic partNumber;
@dynamic recordedMediaPath;
@dynamic recordingStatus;
@dynamic stereo;
@dynamic subtitled;
@dynamic time;
@dynamic totalNumberParts;
@dynamic tvRating;
@dynamic program;
@dynamic station;
@dynamic recording;
@dynamic transcoding;

- (NSString *) tvRatingImageName
{
  if ([self tvRating] == nil)
    return nil;
  else
    return [NSString stringWithFormat:@"%@.png", [self tvRating]];
}

- (NSString *) tvRatingImagePath
{
  if ([self tvRatingImageName] == nil)
    return nil;
  NSString *imagePath = [[NSBundle mainBundle] pathForImageResource:[self tvRatingImageName]];
  return imagePath;
}

@end