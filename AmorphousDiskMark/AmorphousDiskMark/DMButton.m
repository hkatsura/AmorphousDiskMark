//
//  DMButton.m
//  AmorphousDiskMark
//
//  Created by Hidetomo Katsura on 10/10/2016.
//  Copyright © 2016 Katsura Shareware. All rights reserved.
//

#import "DMButton.h"
#import "DMButtonCell.h"

@interface DMButton ()

@property (assign, nonatomic) BOOL isDarkMode;

@end

@implementation DMButton

- (void)viewDidChangeEffectiveAppearance
{
    KSLog(@"%s called", __func__);
    _isDarkMode = NO;
    if (@available(macOS 10.14, *))
    {
        NSAppearance *appearance = NSApp.effectiveAppearance;
        NSAppearanceName name = [appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
        _isDarkMode = [name isEqualToString:NSAppearanceNameDarkAqua];
    }
    KSLog(@"%s: isDarkMode: %s", __func__, _isDarkMode? "YES": "NO");
}

- (void)drawRect:(NSRect)dirtyRect
{
    KSLog(@"%s called", __func__);
    DMButtonCell *cell = (DMButtonCell *)self.cell;
    cell.isDarkMode = _isDarkMode;
    [super drawRect:dirtyRect];
}

@end
