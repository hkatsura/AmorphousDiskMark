//
//  DMButtonCell.m
//  AmorphousDiskMark
//
//  Created by Hidetomo Katsura on 10/11/2016.
//  Copyright © 2016 Katsura Shareware. All rights reserved.
//

#import "DMButtonCell.h"

@interface DMButtonCell ()

@property (strong) NSColor *highlightColor;
@property (strong) NSColor *darkHighlightColor;
@property (strong) NSImage *backgroundImage;
@property (strong) NSColor *darkBackgroundColor;

@end

@implementation DMButtonCell

- (void)setInitialValues
{
    // colorWithWhite:alpha: is only available on 10.9+
    //self.highlightColor = [NSColor colorWithWhite:0 alpha:0.2];
    self.highlightColor = [NSColor colorWithCalibratedWhite:0 alpha:0.2];
    self.darkHighlightColor = [NSColor colorWithCalibratedWhite:0.6 alpha:0.5];
    self.backgroundImage = [NSImage imageNamed:@"cdm-60x48"];
    self.darkBackgroundColor = [NSColor colorWithCalibratedWhite:0.35 alpha:1];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self != nil)
    {
        [self setInitialValues];
    }
    
    return self;
}

#if 0
- (BOOL)isOpaque
{
    KSLog(@"%s called", __func__);
    
    //return NO;
    return [super isOpaque];
}

- (NSColor *)backgroundColor
{
    KSLog(@"%s called", __func__);

    //return [NSColor colorWithCalibratedWhite:1.0 alpha:0.0];
    return [super backgroundColor];
}

// Draws the image associated with the button’s current state.
- (void)drawImage:(NSImage *)image withFrame:(NSRect)frame inView:(NSView *)controlView
{
    KSLog(@"%s called", __func__);

    [super drawImage:image withFrame:frame inView:controlView];
}

// Draws the button’s title centered vertically in a specified rectangle.

- (NSRect)drawTitle:(NSAttributedString *)title withFrame:(NSRect)frame inView:(NSView *)controlView
{
    KSLog(@"%s called", __func__);

    // Return Value: The bounding rectangle for the text of the title.
    return [super drawTitle:title withFrame:frame inView:controlView];
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    KSLog(@"%s called", __func__);
    
    [super drawWithFrame:cellFrame inView:controlView];
}
#endif

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    KSLog(@"%s called", __func__);
    
    KSLog(@"%s: cellFrame: (%d, %d, %d, %d)", __func__, (int)cellFrame.origin.x, (int)cellFrame.origin.y, (int)cellFrame.size.height, (int)cellFrame.size.width);
    cellFrame = NSInsetRect(cellFrame, 1, 1);
    // drawInRect:fromRect:operation:fraction: draws a flipped image.
    // so, use drawInRect:fromRect:operation:fraction:respectFlipped:hints: instead.
    //[_backgroundImage drawInRect:cellFrame fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1.0];
    if (_isDarkMode)
    {
        // don't draw the green background image. just fill with light gray color.
        [_darkBackgroundColor setFill];
        [NSBezierPath fillRect:cellFrame];
    }
    else
    {
        [_backgroundImage drawInRect:cellFrame fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1.0 respectFlipped:YES hints:nil];
    }
    if (self.isHighlighted)
    {
        [(_isDarkMode? _darkHighlightColor: _highlightColor) setFill];
        [NSBezierPath fillRect:cellFrame];
    }
 
    [super drawInteriorWithFrame:cellFrame inView:controlView];
}

@end
