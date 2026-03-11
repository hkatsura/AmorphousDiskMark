//
//  DMTextView.m
//  AmorphousDiskMark
//
//  Created by Hidetomo Katsura on 10/10/2016.
//  Copyright © 2016 Katsura Shareware. All rights reserved.
//

#import "DMTextView.h"

@interface DMTextView ()

@property (strong) NSColor *edgeColor;
@property (strong) NSColor *enabledTextColor;
@property (strong) NSColor *disabledTextColor;
@property (strong) NSImage *barImage;
@property (strong) NSColor *disabledOverlayColor;
@property (strong) NSColor *darkBarColor;
@property (assign, nonatomic) BOOL isDarkMode;
@property (strong, nonatomic) NSLocale *locale;

@end

@implementation DMTextView

// set default (non-zero) values
- (instancetype)initWithCoder:(NSCoder *)coder
{
    KSLog(@"%s called", __func__);

    self = [super initWithCoder:coder];
    if (self != nil)
    {
        [self setInitialApperance];
        [self setInitialValues];
    }
    
    return self;
}

// i just wanted to provide some way to unselect (unfocus)
// the model name text field to remove the keyboard focus
// ring for a nice screenshot.
- (void)mouseDown:(NSEvent *)event
{
#pragma unused(event)
    
    KSLog(@"%s: event: %@", __func__, event);
    
    [self.window makeFirstResponder:nil];
}

- (void)setInitialApperance
{
    // colorWithWhite:alpha: is only available on 10.9+
    //self.edgeColor = [NSColor colorWithWhite:0.5 alpha:0.5];
    //self.enabledTextColor = [NSColor colorWithWhite:0.0 alpha:1.0];
    //self.disabledTextColor = [NSColor colorWithWhite:0.5 alpha:1.0];
    self.edgeColor = [NSColor colorWithCalibratedWhite:0.5 alpha:0.5];
    //self.enabledTextColor = [NSColor colorWithCalibratedWhite:0.0 alpha:1.0];
    //self.disabledTextColor = [NSColor colorWithCalibratedWhite:0.5 alpha:1.0];
    self.enabledTextColor = [NSColor controlTextColor];
    self.disabledTextColor = [NSColor disabledControlTextColor];
    self.barImage = [NSImage imageNamed:@"cdm-16x48-bar"];
    self.darkBarColor = [NSColor colorWithCalibratedWhite:0.4 alpha:0.5];

    if (_isDarkMode)
    {
        self.disabledOverlayColor = [NSColor colorWithCalibratedWhite:0.3 alpha:0.5];
    }
    else
    {
        //self.disabledOverlayColor = [NSColor colorWithWhite:1.0 alpha:0.5];
        self.disabledOverlayColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.5];
    }
}

- (void)setInitialValues
{
    //_enabled = YES;

    // ignore value/state from xib.
    // otherwise, the value "88888.88" from xib
    // shows up briefly when the app launches.
    self.string = @"0.00";
    self.enabled = NO;
    self.values = nil;
    self.key = @"mbps";
    self.locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];

    [self addObserver:self forKeyPath:@"key" options:NSKeyValueObservingOptionNew context:NULL];
}

// two decimal point digits. max eight digits.  "0.00", "10.00", "100.00"
- (NSString *)mbpsString:(NSNumber *)number
{
    float result = number.floatValue;

    // normalize the result value
    if (result < 0.0)
    {
        result = 0.0;
    }

    NSNumberFormatter *nf = [[NSNumberFormatter alloc] init];
    nf.locale = _locale;
    nf.minimumIntegerDigits = 1;
    nf.minimumFractionDigits = 2;
    nf.maximumFractionDigits = 2;
    NSString *s = [nf stringFromNumber:@(result)];
    // normalizing the result value to be 999999.99 ends up the formatter
    // to format it as "1000000.00". so, force it to be "999999.99" here.
    if (s.floatValue > 999999.99)
    {
        s = @"999999.99";
    }
    return s;
}

// one decimal point digit. max eight digits.  "0.0", "10.0", "100.0"
- (NSString *)iopsString:(NSNumber *)number
{
    float result = number.floatValue;

    // normalize the result value
    if (result < 0.0)
    {
        result = 0.0;
    }

    NSNumberFormatter *nf = [[NSNumberFormatter alloc] init];
    nf.locale = _locale;
    nf.minimumIntegerDigits = 1;
    nf.minimumFractionDigits = 1;
    nf.maximumFractionDigits = 1;
    NSString *s = [nf stringFromNumber:@(result)];

    // normalizing the result value to be 9999999.9 ends up the formatter
    // to format it as "10000000.0". so, force it to be "9999999.9" here.
    if (s.floatValue > 9999999.9)
    {
        s = @"9999999.9";
    }
    return s;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey, id> *)change context:(void *)context
{
#pragma unused(object, context, keyPath, change)
    KSLog(@"%s: keyPath: %@, change: %@", __func__, keyPath, change);
    KSLog(@"%s: key: %@, values: %@", __func__, _key, _values);
    NSNumber *n = _key? _values[_key]: nil;
    n = n? n: @(0);
    NSString *s = [_key isEqualToString:@"mbps"]? [self mbpsString:n]: [self iopsString:n];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.string = s;
    });
    KSLog(@"%s: n: %@", __func__, n);
}

#if 0
// set default (non-zero) values
- (instancetype)init
{
    // well, this doesn't get called because DMTextView is instanciated in xib.
    KSLog(@"%s called", __func__);

    self = [super init];
    if (self != nil)
    {
        [self setInitialApperance];
        [self setInitialValues];
    }
    
    return self;
}
#endif

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
    [self setInitialApperance];
}

- (void)setEnabled:(BOOL)enabled
{
    KSLog(@"%s called: %s", __func__, enabled? "YES": "NO");
    _enabled = enabled;

    // use gray text when "disabled" (i.e. test in progress. or not test result.)
    self.textColor = _enabled? _enabledTextColor: _disabledTextColor;
}

#if 0
- (BOOL)isOpaque
{
    KSLog(@"%s called", __func__);
    return YES;
}
#endif

- (BOOL)drawsBackground
{
    KSLog(@"%s called", __func__);
    return NO;
}

//
// as of this writing, Samsung 960 Pro NVMe SSD 3500MB/s read, 2100MB/s write, 440,000 IOPS read, 360,000 IOPS write (4K, QD32/T4).
//   https://www.samsung.com/semiconductor/minisite/ssd/product/consumer/ssd960/
//

//
// CrystalDiskMark uses a logarithmic scale bar.
//
// min (0.00) : 0%
// max (3500>) : 100%
//
// percentage = 100 * log(MB/s) / log(max MB/s)
//
// 100 * log(3500) / log(3500) = 100%
// 100 * log(1750) / log(3500) = 91.5%
// 100 * log(38)   / log(3500) = 44.6%
// 100 * log(1)    / log(3500) = 0.0%
//
// log(0) is invalid. so, use the lower number limit 1.
//

//
// CDM7 (999999.99: 100%, 99999.99: 100%, 9999.99: 83%, 999.99: 67%, 99.99: 50%, 9.99: 33%, 0.99: 17%):
//   if (score > 0.1)
//   {
//     // r = 1.0 / 6.0 * log10(score * 10.0)
//     meterRatio = 0.16666666666666 * log10(score * 10);
//   }
//   else
//   {
//     meterRatio = 0;
//   }
//

- (CGFloat)barWidth
{
    // logarithmic scale bar
    CGFloat width = self.bounds.size.width;
    CGFloat v = [self.string floatValue];

    //
    // max digits
    //  MB/s: 999999.99 MB/s (6 integer digits)
    //  IOPS: 9999999.9 IOPS (7 integer digits)
    //
    CGFloat m = ([_key isEqualToString:@"mbps"]? 6: 7) + 1;

    // CrystalDiskMark uses this formula.
    CGFloat w = (v > 0.1)? (width / m * log10f(v * 10)): 0;
    //KSLog(@"%s: v: %f, width: %d", __func__, v, (int)w);
    
    if (w < 1.0)
    {
        w = 0;
    }
    else if (w > width)
    {
        w = width;
    }

    return w;
}

#if 0
- (BOOL)needsToDrawRect:(NSRect)rect
{
#pragma unused(rect)
    KSLog(@"%s called: rect: (%d, %d, %d, %d)", __func__, (int)rect.origin.x, (int)rect.origin.y, (int)rect.size.height, (int)rect.size.width);
    return NO;
}
#endif

- (void)drawRect:(NSRect)dirtyRect
{
#pragma unused(dirtyRect)
    
    KSLog(@"%s called: dirtyRect: (%d, %d, %d, %d): string: \"%@\"", __func__, (int)dirtyRect.origin.x, (int)dirtyRect.origin.y, (int)dirtyRect.size.height, (int)dirtyRect.size.width, self.string);
    NSRect bounds = self.bounds;
    // the UI size is 50 x 148 (h x w)
    // -[DMTextView drawRect:]: bounds: (0, 0, 48, 146)
    KSLog(@"%s: bounds: (%d, %d, %d, %d)", __func__, (int)bounds.origin.x, (int)bounds.origin.y, (int)bounds.size.height, (int)bounds.size.width);
    CGFloat w = [self barWidth];
    bounds.size.width = w;
    
    // drawInRect:fromRect:operation:fraction: draws a flipped image.
    // so, use drawInRect:fromRect:operation:fraction:respectFlipped:hints: instead.
    //[_image drawInRect:bounds fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1.0];
    if (_isDarkMode)
    {
        // don't use the bar image in dark mode. use gray bar fill.
        [_darkBarColor setFill];
        [NSBezierPath fillRect:bounds];
    }
    else
    {
        [_barImage drawInRect:bounds fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1.0 respectFlipped:YES hints:nil];
    }

    // draw the leading edge only if the bar width is non-zero
    if (bounds.size.width != 0)
    {
        // draw the leading edge
        NSRect line = NSMakeRect(bounds.size.width, 0, 1, bounds.size.height);
        NSBezierPath *path = [NSBezierPath bezierPathWithRect:line];
        [_edgeColor set];
        [path fill];
    }

     // let NSTextView draw the text (with no background)
    bounds = self.bounds;
    [super drawRect:bounds];
    
    // draw light white overlay when "disabled" (i.e. test in progress)
    if (!_enabled)
    {
        KSLog(@"%s: view is not enabled. adding white overlay.", __func__);
        [_disabledOverlayColor setFill];
        [NSBezierPath fillRect:bounds];
        KSLog(@"%s: added white overlay.", __func__);
    }
}

@end
