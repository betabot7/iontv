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

#import "AKSourceTableClasses.h"

@implementation AKSourceTableHeaderView

- (void) updateColumnHeaderCells
{
    NSArray *columns = [[self tableView] tableColumns];
    NSTableColumn *col = nil;
    
    AKSourceTableColumnHeaderCell *headerCell;
    
    for (col in columns) {
        headerCell = [[AKSourceTableColumnHeaderCell alloc]  initTextCell:[[col headerCell] stringValue]];
        [col setHeaderCell:headerCell];
        [headerCell release];
    }
}

- (void) awakeFromNib
{
	[self updateColumnHeaderCells];
}

- (void)mouseDown:(NSEvent *)theEvent 
{
  // Swallow mouse downs so that click in the header doesn't attempt to re-order the contents of the source list.
}

- (void) setTableView:(NSTableView*)inTableView
{
  [super setTableView:inTableView];
  [self updateColumnHeaderCells];
}

@end

@implementation AKSourceTableColumnHeaderCell

- (NSPoint) scalePoint:(NSPoint)inPoint withScaleFactor:(float)scaleFactor
{
  NSPoint scaledPoint = inPoint;
  
  if (scaleFactor != 1.0)
  {
      // Convert coordinates to device space units.
      scaledPoint.x *= scaleFactor;
      scaledPoint.y *= scaleFactor;
   
      // Normalize the point to integer pixel boundaries and then shift the origin by 0.5
      // to produce crisper lines.
      scaledPoint.x = floor(scaledPoint.x);
      scaledPoint.y = floor(scaledPoint.y);
      scaledPoint.x += 0.5;
      scaledPoint.y += 0.5;
   
      // Convert back to user space.
      scaledPoint.x /= scaleFactor;
      scaledPoint.y /= scaleFactor;
  }

  return scaledPoint;
}

- (void)drawWithFrame:(NSRect)inFrame inView:(NSView*)inView
{
  [super drawWithFrame:inFrame inView:inView];
  
  // We draw three lines at the right hand of the header cell to indicate the 'thumb' that can be used to resize the
  // split view we're placed in.
  int i=0;
  NSPoint lineStart, lineEnd;
  
  // Lines start 10 pixels in from the end and have a gap of 3 pixels top/bottom.
  // Dark Color is 28% alpha black light color is 28% white
  lineStart.x = lineEnd.x = inFrame.origin.x + inFrame.size.width - 11;
  lineStart.y = inFrame.origin.y + 5;
  lineEnd.y = inFrame.origin.y + inFrame.size.height - 4;

  NSColor *dark = [[NSColor blackColor] colorWithAlphaComponent:0.45];
  NSColor *light= [[NSColor whiteColor] colorWithAlphaComponent:0.45];

  bool origAntiAliasState = [[NSGraphicsContext currentContext] shouldAntialias];
  [[NSGraphicsContext currentContext] setShouldAntialias:NO];
  
  [NSBezierPath setDefaultLineWidth:1.0];
  float scaleFactor = [[NSScreen mainScreen] userSpaceScaleFactor];
 
  for (i=0; i < 3; i++)
  {
    NSPoint scaledLineStart, scaledLineEnd;
    scaledLineStart = [self scalePoint:lineStart withScaleFactor:scaleFactor];
    scaledLineEnd = [self scalePoint:lineEnd withScaleFactor:scaleFactor];
    
    [dark setStroke];
    [NSBezierPath strokeLineFromPoint:scaledLineStart toPoint:scaledLineEnd];
    lineStart.x++; lineEnd.x++;
    scaledLineStart = [self scalePoint:lineStart withScaleFactor:scaleFactor];
    scaledLineEnd = [self scalePoint:lineEnd withScaleFactor:scaleFactor];
    [light setStroke];
    [NSBezierPath strokeLineFromPoint:scaledLineStart toPoint:scaledLineEnd];
    lineStart.x += 2;
    lineEnd.x += 2;
  }
  [[NSGraphicsContext currentContext] setShouldAntialias:origAntiAliasState];
}

@end

@implementation AKSourceTextCell

- (NSRect) titleRectForBounds:(NSRect)bounds 
{
	NSRect titleRect = bounds;
	
	titleRect.origin.x += 10;
	titleRect.size.width -= 10; // padding right
	
	return titleRect;
}

- (void) drawWithFrame:(NSRect)frame inView:(NSView *)controlView {
	[super drawWithFrame:[self titleRectForBounds:frame] inView:controlView];
}

@end

@implementation AKSourceSeparatorCell

- (void) drawWithFrame:(NSRect)frame inView:(NSView *)controlView
{
	float lineWidth = frame.size.width * 0.85;
	float lineX = (frame.size.width - lineWidth) / 2;
	float lineY = (frame.size.height - 2) / 2;
	lineY += 0.5;

	[[NSColor colorWithDeviceRed:0.820 green:0.847 blue:0.878 alpha:1.0] set];
	NSRectFill(NSMakeRect(frame.origin.x + lineX, frame.origin.y + lineY, lineWidth, 1));
	
	[[NSColor colorWithDeviceRed:0.976 green:1.0 blue:1.0 alpha:1.0] set];
	NSRectFill(NSMakeRect(frame.origin.x + lineX, frame.origin.y + lineY + 1, lineWidth, 1));
}

- (void) setPlaceholderString:(NSString *)placeholder
{
	// do nothing, method is just here in case you bind to a string
	// value, like [NSObject description]
}

@end
