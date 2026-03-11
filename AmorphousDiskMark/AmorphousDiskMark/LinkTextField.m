//
//  LinkTextField.m
//  AmorphousDiskMark
//
//  Created by Hidetomo Katsura on 10/16/2016.
//  Copyright © 2016 Katsura Shareware. All rights reserved.
//

#import "LinkTextField.h"

@interface LinkTextField ()

@property (strong) NSTrackingArea *trackingArea;

- (void)openURL;

@end

@implementation LinkTextField

- (void)mouseEntered:(NSEvent *)event
{
#pragma unused(event)
    
    KSLog(@"%s", __func__);
    
    // add underline
    NSMutableAttributedString *str = [[self attributedStringValue] mutableCopy];
    
    [str addAttribute:NSUnderlineStyleAttributeName value:[NSNumber numberWithInt:NSUnderlineStyleSingle] range:NSMakeRange(0, str.length)];
    
    [self setAttributedStringValue:str];
}

- (void)mouseExited:(NSEvent *)event
{
#pragma unused(event)

    KSLog(@"%s", __func__);

    // remove underline
    NSMutableAttributedString *str = [[self attributedStringValue] mutableCopy];
    
    [str removeAttribute:NSUnderlineStyleAttributeName range:NSMakeRange(0, str.length)];
    
    [self setAttributedStringValue:str];
}

-(void)updateTrackingAreas
{
    if (_trackingArea != nil)
    {
        [self removeTrackingArea:_trackingArea];
    }
    
    NSTrackingAreaOptions opts = (NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways);
    _trackingArea = [[NSTrackingArea alloc] initWithRect:[self bounds]
                                                 options:opts
                                                   owner:self
                                                userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)mouseDown:(NSEvent *)theEvent
{
    KSLog(@"%s", __func__);
    
    NSWindow *window;
    NSDate *distantFuture;
    NSEvent *currentEvent;
    
    window = [self window];
    distantFuture = [NSDate distantFuture];
    currentEvent = theEvent;
    
    // Track mouse dragged events until mouse up.  Always enter at least once.
    do
    {
        NSPoint currentPoint;
        NSEventType type;
        
        type = [currentEvent type];
        switch (type)
        {
            case NSEventTypeLeftMouseDown:
            case NSEventTypeLeftMouseDragged:
                KSLog(@"%s: NSLeftMouseDown/NSLeftMouseDragged", __func__);
                // draw darker image if the mouse is in the frame, otherwise draw regular image
                currentPoint = [self convertPoint:[currentEvent locationInWindow] fromView:self];
                if (NSMouseInRect(currentPoint, [self frame], [self isFlipped]))
                {
                    // add underline
                    [self mouseEntered:currentEvent];
                }
                else
                {
                    // remove underline
                    [self mouseExited:currentEvent];
                }
                break;
                
            case NSEventTypeLeftMouseUp:
                KSLog(@"%s: NSLeftMouseUp", __func__);
                currentPoint = [self convertPoint:[currentEvent locationInWindow] fromView:self];
                if ( NSMouseInRect( currentPoint, [self frame], [self isFlipped] ) )
                {
                    [self openURL];
                }
                return;
                
            default:
                KSLog(@"%s: other event", __func__);
                // If we find anything other than a mouse dragged (mouse up) we are done.
                return;
        }
        currentEvent = [window nextEventMatchingMask:( NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp ) untilDate:distantFuture inMode:NSEventTrackingRunLoopMode dequeue:YES];
    }
    while ( currentEvent != nil );
}

- (void)openURL
{
    KSLog( @"openURL" );
    
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[self stringValue]]];
}

- (void) resetCursorRects
{
    KSLog( @"resetCursorRects" );
    
    // change to a hand cursor when the mouse pointer enters
    NSCursor *cursor = [NSCursor pointingHandCursor];  // Mac OS X 10.3 and later
    [self addCursorRect:[self visibleRect] cursor:cursor];
}

@end
