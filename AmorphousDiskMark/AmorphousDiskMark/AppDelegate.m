//
//  AppDelegate.m
//  AmorphousDiskMark
//
//  Created by Hidetomo Katsura on 10/7/2016.
//  Copyright © 2016-2020 Katsura Shareware. All rights reserved.
//

#import "AppDelegate.h"

#import "DiskUtil.h"

#import "DMTextView.h"
#import "DMButton.h"
#import "DMMediaIcon.h"

#include <sys/sysctl.h>

// Test button tags (make sure to update the tag value in xib if you change tag/kind)
enum
{
    kAllButtonTag = kAllTestKind,
    kSeqQTButtonTag = kSeqQTTestKind,
    kSeqButtonTag = kSeqTestKind,
    k4KQTButtonTag = k4KQTTestKind,
    k4KButtonTag = k4KTestKind
};

//
// Storage popup button menu item tag:
//   Boot Volume: 0 (identifier: boot)
//   --------------
//   another volume: 1
//   yet another volume: 1
//   --------------
//   Select Target Volume...: 1 (identifier: select)
//
enum
{
    kSelectFolderTag = 1
};

// Test Data menu item.
enum
{
    kTestDataRandomTag = 1,
    kTestDataZeroTag = 0
};

// Interval menu item has the tag value in seconds
//  0 seconds: 0
//  1 second:  1
//  3 seconds: 3
//  ...

// deployment taget 10.6 doesn't support "weak".
// 10.8+ supports "weak".
#define WEAK unsafe_unretained

@interface NSString (DiskMark)

- (NSString *)stringByTrimmingTrailingWhitespace;

@end

@implementation NSString (DiskMark)

- (NSString *)stringByTrimmingTrailingWhitespace
{
     return [self stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

@end

@interface NSImage (DiskMark)

- (NSData *)PNGRepresentation;
- (NSImage *)menuItemImage;

@end

@implementation NSImage (DiskMark)

- (NSData *)PNGRepresentation
{
#if 0
    NSSize size = self.size;
    
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:size.width pixelsHigh:size.height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    [rep setSize:size];
    
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
    // drawInRect: is only available on 10.9+
    //[self drawInRect:NSMakeRect(0, 0, size.width, size.height)];
    [self drawInRect:NSMakeRect(0, 0, size.width, size.height) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
    [NSGraphicsContext restoreGraphicsState];
    
    return [rep representationUsingType:NSPNGFileType properties:@{}];
#else
    CGImageRef cgImage = [self CGImageForProposedRect:NULL context:nil hints:nil];
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];
    rep.size = self.size;
    return [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
#endif
}

- (NSImage *)menuItemImage {
#if 0
    NSRect rect = NSMakeRect(0, 0, 16, 16);
    NSImage *i16x16 = [[NSImage alloc] initWithSize:rect.size];
    NSImageRep *rep = [self bestRepresentationForRect:rect context:nil hints:nil];
    [i16x16 addRepresentation:rep];
    return i16x16;
#else
    self.size = NSMakeSize(16, 16);
    return self;
#endif
}

@end

@interface NSWindow (DiskMark)

- (NSImage *)windowImage;

@end

@implementation NSWindow (DiskMark)

- (NSImage *)windowImage
{
    CGWindowID windowID = (CGWindowID)[self windowNumber];
    
    // convert the origin (bottom-left to top-left)
    NSRect windowFrame = self.frame;
    windowFrame.origin.y = self.screen.frame.size.height - windowFrame.origin.y - windowFrame.size.height;
    // and include the window borders (but not the shadow) to make it look nice in reviews.
    windowFrame = NSInsetRect(windowFrame, -1, -1);
    // use CGRectNull if you want to include the shadow.
    CGImageRef windowCGImage = CGWindowListCreateImage(NSRectToCGRect(windowFrame), kCGWindowListOptionIncludingWindow, windowID, kCGWindowImageDefault);
    // convert from CGImage to NSImage
    NSImage *windowImage = [[NSImage alloc] initWithCGImage:windowCGImage size:windowFrame.size];
    [windowImage setCacheMode:NSImageCacheNever];
    CGImageRelease(windowCGImage);
    
    return windowImage;
}

@end

@interface AppDelegate ()

@property (WEAK) IBOutlet NSWindow *window;

@property (WEAK) IBOutlet NSPanel *helpWindow;
@property (WEAK) IBOutlet NSPanel *aboutWindow;

@property (WEAK) IBOutlet NSTextField *helpLlinkTextField;

@property (WEAK) IBOutlet NSTextField *versionTextField;
@property (WEAK) IBOutlet NSTextField *linkTextField;
@property (WEAK) IBOutlet NSTextField *ksLinkTextField;

@property (WEAK) IBOutlet NSTextField *mReadTitleTextField;
@property (WEAK) IBOutlet NSTextField *mWriteTitleTextField;

@property (WEAK) IBOutlet DMTextView *mRead0;
@property (WEAK) IBOutlet DMTextView *mWrite0;
@property (WEAK) IBOutlet DMTextView *mRead1;
@property (WEAK) IBOutlet DMTextView *mWrite1;
@property (WEAK) IBOutlet DMTextView *mRead2;
@property (WEAK) IBOutlet DMTextView *mWrite2;
@property (WEAK) IBOutlet DMTextView *mRead3;
@property (WEAK) IBOutlet DMTextView *mWrite3;

@property (WEAK) IBOutlet NSTextField *mModelName;

@property (WEAK) IBOutlet DMButton *mAllButton;
@property (WEAK) IBOutlet DMButton *mSeqQTButton;
@property (WEAK) IBOutlet DMButton *m4KQTButton;
@property (WEAK) IBOutlet DMButton *mSeqButton;
@property (WEAK) IBOutlet DMButton *m4KButton;

@property (WEAK) IBOutlet NSPopUpButton *mIterationPopUpButton;
@property (WEAK) IBOutlet NSPopUpButton *mSizePopUpButton;
@property (WEAK) IBOutlet NSPopUpButton *mStoragePopUpButton;
@property (WEAK) IBOutlet NSPopUpButton *mUnitPopUpButton;

@property (WEAK) IBOutlet NSMenu *mValueMenu;  // test data value: random or zero
@property (WEAK) IBOutlet NSMenu *mIntervalMenu;  // 0s, 1s, 3s, ..., 10m
@property (WEAK) IBOutlet NSMenu *mSeqQDMenu;  // QD=1, 2, 4, 8, ..., 1024
@property (WEAK) IBOutlet NSMenu *mRandomQDMenu;  // QD=1, 2, 4, 8, ..., 1024
@property (WEAK) IBOutlet NSMenu *mDurationMenu;  // duration limit: None (0), 5s, 10s, 15s, 30s, 60s (1 minute)

@property (nonatomic, strong) NSMenuItem *bootVolumeMenuItem;
@property (nonatomic, strong) NSMenuItem *selectTargetVolumeMenuItem;
@property (nonatomic, strong) NSString *bootVolumeDirectoryPath;
@property (nonatomic, strong) NSString *targetVolumePath;
@property (nonatomic, strong) NSDictionary *targetMountInfo;

@property (strong) id values;

@property (assign) NSInteger lastSelectedStorageIndex;

@property (assign) double timebase;

@property (strong) DiskMark *mDiskMark;

@property (strong) DiskUtil *mDiskUtil;

@property (strong) NSMutableDictionary *scores;

@property (strong) NSArray *unitTypeIdentifiers;
@property (strong) NSLocale *locale;

@end

@implementation AppDelegate

#pragma mark --- class methods ---

//
// 1.0/2.0:
//      test size: 500 MiB
//
// 2.5:
//      interval: 3 seconds
//      iteration: 1 run
//      test size: 512 MiB
//      sequential queue depth: 32 (128 KiB block size)
//      random queue depth: 32
//
// 3.0: changed the default settings to match CDM7.
//      interval: 5 seconds
//      iteration: 5 runs
//      test size: 1 GiB
//      sequential queue depth: 8 (1 MiB block size)
//      random queue depth: 64
//
// 3.1: added arm64 support.
//
// 3.2: fixed the slow measurement result text field update
//      issue by adding needsDIsplay=YES.
//      fixed the issue where the About/Help window gets left
//      behind after the main window gets closed (NSWindow ==>
//      NSPanel).
//
+ (void)initialize
{
    [[NSUserDefaultsController sharedUserDefaultsController] setInitialValues:@{
        DMInterval : @(5),  // 5 seconds (CDM: 5 seconds)
        DMIsRandom : @YES,  // YES: random, NO: zero-fill (CDM: random)
        DMIteration : @(5),  // 5 runs (CDM: 5 runs)
        DMMiBSize : @(1024),  // 1 GiB (CDM: 1 GiB = 1024 MiB)
        DMSeqQD : @(8),  // QD=8
        DMRandomQD : @(64),  // QD=64
        DMUnitType : @"mbps",  // unit type: "MB/s" (mbps)
        DMDuration : @(5),  // 5-second measurement duration time limit (CDM: 5 seconds)
    }];
}

#pragma mark ---

- (void)clearScoresForButtonTag:(NSInteger)kind
{
    // clear all if kind is kAllButtonTag
    if (kind == kAllButtonTag)
    {
        [self clearScoresForButtonTag:kSeqQTButtonTag];
        [self clearScoresForButtonTag:k4KQTButtonTag];
        [self clearScoresForButtonTag:kSeqButtonTag];
        [self clearScoresForButtonTag:k4KButtonTag];
    }
    else
    {
        DMTextView *read, *write;
        
        read = write = nil;
        switch (kind)
        {
            case kSeqQTButtonTag:
            {
                read = _mRead0;
                write = _mWrite0;
                break;
            }
            case k4KQTButtonTag:
            {
                read = _mRead1;
                write = _mWrite1;
                break;
            }
            case kSeqButtonTag:
            {
                read = _mRead2;
                write = _mWrite2;
                break;
            }
            case k4KButtonTag:
            {
                read = _mRead3;
                write = _mWrite3;
                break;
            }
            default:
            {
                // this should never happen.
                break;
            }
        }
        NSDictionary *zeros = @{@"mbps": @(0), @"iops": @(0)};
        read.values = zeros;
        write.values = zeros;
        NSString *key = [_values valueForKey:DMUnitType];
        // setting the key to DMTextView triggers the redraw
        read.key = key;
        write.key = key;
        read.toolTip = @"";
        write.toolTip = @"";
        read.enabled = NO;
        write.enabled = NO;

        // clear the score cache
        NSMutableDictionary *md = _scores;
        if (md != nil)
        {
            NSArray *keys = @[[NSString stringWithFormat:@"%ld,r", (unsigned long)kind], [NSString stringWithFormat:@"%ld,w", (unsigned long)kind]];
            [md removeObjectsForKeys:keys];
            _scores = md;
        }
    }
}

#pragma mark --- disk test ---

#if 0
- (NSString *)testPathForStorageMenuItem:(NSMenuItem *)menuItem
{
    KSLog(@"%s: menuItem: %@", __func__, menuItem);
    if (menuItem.tag == kSelectFolderTag)
    {
        NSDictionary *representedObject = menuItem.representedObject;
        NSURL *URL = representedObject[@"URL"];
        if (URL == NULL)
        {
            // this should never happen.
            return @"/tmp";
        }
        
        return URL.path;
    }
    else
    {
        // add "/tmp" to the target path if the boot partition is selected
        // since "/" is not writable unless you have the root privilege.
        NSDictionary *selectedMount = menuItem.representedObject;
        return [selectedMount[@"isBootVolume"] boolValue]? @"/tmp": selectedMount[@"onname"];
    }
}

- (NSString *)testPath
{
    return [self testPathForStorageMenuItem:_mStoragePopUpButton.selectedItem];
}
#else
- (NSString *)testPath
{
    return _targetVolumePath;
}
#endif

- (NSNumber *)testIteration
{
    NSInteger iteration = _mIterationPopUpButton.selectedTag;
    return @(iteration);
}

- (NSNumber *)testSize
{
    NSInteger mebibytes = _mSizePopUpButton.selectedTag;
    KSLog(@"%s: testSize: %d MiB", __func__, (int)mebibytes);
    return @(mebibytes * 1024 * 1024);
}

// BOOL: YES (random) / NO (zero fill)
- (NSNumber *)testRandomValues
{
    return [_values valueForKey:DMIsRandom];
}

- (NSNumber *)testInterval
{
    return [_values valueForKey:DMInterval];
}

- (NSNumber *)testSeqQD
{
    return [_values valueForKey:DMSeqQD];
}

- (NSNumber *)testRandomQD
{
    return [_values valueForKey:DMRandomQD];
}

- (NSNumber *)testDuration
{
    return [_values valueForKey:DMDuration];
}

- (void)runTestSeqQT
{
    KSLog(@"%s: ", __func__);
    
#if 0
    extern const NSString *DMInterval;
    
    extern const NSString *DMSeqQD;
    extern const NSString *DMRandomQD;

    extern const NSString *DMIteration;
    extern const NSString *DMMiBSize;
    extern const NSString *DMPath;
    
    extern const NSString *DMKind;

    extern const NSString *DMUnitType;

    extern const NSString *DMDuration;
#endif
    
    NSDictionary *attrs = @{DMKind: @(kSeqQTTestKind), DMSeqQD: [self testSeqQD], DMIsRandom: [self testRandomValues], DMRandomQD: [self testRandomQD], DMInterval: [self testInterval], DMIteration: [self testIteration], DMMiBSize: [self testSize], DMPath: [self testPath], DMDuration: [self testDuration]};
    self.mDiskMark = [DiskMark diskMarkWithAttributes:attrs delegate:self];
    
    // DMBlockSize: @(1 * 1024 * 1024), DMQueueDepth: @(32), DMThread: @(1), DMIsRandom: @NO,
}

- (void)runTest4KQT
{
    KSLog(@"%s: ", __func__);
    
    NSDictionary *attrs = @{DMKind: @(k4KQTTestKind), DMSeqQD: [self testSeqQD], DMIsRandom: [self testRandomValues], DMRandomQD: [self testRandomQD], DMInterval: [self testInterval], DMIteration: [self testIteration], DMMiBSize: [self testSize], DMPath: [self testPath], DMDuration: [self testDuration]};
    self.mDiskMark = [DiskMark diskMarkWithAttributes:attrs delegate:self];
    
    // DMBlockSize: @(4 * 1024), DMQueueDepth: @(32), DMThread: @(1), DMIsRandom: @YES,
}

- (void)runTestSeq
{
    KSLog(@"%s: ", __func__);
    
    NSDictionary *attrs = @{DMKind: @(kSeqTestKind), DMSeqQD: [self testSeqQD], DMIsRandom: [self testRandomValues], DMRandomQD: [self testRandomQD], DMInterval: [self testInterval], DMIteration: [self testIteration], DMMiBSize: [self testSize], DMPath: [self testPath], DMDuration: [self testDuration]};
    self.mDiskMark = [DiskMark diskMarkWithAttributes:attrs delegate:self];
    
    // DMBlockSize: @(1 * 1024 * 1024), DMQueueDepth: @(1), DMThread: @(1), DMIsRandom: @NO,
}

- (void)runTest4K
{
    KSLog(@"%s: ", __func__);
    
    NSDictionary *attrs = @{DMKind: @(k4KTestKind), DMSeqQD: [self testSeqQD], DMIsRandom: [self testRandomValues], DMRandomQD: [self testRandomQD], DMInterval: [self testInterval], DMIteration: [self testIteration], DMMiBSize: [self testSize], DMPath: [self testPath], DMDuration: [self testDuration]};
    self.mDiskMark = [DiskMark diskMarkWithAttributes:attrs delegate:self];
    
    // DMBlockSize: @(4 * 1024), DMQueueDepth: @(1), DMThread: @(1), DMIsRandom: @YES,
}

- (void)runAllTests
{
    KSLog(@"%s: ", __func__);
    
    NSDictionary *attrs = @{DMKind: @(kAllTestKind), DMSeqQD: [self testSeqQD], DMIsRandom: [self testRandomValues], DMRandomQD: [self testRandomQD], DMInterval: [self testInterval], DMIteration: [self testIteration], DMMiBSize: [self testSize], DMPath: [self testPath], DMDuration: [self testDuration]};
    self.mDiskMark = [DiskMark diskMarkWithAttributes:attrs delegate:self];
}

// Stop button pressed. clean up after a force-stop.
- (void)stopTest
{
    KSLog(@"%s: ", __func__);
    
    // force-stop the test
    [_mDiskMark stop];
    [_mDiskMark waitUntilStop];
    
    // UI clean up is done in the "didFinish" delegate
}

//
// 1. the data kind random (default) vs. zero.
//   "AmorphousDiskMark <version>" vs. "AmorphousDiskMark <version> <0 Fill>"
// 2. the duration limit 5-second (default) vs. other settings.
//   "AmorphousDiskMark <version>" vs. "AmorphousDiskMark <version> <duration-limit-second>"
//
- (void)updateWindowTitle
{
    // reset the window title
    NSString *title;

    // add the test value string to the window title if it's not the default (random).
    if ([[_values valueForKey:DMIsRandom] integerValue] == kTestDataRandomTag)
    {
        title = NSLocalizedString(@"AmorphousDiskMark %@", "AmorphousDiskMark %@");
    }
    else
    {
        title = NSLocalizedString(@"AmorphousDiskMark %@ <0 Fill>", "AmorphousDiskMark %@ <0 Fill>");
    }

    // add the duration limit string to the window title if it's not the default (5-second).
    NSInteger limit = [[_values valueForKey:DMDuration] integerValue];
    if (limit == 0)
    {
        title = [title stringByAppendingString:@" <No Limit>"];
    }
    else if (limit != 5)
    {
        title = [title stringByAppendingFormat:@" <Limit=%@s>", @(limit)];
    }
    _window.title = [NSString stringWithFormat:title, [self appVersion]];
}

- (void)updateSeqQDButton
{
    NSNumber *seqQD = [_values valueForKey:DMSeqQD];
    
    _mSeqQTButton.title = [NSString stringWithFormat:NSLocalizedString(@"SEQ1M\nQD%@", "SeqQD button"), seqQD];
    _mSeqQTButton.toolTip = [NSString stringWithFormat:NSLocalizedString(@"Run sequential 1 MiB block (QD=%@) read/write tests", "Run sequential 1 MiB block (QD=%@) read/write tests"), seqQD];
}

- (void)updateRandomQDButton
{
    NSNumber *randomQD = [_values valueForKey:DMRandomQD];
    
    _m4KQTButton.title = [NSString stringWithFormat:NSLocalizedString(@"RND4K\nQD%@", "4KQD button"), randomQD];
    _m4KQTButton.toolTip = [NSString stringWithFormat:NSLocalizedString(@"Run random sequence 4KiB block (QD=%@) read/write tests", "Run random sequence 4KiB block (QD=%@) read/write tests"), randomQD];
}

- (void)restoreButtons
{
    // restore the window title
    [self updateWindowTitle];
    
    // reset all buttons to the original title
    _mAllButton.title = NSLocalizedString(@"All", "All button");
    
    // SeqQD, RandomQD buttons
    [self updateSeqQDButton];
    [self updateRandomQDButton];
    
    _mSeqButton.title = NSLocalizedString(@"SEQ1M\nQD1", "Seq button");
    _m4KButton.title = NSLocalizedString(@"RND4K\nQD1", "4K button");

    // enable UI (except for the Stop buttons)
    _mIterationPopUpButton.enabled = YES;
    _mSizePopUpButton.enabled = YES;
    _mStoragePopUpButton.enabled = YES;
}

- (void)prepareForTest:(NSInteger)kind
{
    // set all buttons to "Stop"
    NSString *stopString = NSLocalizedString(@"Stop", "Stop button");
    
    _mAllButton.title = stopString;
    _mSeqQTButton.title = stopString;
    _m4KQTButton.title = stopString;
    _mSeqButton.title = stopString;
    _m4KButton.title = stopString;
    
    [self clearScoresForButtonTag:kind];
    
    // disable UI (except for the Stop buttons)
    _mIterationPopUpButton.enabled = NO;
    _mSizePopUpButton.enabled = NO;
    _mStoragePopUpButton.enabled = NO;

#if 0
    switch (kind)
    {
        case kAllTestKind:
        {
            _mRead0.enabled = NO;
            _mWrite0.enabled = NO;
            _mRead1.enabled = NO;
            _mWrite1.enabled = NO;
            _mRead2.enabled = NO;
            _mWrite2.enabled = NO;
            _mRead3.enabled = NO;
            _mWrite3.enabled = NO;
            break;
        }
        case kSeqQTTestKind:
        {
            _mRead0.enabled = NO;
            _mWrite0.enabled = NO;
            break;
        }
        case k4KQTTestKind:
        {
            _mRead1.enabled = NO;
            _mWrite1.enabled = NO;
            break;
        }
        case kSeqTestKind:
        {
            _mRead2.enabled = NO;
            _mWrite2.enabled = NO;
            break;
        }
        case k4KTestKind:
        {
            _mRead3.enabled = NO;
            _mWrite3.enabled = NO;
            break;
        }
        default:
        {
            // this should never happen.
            break;
        }
    }
#endif
}

#if 0
// one decimal point digit. max total eight digits.  "0.0", "10.0", "100.0"
- (NSString *)iopsString:(NSNumber *)number
{
    float result = number.floatValue;

    // normalize the result value
    if (result > 9999999.9)
    {
        result = 9999999.9;
    }
    else if (result < 0.0)
    {
        result = 0.0;
    }

    NSNumberFormatter *nf = [[NSNumberFormatter alloc] init];
    nf.locale = _locale;
    nf.minimumIntegerDigits = 1;
    nf.minimumFractionDigits = 1;
    nf.maximumFractionDigits = 1;
    nf.usesGroupingSeparator = YES;
    return [nf stringFromNumber:@(result)];
}
#endif

- (void)didFinishTest:(NSDictionary *)results
{
#pragma unused(results)
    
    KSLog(@"%s: results: %@", __func__, results);

    // bring UI back
    [self restoreButtons];
    
    // clean up the disk mark
    self.mDiskMark = nil;
}

#pragma mark --- DiskUtilDelegate ---

- (void)didMountDiskUtil:(DiskUtil *)diskUtil volume:(NSDictionary *)volume
{
#pragma unused(diskUtil, volume)
    [self diskArbitationObserver:nil];
}

- (void)didUnmountDiskUtil:(DiskUtil *)diskUtil volume:(NSDictionary *)volume
{
#pragma unused(diskUtil, volume)
    [self diskArbitationObserver:nil];
}

- (void)didChangeDiskUtil:(DiskUtil *)diskUtil volume:(NSDictionary *)volume
{
    #pragma unused(diskUtil, volume)
    [self diskArbitationObserver:nil];
}

#pragma mark --- DiskMarkDelegate ---

- (void)didProgressDiskMark:(DiskMark *)diskMark progress:(NSDictionary *)progress
{
#pragma unused(diskMark)
    
    _window.title = progress[@"message"];
}

// this gets called with one result at a time
// kind: @(kSeqQTTestKind), isRead: @(YES), result: @(356.8)
- (void)didMeasureDiskMark:(DiskMark *)diskMark measurements:(NSDictionary *)measurements
{
#pragma unused(diskMark)
    
    DMTextView *textView;
    NSInteger kind = [measurements[@"kind"] integerValue];
    BOOL isRead = [measurements[@"isRead"] boolValue];
    NSNumber *mbps = measurements[@"mbps"];
    NSNumber *iops = measurements[@"iops"];
    NSString *toolTip = measurements[@"tooltip"];
    switch (kind)
    {
        case kSeqQTTestKind:
        {
            textView = isRead? _mRead0: _mWrite0;
            break;
        }
        case k4KQTTestKind:
        {
            textView = isRead? _mRead1: _mWrite1;
            break;
        }
        case kSeqTestKind:
        {
            textView = isRead? _mRead2: _mWrite2;
            break;
        }
        case k4KTestKind:
        {
            textView = isRead? _mRead3: _mWrite3;
            break;
        }
        default:
        {
            // this should never happen.
            break;
        }
    }
    
    //textView.string = mbps;
    //textView.toolTip = iops;
    textView.toolTip = toolTip;
    textView.values = @{@"mbps": mbps, @"iops": iops};
    // setting the key to DMTextView triggers the redraw
    textView.key = [_values valueForKey:DMUnitType];
    textView.enabled = YES;

    // update the score cache
    NSMutableDictionary *md = _scores? _scores: [NSMutableDictionary dictionary];
    NSString *key = [NSString stringWithFormat:@"%ld,%s", (unsigned long)kind, isRead? "r": "w"];
    NSDictionary *dict = @{@"mbps": mbps, @"iops": iops};
    [md setObject:dict forKey:key];
    _scores = md;
}

- (void)didPresentErrorWithRecovery:(BOOL)recover contextInfo:(void *)info
{
#pragma unused(recover, info)
    [self didFinishTest:nil];
}

- (void)didFinishDiskMark:(DiskMark *)diskMark withError:(NSError *)error
{
#pragma unused(diskMark, error)

    KSLog(@"%s:error:%@", __func__, error);

    if (error != nil)
    {
        [_window presentError:error modalForWindow:_window delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:NULL];
    }
    else
    {
        [self didFinishTest:nil];
    }
}

#pragma mark --- DiskArbitration ---

- (void)updateTestDataMenu
{
    NSMenuItem *randomMenuItem = [_mValueMenu itemWithTag:kTestDataRandomTag];
    NSMenuItem *zeroMenuItem = [_mValueMenu itemWithTag:kTestDataZeroTag];
    
    if ([[_values valueForKey:DMIsRandom] integerValue] == kTestDataRandomTag)
    {
        randomMenuItem.state = NSOnState;
        zeroMenuItem.state = NSOffState;
    }
    else
    {
        randomMenuItem.state = NSOffState;
        zeroMenuItem.state = NSOnState;
    }
}

- (void)updateIntervalMenu
{
    NSInteger interval = [[_values valueForKey:DMInterval] integerValue];
    
    // set all menu items to "off"
    for (NSMenuItem *item in _mIntervalMenu.itemArray)
    {
        item.state = NSOffState;
    }
    
    // set one menu item to "on"
    [[_mIntervalMenu itemWithTag:interval] setState:NSOnState];
}

- (void)updateSeqQDMenu
{
    NSInteger seqQD = [[_values valueForKey:DMSeqQD] integerValue];
    
    // set all menu items to "off"
    for (NSMenuItem *item in _mSeqQDMenu.itemArray)
    {
        item.state = NSOffState;
    }
    
    // set one menu item to "on"
    [[_mSeqQDMenu itemWithTag:seqQD] setState:NSOnState];
}

- (void)updateRandomQDMenu
{
    NSInteger randomQD = [[_values valueForKey:DMRandomQD] integerValue];
    
    // set all menu items to "off"
    for (NSMenuItem *item in _mRandomQDMenu.itemArray)
    {
        item.state = NSOffState;
    }
    
    // set one menu item to "on"
    [[_mRandomQDMenu itemWithTag:randomQD] setState:NSOnState];
}

- (void)updateDurationMenu
{
    NSInteger duration = [[_values valueForKey:DMDuration] integerValue];

    // set all menu items to "off"
    for (NSMenuItem *item in _mDurationMenu.itemArray)
    {
        item.state = NSOffState;
    }

    // set one menu item to "on"
    [[_mDurationMenu itemWithTag:duration] setState:NSOnState];
}

- (void)updateMenus
{
    [self updateTestDataMenu];
    [self updateIntervalMenu];
    [self updateSeqQDMenu];
    [self updateRandomQDMenu];
    [self updateUnitTypeMenu];
    [self updateDurationMenu];
}

#define TB (1000ULL * 1000 * 1000 * 1000)
#define GB (1000ULL * 1000 * 1000)
#define MB (1000ULL * 1000)
#define KB (1000ULL)

- (NSString *)humanReadableSize:(NSNumber *)size
{
    uint64_t s = size.unsignedIntegerValue;
    
    if (s >= TB)
    {
        // turn 1.999 TB into 2 TB
        // assuming we usually don't have 1.5 TB or 2.5 TB storage device.
        s += (TB / 4);
        return [NSString stringWithFormat:NSLocalizedString(@"%lldTB", "%lldTB"), s / TB];
    }
    else if (s >= GB )
    {
        s += (GB / 2);
        return [NSString stringWithFormat:NSLocalizedString(@"%lldGB", "%lldGB"), s / GB];
    }
    else if (s >= MB )
    {
        s += (MB / 2);
        return [NSString stringWithFormat:NSLocalizedString(@"%lldMB", "%lldMB"), s / MB];
    }
    else if (s >= KB )
    {
        s += (KB / 2);
        return [NSString stringWithFormat:NSLocalizedString(@"%lldKB", "%lldKB"), s / KB];
    }
    else
    {
        return [NSString stringWithFormat:NSLocalizedString(@"%lldB", "%lldB"), s];
    }
}

- (void)updateModelName
{
    NSString *modelName = @"";
    NSDictionary *selectedMount = [[_mStoragePopUpButton selectedItem] representedObject];
    if (selectedMount != nil)
    {
        NSString *deviceModel = selectedMount[@"daDeviceModel"];
        NSString *cpuName = [self cpuName];
        if (cpuName.length != 0)
        {
            modelName = [NSString stringWithFormat:@"%@ / %@", deviceModel, cpuName];
        }
        else
        {
            modelName = deviceModel;
        }
    }
    _mModelName.stringValue = modelName;
    _mModelName.toolTip = _mStoragePopUpButton.toolTip;
    
    // hack. remove me. this is for a nice screenshot just like CrystalDiskMark.
    //_mModelName.stringValue = @"Intel SSD 750 (Intel NVMe Driver)";
}

- (NSString *)toolTipStringWithInfo:(NSDictionary *)mount
{
    //
    // Device Model: APPLE SSD SM0512F
    // Volume Name: Macintosh HD
    // File System: APFS
    // Capacity: 500.07 GB
    // Available: 57.73 GB
    // Used: 442.34 GB
    // Block Size: 4 KiB
    // Interconnect: PCI
    // Location: Internal
    // Medium Type: Solid State
    // Queue Depth: 32
    // Native Command Queuing: Yes
    //

    // @{@"fromname": fromname, @"onname": onname, @"daVolumeName": daVolumeName, @"daDeviceModel": daDeviceModel, @"daVolumeType": daVolumeType, @"isBootVolume": @(isBootVolume), @"isReadOnly": @(isReadOnly), @"size": @(size), @"freeSize": @(freeSize), @"bsize": @(bsize), @"percentUsed": @(percentUsed), @"fstype": fstype}
    NSNumber *blockSize = mount[@"bsize"];
    NSNumber *capacity = mount[@"size"];
    NSNumber *available = mount[@"freeSize"];
    NSUInteger used = capacity.unsignedIntegerValue - available.unsignedIntegerValue;
    NSNumber *isReadOnly = mount[@"isReadOnly"];
    NSNumber *isBootVolume = mount[@"isBootVolume"];
    NSString *readOnly = @"";
    if (!isBootVolume.boolValue && isReadOnly.boolValue)
    {
        //
        // workaround: adding " " in between "\n" and "\n". otherwise, "\n\n" turns into
        //             just one "\n" on macOS 10.15.
        //
        readOnly = @"Read/Write test cannot run on a read-only target.\n \n";
    }
    // device: "/dev/disk0s2" for non-APFS, "/dev/disk1s1 (Physical Store: disk0s2)" for APFS, or "//user@host/share-point" for remote file system.
    NSString *device = mount[@"fromname"];
    NSString *apfsPhysicalStore = mount[@"apfsPhysicalStore"];
    if (apfsPhysicalStore.length != 0)
    {
        device = [NSString stringWithFormat:@"%@ (Physical Store: %@)", device, apfsPhysicalStore];
    }
    NSString *toolTip = [NSString stringWithFormat:@"%@Device Model: %@\nVolume Name: %@\nDevice Node: %@\nFile System: %@\nCapacity: %@\nAvailable: %@\nUsed: %@\nBlock Size: %@", readOnly, mount[@"daDeviceModel"], mount[@"daVolumeName"], device, [DiskUtil localizedFileSystemNameForKind:mount[@"fstype"] type:mount[@"daVolumeType"]], [DiskUtil humanReadableSize:capacity.unsignedIntegerValue], [DiskUtil humanReadableSize:available.unsignedIntegerValue], [DiskUtil humanReadableSize:used], [DiskMark humanReadableBlockSize:blockSize.unsignedIntegerValue]];

    // add "Queue Depth", "NCQ", "Interconnect", etc. if available
    NSDictionary *deviceInfo = [self deviceInfoAtDevicePath:mount[@"daDevicePath"]];
    // Physical Interconnect: USB, PCI, SATA, etc.
    NSString *interconnect = deviceInfo[@"physicalInterconnect"];
    if ([interconnect isKindOfClass:[NSString class]]) {
        toolTip = [toolTip stringByAppendingFormat:@"\nInterconnect: %@", interconnect];
    }
    // Physical Interconnect Location: Internal, External
    NSString *location = deviceInfo[@"physicalInterconnectLocation"];
    if ([location isKindOfClass:[NSString class]]) {
        toolTip = [toolTip stringByAppendingFormat:@"\nLocation: %@", location];
    }
    // Medium Type: Rotational, Solid State
    NSString *mediumType = deviceInfo[@"mediumType"];
    if ([mediumType isKindOfClass:[NSString class]]) {
        toolTip = [toolTip stringByAppendingFormat:@"\nMedium Type: %@", mediumType];
    }
    // Queue Depth: 32
    NSNumber *qd = deviceInfo[@"queueDepth"];
    if ([qd isKindOfClass:[NSNumber class]]) {
        toolTip = [toolTip stringByAppendingFormat:@"\nQueue Depth: %@", qd];
    }
    // NCQ: YES/NO
    NSNumber *ncq = deviceInfo[@"ncq"];
    if ([ncq isKindOfClass:[NSNumber class]]) {
        toolTip = [toolTip stringByAppendingFormat:@"\nNative Command Queuing: %s", ncq.boolValue? "Yes": "No"];
    }

    return toolTip;
}

- (NSDictionary *)propertiesFromDevicePath:(NSString *)devicePath {
    CFMutableDictionaryRef props = NULL;
    if (devicePath.length != 0) {
        io_registry_entry_t entry = IORegistryEntryFromPath(kIOMasterPortDefault, devicePath.UTF8String);
        if (entry != MACH_PORT_NULL) {
            kern_return_t kr = IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0);
            if (kr != kIOReturnSuccess) {
                NSLog(@"error: IORegistryEntryCreateCFProperties: kr: %@", @(kr));
            }
            IOObjectRelease(entry);
        } else {
            NSLog(@"error: IORegistryEntryFromPath");
        }
    }
    return props? [NSDictionary dictionaryWithDictionary:(__bridge_transfer NSDictionary *)props]: nil;
}

- (NSDictionary *)deviceInfoAtDevicePath:(NSString *)devicePath {
    KSLog(@"%s: devicePath: %@", __func__, devicePath);
    NSMutableDictionary *md = [NSMutableDictionary dictionary];
    NSDictionary *deviceProps = [self propertiesFromDevicePath:devicePath];
    KSLog(@"%s: deviceProps: %@", __func__, deviceProps);
    // "Device Characteristics":{"Medium Type": "Solid State", "Product Revision Level": "UXM2JA1Q", "Serial Number": "S1K5NYAG336733      ", "Physical Block Size": 4096, "Logical Block Size": 512}
    NSDictionary *dc = deviceProps[@"Device Characteristics"];
    if ([dc isKindOfClass:[NSDictionary class]]) {
        NSString *mediumType = dc[@"Medium Type"];
        if ([mediumType isKindOfClass:[NSString class]]) [md setObject:mediumType forKey:@"mediumType"];
        NSString *revision = dc[@"Product Revision Level"];
        if ([revision isKindOfClass:[NSString class]]) [md setObject:revision forKey:@"revision"];
        NSNumber *logicalBlockSize = dc[@"Logical Block Size"];
        if ([logicalBlockSize isKindOfClass:[NSNumber class]]) [md setObject:logicalBlockSize forKey:@"logicalBlockSize"];
        NSNumber *physicalBlockSize = dc[@"Physical Block Size"];
        if ([physicalBlockSize isKindOfClass:[NSNumber class]]) [md setObject:physicalBlockSize forKey:@"physicalBlockSize"];
        // "S1K5NYAG336733      "
        NSString *serialNumber = dc[@"Serial Number"];
        serialNumber = [serialNumber stringByTrimmingTrailingWhitespace];
        if (serialNumber != nil) [md setObject:serialNumber forKey:@"serialNumber"];
    }

    // "Protocol Characteristics":{"Physical Interconnect": "USB", "Physical Interconnect Location": "External"}
    NSDictionary *pc = deviceProps[@"Protocol Characteristics"];
    if ([pc isKindOfClass:[NSDictionary class]]) {
        NSString *physicalInterconnect = pc[@"Physical Interconnect"];
        if ([physicalInterconnect isKindOfClass:[NSString class]]) [md setObject:physicalInterconnect forKey:@"physicalInterconnect"];
        NSString *physicalInterconnectLocation = pc[@"Physical Interconnect Location"];
        if ([physicalInterconnectLocation isKindOfClass:[NSString class]]) [md setObject:physicalInterconnectLocation forKey:@"physicalInterconnectLocation"];
    }

    // "IOService:/.../AppleAHCIDiskDriver/IOAHCIBlockStorageDevice"
    //   ==> "IOService:/.../AppleAHCIDiskDriver"
    devicePath = [devicePath stringByDeletingLastPathComponent];
    NSDictionary *deviceParentProps = [self propertiesFromDevicePath:devicePath];
    KSLog(@"%s: deviceParentProps: %@", __func__, deviceParentProps);
    // "Serial Number" (String), "Revision" (String), "Queue Depth" (Number), "Queue Depth Counters" (Dictionary), "NCQ" (bool), "Logical Block Size" (Number), "Physical Block Size" (Number)
    NSNumber *queueDepth = deviceParentProps[@"Queue Depth"];
    if ([queueDepth isKindOfClass:[NSNumber class]]) [md setObject:queueDepth forKey:@"queueDepth"];
    NSNumber *ncq = deviceParentProps[@"NCQ"];
    if ([ncq isKindOfClass:[NSNumber class]]) [md setObject:ncq forKey:@"ncq"];
    NSDictionary *queueDepthCounters = deviceParentProps[@"Queue Depth Counters"];
    if ([queueDepthCounters isKindOfClass:[NSDictionary class]]) [md setObject:queueDepthCounters forKey:@"queueDepthCounters"];
    return [NSDictionary dictionaryWithDictionary:md];
}

- (NSString *)volumeTitleWithInfo:(NSDictionary *)mount {
    //NSString *volumeName = [self volumeNameAtPath:mount[@"onname"]];
    NSString *volumeName = mount[@"daVolumeName"];
    NSNumber *percentUsed = mount[@"percentUsed"];
    return [NSString stringWithFormat:@"%@ (%@%% used)", volumeName, percentUsed];
}

- (NSImage *)volumeIconWithInfo:(NSDictionary *)mount
{
    NSDictionary *iconDict = mount[@"daMediaIcon"];
    KSLog(@"%s: iconDict: %@", __func__, iconDict);
    NSImage *image = nil;
    if (iconDict.count != 0) {
        image = [DMMediaIcon iconWithDictionary:iconDict];
    } else if (!((NSNumber *)mount[@"isLocal"]).boolValue) {
        // get the network icon
        image = [NSImage imageNamed:NSImageNameNetwork];
    }
    return [image menuItemImage];
}

- (void)updateStoragePopUpButton
{
    // remember the current selection.
    // the current selection may go away
    // when the user unmounts the device
    // or the remote mount point.
    //NSDictionary *selectedMount = [[_mStoragePopUpButton selectedItem] representedObject];
    //KSLog(@"%s: entered: selected mount: %@", __func__, selectedMount[@"daVolumeName"]);
    
    // get the current popup button menu
    // and delete all menu items.
    //
    NSMenu *m = _mStoragePopUpButton.menu;
    [m removeAllItems];

    // add the boot volume menu item first
    _bootVolumeMenuItem.state = NSOffState;
    [m addItem:_bootVolumeMenuItem];
    [m addItem:[NSMenuItem separatorItem]];

    NSArray *mounts = [_mDiskUtil mountInfo];
    for (NSDictionary *mount in mounts) {
        if ([mount[@"onname"] isEqualToString:@"/"]) {
            _bootVolumeMenuItem.representedObject = mount;
            _bootVolumeMenuItem.toolTip = [self toolTipStringWithInfo:mount];
            _bootVolumeMenuItem.title = [self volumeTitleWithInfo:mount];
            _bootVolumeMenuItem.image = [self volumeIconWithInfo:mount];
        } else {
            NSString *title = [self volumeTitleWithInfo:mount];
            NSMenuItem *mi = [m addItemWithTitle:title action:NULL keyEquivalent:@""];
            mi.representedObject = mount;
            mi.tag = kSelectFolderTag;
            mi.toolTip = [self toolTipStringWithInfo:mount];
            NSNumber *isReadOnly = mount[@"isReadOnly"];
            mi.enabled = !isReadOnly.boolValue;
            mi.image = [self volumeIconWithInfo:mount];
        }
    }

    // avoid adding two separators in a row
    if (mounts.count > 1)
    {
        [m addItem:[NSMenuItem separatorItem]];
    }

    // add the "Select Folder..." menu item
    [m addItem:_selectTargetVolumeMenuItem];

    [self selectCurrentVolume];

    // update the model name text field
    [self updateModelName];

#if 0
    NSInteger index;

    // add the current mounts to the popup button
    NSArray *mounts = [_mDiskUtil mountInfo];
    for (NSDictionary *mount in mounts)
    {
        uint64_t capacity, available, used, blockSize;
        
        // add to before the separator
        index = [_mStoragePopUpButton numberOfItems] - 2;
        NSString *title = [NSString stringWithFormat:@"%@ (%@%%)", mount[@"daVolumeName"], mount[@"percentUsed"]];
        [_mStoragePopUpButton insertItemWithTitle:title atIndex:index];
        NSMenuItem *item = [_mStoragePopUpButton itemAtIndex:index];
        [item setRepresentedObject:mount];
        capacity = [mount[@"size"] unsignedIntegerValue];
        available = [mount[@"freeSize"] unsignedIntegerValue];
        used = capacity - available;
        blockSize = [mount[@"bsize"] unsignedIntegerValue];
        NSString *toolTip = [NSString stringWithFormat:NSLocalizedString(@"Device Model: %@\nVolume Name: %@\nFile System: %@\nCapacity: %@\nAvailable: %@\nUsed: %@\nBlock Size: %@", "Device Model: %@\nVolume Name: %@\nFile System: %@\nCapacity: %@\nAvailable: %@\nUsed: %@\nBlock Size: %@"), mount[@"daDeviceModel"], mount[@"daVolumeName"], [DiskUtil localizedFileSystemNameForKind:mount[@"fstype"] type:mount[@"daVolumeType"]], [DiskUtil humanReadableSize:capacity], [DiskUtil humanReadableSize:available], [DiskUtil humanReadableSize:used], [DiskMark humanReadableBlockSize:blockSize]];
        if ([mount[@"isReadOnly"] boolValue])
        {
            // make sure to disable the read-only menu item here.
            // validateMenuItem only doesn't get invoked if the
            // popup button menu is already showing (popped).
            [item setEnabled:NO];
            
            // add "read-only" note to the mount description tooltop.
            [item setToolTip:[NSString stringWithFormat:NSLocalizedString(@"%@\n\n%@", "%@\n\n%@"), NSLocalizedString(@"Read/Write test cannot run on a read-only target.", "Read/Write test cannot run on a read-only target."), toolTip]];
        }
        else
        {
            [item setToolTip:toolTip];
        }
    }
    
    // try to select the previous selection
    NSString *fromname = selectedMount[@"fromname"];
    numberOfItems = [_mStoragePopUpButton numberOfItems];
    for (index = 0; index < numberOfItems; index++)
    {
        NSDictionary *menuMount = [[_mStoragePopUpButton itemAtIndex:index] representedObject];
        if ([fromname isEqualToString:menuMount[@"fromname"]])
        {
            // found it!
            break;
        }
    }
    
    // select the previous selection if still there
    if (index >= numberOfItems)
    {
        // the device was probably disconnected. clear the scores.
        [self clearScoresForButtonTag:kAllButtonTag];
        [_mStoragePopUpButton selectItemAtIndex:0];
    }
    else
    {
        // select the previously selected item
        [_mStoragePopUpButton selectItemAtIndex:index];
    }
    
    // update the model name text field
    [self updateModelName];
    
    _lastSelectedStorageIndex = _mStoragePopUpButton.indexOfSelectedItem;
    KSLog(@"%s: exiting: selected mount: %@ (index: %d)", __func__, _mStoragePopUpButton.titleOfSelectedItem, (int)_lastSelectedStorageIndex);
#endif
}

- (void)selectCurrentVolume {
    // add checkmark to the appropriate menu item
    NSMenu *m = _mStoragePopUpButton.menu;
    for (NSMenuItem *mi in m.itemArray) {
        mi.state = NSOffState;
    }
    BOOL selected = NO;
    NSString *mp = [DiskUtil mountPointForPath:_targetVolumePath];
    KSLog(@"%s: mp: %@", __func__, mp);
    if ([mp isEqualToString:@"/"]) {
        _bootVolumeMenuItem.state = NSOnState;
        [_mStoragePopUpButton selectItem:_bootVolumeMenuItem];
        selected = YES;
        _targetMountInfo = _bootVolumeMenuItem.representedObject;
        _mStoragePopUpButton.toolTip = _bootVolumeMenuItem.toolTip;
    } else {
        NSArray<NSMenuItem *> *items = m.itemArray;
        for (NSMenuItem *mi in items) {
            NSDictionary *mount = mi.representedObject;
            if (mount == nil) {
                continue;
            }
            BOOL state = [mp isEqualToString:mount[@"onname"]];
            KSLog(@"%s: mount[\"fromname\"]: %@, mount[\"onname\"]: %@. state: %s", __func__, mount[@"fromname"], mount[@"onname"], state? "YES": "NO");
            mi.state = state;
            if (state) {
                [_mStoragePopUpButton selectItem:mi];
                selected = YES;
                _targetMountInfo = mi.representedObject;
                _mStoragePopUpButton.toolTip = mi.toolTip;
            }
        }
    }
    if (!selected) {
        // not in the volume menu. select the "select target volume..." menu item
        _selectTargetVolumeMenuItem.state = NSOnState;
        _targetMountInfo = nil;
        _mStoragePopUpButton.toolTip = nil;
    }
}

- (BOOL)isWritableFileAtPath:(NSString *)path {
    KSLog(@"%s: path: %@", __func__, path);
    return [[NSFileManager defaultManager] isWritableFileAtPath:path];
}

// "mbps", "iops"
- (void)updateUnitTypeMenu
{
    NSUInteger c = _unitTypeIdentifiers.count;
    NSString *identifier = [_values valueForKey:DMUnitType];
    NSUInteger tag = [_unitTypeIdentifiers indexOfObject:identifier];
    if ((tag == NSNotFound) || (tag < 0)) tag = 0;
    else if (tag >= c) tag = c - 1;
    for (NSMenuItem *mi in [_mUnitPopUpButton itemArray])
    {
        NSString *mii = [self unitTypeIdentifierForTag:mi.tag];
        mi.toolTip = [mii isEqualToString:@"mbps"]? @"MB/s (megabytes per second)": @"IOPS (input/output operations per second)";
    }
    [_mUnitPopUpButton selectItemWithTag:tag];
    _mUnitPopUpButton.toolTip = [_mUnitPopUpButton selectedItem].toolTip;

    // also update the read/write titles
    [self updateReadWriteTitlesForIdentifier:identifier];
}

#pragma mark --- Disk Arbitration Observer ---

- (void)diskArbitationObserver:(NSArray *)keys
{
#pragma unused(keys)
    
    KSLog(@"%s called: %@", __func__, keys);

    // in case of an unmount, default the current volume to "/"
    if ([DiskUtil volumeNameAtPath:_targetVolumePath] == nil) {
        _targetVolumePath = _bootVolumeDirectoryPath;
    }

    // update the storage popup button menu items
    [self updateStoragePopUpButton];
}

#pragma mark --- menu item validation ---

- (BOOL)shouldEnableStorageMenuItem:(NSMenuItem *)menuItem
{
#if 0
    // the "Select Folder..." menu item must always be
    // enabled so that the use can select a folder at
    // any time as long as the test is not currently
    // running.
    if (menuItem.tag == kSelectFolderTag)
    {
        return YES;
    }
    
    // and only writable mount points should be enabled.
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *path = [self testPathForStorageMenuItem:menuItem];
    KSLog(@"%s: path: %@", __func__, path);
    return [fm isWritableFileAtPath:path];
#else
    NSString *identifier = menuItem.identifier;
    if ([identifier isEqualToString:@"boot"]) {
        return YES;
    } else if ([identifier isEqualToString:@"select"]) {
        return YES;
    } else {
        NSDictionary *mount = menuItem.representedObject;
        NSNumber *isReadOnly = mount[@"isReadOnly"];
        return !isReadOnly.boolValue;
    }
#endif
}

- (BOOL) isTestSettingMenuItem:(NSMenuItem *)menuItem
{
    SEL action = menuItem.action;
    BOOL isRunning = _mDiskMark.isRunning;
    
    if ((action == @selector(copy:)) ||
        (action == @selector(saveDocument:)) ||
        (action == @selector(saveDocumentAs:)))
    {
        return YES;
    }
    else if (action == @selector(printWindow:))
    {
        return YES;
    }
    else if ((action == @selector(orderFrontAboutPanel:)) ||
             (action == @selector(showHelp:)))
    {
        // the "about this app" and "help" menu items are always enabled
        return YES;
    }
    else if ((action == @selector(iaTestDataMenuItem:)) ||
        (action == @selector(iaIntervalMenuItem:)) ||
        (action == @selector(iaSeqQDMenuItem:)) ||
        (action == @selector(iaRandomQDMenuItem:)) ||
        (action == @selector(iaIterationPopUpButton:)) ||
        (action == @selector(iaSizePopUpButton:)) ||
        (action == @selector(iaDurationMenuItem:)))
    {
        return isRunning? NO: YES;
    }
    else if (action == @selector(iaStoragePopUpButton:))
    {
        // disable the menu item for read-only mount points and devices
        if (isRunning)
        {
            return NO;
        }
        
        // only enable writable mounts
        return [self shouldEnableStorageMenuItem:menuItem];
    }
    else if (action == @selector(iaUnitPopUpButton:))
    {
        // always enabled
        return YES;
    }

    return NO;
}

- (BOOL) validateMenuItem:(NSMenuItem *)menuItem
{
    return [self isTestSettingMenuItem:menuItem];
}

#pragma mark --- NSApplicationDelegate ---

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
#pragma unused(aNotification)
    
    KSLog(@"%s: entered", __func__);

    // use consistent decimal point "." and thousand separater ","
    self.locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];

    //
    // NSUserInterfaceItemIdentifier (identifier) is only available on macOS 10.13+
    // so, create the operation type identifier and tag mapping here.
    //
    self.unitTypeIdentifiers = @[@"mbps",@"iops"];

    // retain special storage popup button menu items
    NSArray<NSMenuItem *> *ia = _mStoragePopUpButton.menu.itemArray;
    KSLog(@"storage popup button itemArray: %@", ia);
    for (NSMenuItem *mi in ia)
    {
        //
        // identifier does't work on macOS 10.11.6 for some reason,
        // and the app ends up with no volume popup button menu.
        //
        // use the tag value 0/1 as a workaround.
        //
        NSString *identifier = mi.identifier;
        NSInteger tag = mi.tag;
        if ([identifier isEqualToString:@"boot"] || ((tag == 0) && !mi.isSeparatorItem))
        {
            KSLog(@"found the boot volume menu item: %@", mi);
            _bootVolumeMenuItem = mi;
        }
        else if ([identifier isEqualToString:@"select"] || (tag == kSelectFolderTag))
        {
            KSLog(@"found the select volume menu item: %@", mi);
            _selectTargetVolumeMenuItem = mi;
        }
    }

    // keep the shared user defaults values handy
    self.values = [[NSUserDefaultsController sharedUserDefaultsController] values];

    // the model name field gets selected (well, i guess i could do something
    // about this in the xib but...). so, deselect it here programatically for now.
    [_window makeFirstResponder:nil];
    
    // initialize DiskUtil instance
    self.mDiskUtil = [DiskUtil diskUtilWithDelegate:self];

    // clear model name
    _mModelName.stringValue = @"";
    
    // set zero to score fields
    [self clearScoresForButtonTag:kAllButtonTag];
    
    // update menu item status
    [self updateMenus];

    // assuming the temporary directory is on the boot volume (usually in /var/folder/).
    _bootVolumeDirectoryPath = NSTemporaryDirectory();
    _targetVolumePath = _bootVolumeDirectoryPath;
    KSLog(@"_bootVolumeDirectoryPath: %@", _bootVolumeDirectoryPath);

    // update the storage popup button
    [self updateStoragePopUpButton];
    
    // update popup button state, button text and state
    [self restoreButtons];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
#pragma unused(sender)

    KSLog(@"%s: entered", __func__);

    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
#pragma unused(aNotification)
    
    KSLog(@"%s: entered", __func__);
    KSLog(@"_mDiskMark: %@", _mDiskMark);

    // force-stop the test if any
    [_mDiskMark stop];
    [_mDiskMark waitUntilStop];
    
    self.mDiskMark = nil;
    self.mDiskUtil = nil;

    KSLog(@"%s: existing", __func__);
}

#pragma mark --- IBAction ---

- (IBAction)iaButton:(id)sender
{
    NSButton *button = (NSButton *)sender;
    NSInteger tag = button.tag;
    
    KSLog(@"%s: entered (tag: %d)", __func__, (int)tag);
    
    // if the test is running, this is a "Stop" request.
    if (_mDiskMark.isRunning)
    {
        [self stopTest];
        
        return;
    }
    
    [self prepareForTest:tag];
    switch (tag)
    {
        case kAllButtonTag:
        {
            [self runAllTests];
            break;
        }
        case kSeqQTButtonTag:
        {
            [self runTestSeqQT];
            break;
        }
        case k4KQTButtonTag:
        {
            [self runTest4KQT];
            break;
        }
        case kSeqButtonTag:
        {
            [self runTestSeq];
            break;
        }
        case k4KButtonTag:
        {
            [self runTest4K];
            break;
        }
        default:
        {
            // this should never happen.
            break;
        }
    }
}

- (IBAction)iaIterationPopUpButton:(id)sender
{
#pragma unused(sender)
    
#if DO_LOG
    NSPopUpButton *popUpButton = (NSPopUpButton *)sender;
    NSInteger tag = popUpButton.selectedTag;
    
    KSLog(@"%s: entered (tag: %d)", __func__, (int)tag);
#endif
}

- (IBAction)iaSizePopUpButton:(id)sender
{
#pragma unused(sender)
    
#if DO_LOG
    NSPopUpButton *popUpButton = (NSPopUpButton *)sender;
    NSInteger tag = popUpButton.selectedTag;
    
    KSLog(@"%s: entered (tag: %d)", __func__, (int)tag);
#endif
}

- (IBAction)iaStoragePopUpButton:(id)sender
{
#if 0
    NSPopUpButton *popUpButton = (NSPopUpButton *)sender;
    NSInteger tag = popUpButton.selectedTag;
    
    KSLog(@"%s: entered (tag: %d)", __func__, (int)tag);
    
    if (tag == kSelectFolderTag)
    {
        NSOpenPanel *openPanel = [NSOpenPanel openPanel];
        openPanel.canChooseFiles = NO;
        openPanel.canChooseDirectories = YES;
        openPanel.resolvesAliases = YES;
        openPanel.allowsMultipleSelection = NO;
        openPanel.prompt = NSLocalizedString(@"Select", "Select button");
        openPanel.directoryURL = [NSURL fileURLWithPath:@"/Volumes" isDirectory:YES];
        
        [openPanel beginSheetModalForWindow:_window completionHandler:^(NSInteger result) {
            KSLog(@"%s: result: %d", __func__, (int)result);
            if (result == NSFileHandlingPanelOKButton)
            {
                // figure out which mount point that the selected
                // "folder" belongs to.
                NSArray *URLs = openPanel.URLs;
                if (URLs.count == 0)
                {
                    // this should never happen.
                    return;
                }
                NSMenuItem *menuItem = [self->_mStoragePopUpButton lastItem];
                NSURL *URL = URLs[0];
                NSString *path = URL.path;
                menuItem.representedObject = @{@"URL": URL, @"daDeviceModel": path, @"fromname": path, @"onname": path};
                [menuItem setToolTip:[NSString stringWithFormat:NSLocalizedString(@"Selected Folder: %@", "Selected Folder: %@"), URL.path]];
                menuItem.title = [NSString stringWithFormat:NSLocalizedString(@"Select Folder... (%@)", "Select Folder... (%@)"), URL.lastPathComponent];
                
                self->_lastSelectedStorageIndex = self->_mStoragePopUpButton.indexOfSelectedItem;
                KSLog(@"%s: select folder: OK: updated lastSelectedStorageIndex to %d", __func__, (int)self.lastSelectedStorageIndex);
                [self clearScoresForButtonTag:kAllButtonTag];
            }
            else
            {
                // the folder selection has been cancelled. so, select the last known item.
                [self->_mStoragePopUpButton selectItemAtIndex:self->_lastSelectedStorageIndex];
                KSLog(@"%s: select folder: CANCEL: selected lastSelectedStorageIndex: %d", __func__, (int)self.lastSelectedStorageIndex);
            }

            [self updateModelName];
        }];
    }
    else
    {
        // if a different item is selected, clear the score and update the model name
        NSInteger indexOfSelectedItem = _mStoragePopUpButton.indexOfSelectedItem;
        if (_lastSelectedStorageIndex != indexOfSelectedItem)
        {
            _lastSelectedStorageIndex = indexOfSelectedItem;
            KSLog(@"%s: lastSelectedStorageIndex: %d", __func__, (int)_lastSelectedStorageIndex);
            [self clearScoresForButtonTag:kAllButtonTag];
            [self updateModelName];
        }
    }
#else
    KSLog(@"sender: %@", sender);
    NSPopUpButton *popUpButton = (NSPopUpButton *)sender;
    NSMenuItem *mi = [popUpButton selectedItem];
    NSString *identifier = mi.identifier;
    KSLog(@"identifier: %@", identifier);
    NSInteger tag = mi.tag;
    KSLog(@"tag: %@", @(tag));
    NSDictionary *representedObject = mi.representedObject;
    KSLog(@"representedObject: %@", representedObject);
    if (tag == kSelectFolderTag) {
        // selected the volume menu item or the select folder menu item
        NSOpenPanel *openPanel = [NSOpenPanel openPanel];
        if (representedObject != nil) {
            NSString *volumePath = representedObject[@"onname"];
            openPanel.directoryURL = [NSURL fileURLWithPath:volumePath isDirectory:YES];
        }
        openPanel.canChooseDirectories = YES;
        openPanel.canChooseFiles = NO;
        openPanel.canCreateDirectories = YES;
        openPanel.prompt = @"Choose";
        openPanel.message = @"Choose a writable folder on the target volume you want to test:";
        //openPanel.delegate = self;
        [openPanel beginSheetModalForWindow:_window completionHandler:^(NSModalResponse returnCode) {
            KSLog(@"returnCode: %@", @(returnCode));
            KSLog(@"NSModalResponseOK: %@, NSModalResponseCancel: %@", @(NSModalResponseOK), @(NSModalResponseCancel));
            if (returnCode == NSModalResponseCancel) {
                // cancelled. do nothing.
                [self selectCurrentVolume];

                // update the model name text field
                [self updateModelName];
                return;
            }
            NSString *path = openPanel.URL.path;
            if (![self isWritableFileAtPath:path]) {
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = @"Not writable";
                alert.informativeText = @"The selected folder is not writable. Please select a writable folder.";
                [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
#pragma unused(returnCode)
                    KSLog(@"returnCode: %@", @(returnCode));
                }];
                [self selectCurrentVolume];

                // update the model name text field
                [self updateModelName];
            } else {
                self.targetVolumePath = openPanel.URL.path;
                [self updateStoragePopUpButton];
            }
        }];
    } else if ([identifier isEqualToString:@"boot"]) {
        // boot volume
        _targetVolumePath = _bootVolumeDirectoryPath;

        // select the boot volume in the popup button
        [self selectCurrentVolume];

        // update the model name text field
        [self updateModelName];
    }
#endif
}

- (IBAction)iaTestDataMenuItem:(id)sender
{
    NSMenuItem *menuItem = (NSMenuItem *)sender;
    
    KSLog(@"%s: entered (tag: %d)", __func__, (int)menuItem.tag);
    
    // update the test data (random or zero-fill)
    [_values setValue:@(menuItem.tag) forKey:DMIsRandom];
    
    // update the menu item states
    [self updateTestDataMenu];

    // update the window title
    [self updateWindowTitle];
}

- (IBAction)iaIntervalMenuItem:(id)sender
{
    NSMenuItem *menuItem = (NSMenuItem *)sender;
    
    KSLog(@"%s: entered (tag: %d)", __func__, (int)menuItem.tag);
    
    [_values setValue:@(menuItem.tag) forKey:DMInterval];
    [self updateIntervalMenu];
}

- (IBAction)iaSeqQDMenuItem:(id)sender
{
    NSMenuItem *menuItem = (NSMenuItem *)sender;
    
    KSLog(@"%s: entered (tag: %d)", __func__, (int)menuItem.tag);
    
    [_values setValue:@(menuItem.tag) forKey:DMSeqQD];
    [self updateSeqQDMenu];
    [self updateSeqQDButton];
}

- (IBAction)iaRandomQDMenuItem:(id)sender
{
    NSMenuItem *menuItem = (NSMenuItem *)sender;
    
    KSLog(@"%s: entered (tag: %d)", __func__, (int)menuItem.tag);
    
    [_values setValue:@(menuItem.tag) forKey:DMRandomQD];
    [self updateRandomQDMenu];
    [self updateRandomQDButton];
}

- (IBAction)iaDurationMenuItem:(id)sender
{
    NSMenuItem *mi = (NSMenuItem *)sender;
    NSInteger tag = mi.tag;
    KSLog(@"%s: entered (tag: %d)", __func__, (int)tag);
    // save the duration time limit seconds
    [_values setValue:@(tag) forKey:DMDuration];
    [self updateDurationMenu];

    // update the window title
    [self updateWindowTitle];
}

- (IBAction)iaModelName:(id)sender
{
#pragma unused(sender)
    
    KSLog(@"%s: entered (string: %@)", __func__, [sender stringValue]);

    // deselect the model name text field when the user hits return.
    [_window makeFirstResponder:_window.contentView];
}

- (NSString *)unitTypeIdentifierForTag:(NSInteger)tag
{
    NSUInteger c = _unitTypeIdentifiers.count;
    if (tag < 0) tag = 0;
    else if ((NSUInteger)tag >= c) tag = c - 1;
    return _unitTypeIdentifiers[tag];
}

- (void)updateReadWriteTitlesForIdentifier:(NSString *)identifier
{
    if ([identifier isEqualToString:@"mbps"])
    {
        _mReadTitleTextField.stringValue = @"Read [MB/s]";
        _mWriteTitleTextField.stringValue = @"Write [MB/s]";
        _mReadTitleTextField.toolTip = @"MB/s = 1,000,000 bytes/second";
        _mWriteTitleTextField.toolTip = @"MB/s = 1,000,000 bytes/second";
    }
    else
    {
        _mReadTitleTextField.stringValue = @"Read [IOPS]";
        _mWriteTitleTextField.stringValue = @"Write [IOPS]";
        _mReadTitleTextField.toolTip = @"IOPS (input/output operations per second)";
        _mWriteTitleTextField.toolTip = @"IOPS (input/output operations per second)";
    }
}

- (IBAction)iaUnitPopUpButton:(id)sender
{
#pragma unused(sender)
    KSLog(@"%s: entered (string: %@)", __func__, [sender stringValue]);
    NSPopUpButton *popUpButton = (NSPopUpButton *)sender;
    NSMenuItem *mi = [popUpButton selectedItem];
    NSInteger tag = mi.tag;
    KSLog(@"tag: %d", (int)tag);
    NSString *identifier = [self unitTypeIdentifierForTag:tag];
    popUpButton.toolTip = mi.toolTip;
    NSArray<DMTextView *> *tvs = @[_mRead0, _mRead1, _mRead2, _mRead3, _mWrite0, _mWrite1, _mWrite2, _mWrite3];
    [tvs enumerateObjectsWithOptions:NSEnumerationConcurrent usingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
#pragma unused(idx, stop)
        DMTextView *tv = obj;
        tv.key = identifier;
        // relying on the key/value observer callback causes each text field
        // to get updated at visually different time, unfortunately. setting
        // needsDisplay/YES here seems to trigger the simultaneous redraw of
        // all text fields.
        dispatch_async(dispatch_get_main_queue(), ^{
            tv.needsDisplay = YES;
        });
    }];

    // [MB/s] <=> [IOPS]
    [self updateReadWriteTitlesForIdentifier:identifier];

    // save the unit type selection
    [_values setValue:identifier forKey:DMUnitType];
}

#pragma mark --- Help panel ---

- (IBAction)showHelp:(id)sender
{
    KSLog(@"%s: entered (sender: %@)", __func__, sender);

    if (@available(macOS 10.10, *))
    {
        _helpLlinkTextField.textColor = [NSColor linkColor];
    }

    [_helpWindow center];
    [_helpWindow makeKeyAndOrderFront:sender];
}

#pragma mark --- About panel ---

- (IBAction)orderFrontAboutPanel:(id)sender
{
    KSLog(@"%s: entered (sender: %@)", __func__, sender);
    
    // update the version string
    NSDictionary* infoDict = [[NSBundle mainBundle] infoDictionary];
    NSString *versionString = [NSString stringWithFormat:NSLocalizedString(@"Version %@ (%@)", "Version %@ (%@)"), [infoDict objectForKey:@"CFBundleShortVersionString"], [infoDict objectForKey:@"CFBundleVersion"]];
    _versionTextField.stringValue = versionString;
    if (@available(macOS 10.10, *))
    {
        _linkTextField.textColor = [NSColor linkColor];
        _ksLinkTextField.textColor = [NSColor linkColor];
    }
    
    [_aboutWindow center];
    [_aboutWindow makeKeyAndOrderFront:sender];
}

#pragma mark --- print ---

- (IBAction)printWindow:(id)sender
{
    KSLog(@"%s: entered (sender: %@)", __func__, sender);

    NSImage *windowImage = [_window windowImage];
    NSSize size = windowImage.size;
    NSImageView *imageView = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)];
    imageView.image = windowImage;
    //
    // Mac App Store review rejected the app because the image
    // on the print preview was getting clipped.
    //
#if 0
    [imageView print:sender];
#else
#pragma unused(sender)
    NSPrintInfo *pi = [NSPrintInfo sharedPrintInfo];
    pi.horizontallyCentered = YES;
    pi.horizontalPagination = NSPrintingPaginationModeFit;
    pi.verticallyCentered = NO;
    pi.verticalPagination = NSPrintingPaginationModeFit;
    //pi.orientation = NSLandscapeOrientation;
    NSPrintOperation *po = [NSPrintOperation printOperationWithView:imageView printInfo:pi];
    NSPrintPanel *pp = po.printPanel;
    pp.options |= NSPrintPanelShowsPageSetupAccessory;
    [po runOperation];
#endif
}

#pragma mark -- copy/cut ---

- (NSString *)osVersionWithBuildVersion:(NSString *)osBuildVersion
{
    NSString *osVersion = @"";
    NSOperatingSystemVersion v;
    NSProcessInfo *pi = [NSProcessInfo processInfo];
    if ([pi respondsToSelector:@selector(operatingSystemVersion)])
    {
        v = [pi operatingSystemVersion];
    }
    else
    {
        // operatingSystemVersion is availabe on macoS 10.10+
        // 10K549 : 10.6.8
        // 11E53 : 10.7.4
        // 12F45 : 10.8.5
        // 13F34 : 10.9.5
        // 14F2109 : 10.10.5
        // 15G19009 : 10.11.6
        v.majorVersion = 10;
        NSInteger minor = (osBuildVersion.length >= 2)? [osBuildVersion substringToIndex:2].intValue: 12;
        v.minorVersion = minor - 4;
        NSInteger patch = (osBuildVersion.length >= 3)? [osBuildVersion characterAtIndex:2] - 'A': 0;
        v.patchVersion = patch;
    }
    if (v.patchVersion != 0)
    {
        osVersion = [NSString stringWithFormat:@"%@.%@.%@", @(v.majorVersion), @(v.minorVersion), @(v.patchVersion)];
    }
    else
    {
        osVersion = [NSString stringWithFormat:@"%@.%@", @(v.majorVersion), @(v.minorVersion)];
    }
    return osVersion;
}

- (NSString *)osBuildVersion
{
    // int sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen);
    char s[256];
    size_t l = sizeof(s);
    int r = sysctlbyname("kern.osversion", &s[0], &l, NULL, 0);
    return (r == 0)? [NSString stringWithUTF8String:s]: @"";
}

- (NSString *)appVersion
{
    NSDictionary *infoPlist = [[NSBundle mainBundle] infoDictionary];
    NSString *appVersion = infoPlist[@"CFBundleShortVersionString"];
    return appVersion? appVersion: @"";
}

- (NSString *)cpuName
{
    // int sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen);
    char s[256];
    size_t l = sizeof(s);
    int r = sysctlbyname("machdep.cpu.brand_string", &s[0], &l, NULL, 0);
    NSString *cpuName = (r == 0)? [NSString stringWithUTF8String:s]: @"";
    // Intel(R) Core(TM) i7-4870HQ CPU @ 2.50GHz
    // Intel(R) Core(TM)2 Duo CPU P8600 @ 2.40GHz
    // Intel(R) Core(TM) M-5Y31 CPU @ 0.90GHz
    // Intel(R) Xeon(R) CPU           E5520  @ 2.27GHz
    // Apple processor (Developer Transition Kit ARM Mac mini)
    // VirtualApple @ 2.50GHz processor (Developer Transition Kit ARM Mac mini Rosetta 2)
    if ([cpuName hasPrefix:@"Intel"])
    {
        // remove repeating whitespace
        cpuName = [cpuName stringByReplacingOccurrencesOfString:@"[ \t]+" withString:@" " options:NSRegularExpressionSearch range:NSMakeRange(0, cpuName.length)];
        // remove " CPU"
        cpuName = [cpuName stringByReplacingOccurrencesOfString:@" CPU" withString:@""];
        // remove "(R)"
        cpuName = [cpuName stringByReplacingOccurrencesOfString:@"(R)" withString:@""];
        // remove "(TM)"
        cpuName = [cpuName stringByReplacingOccurrencesOfString:@"(TM)" withString:@""];
        // remove "®"
        cpuName = [cpuName stringByReplacingOccurrencesOfString:@"®" withString:@""];
        // remove "™"
        cpuName = [cpuName stringByReplacingOccurrencesOfString:@"™" withString:@""];
        // remove " @ n.nnGHz"
        cpuName = [cpuName stringByReplacingOccurrencesOfString:@" @ \\d+\\.\\d+\\wHz" withString:@"" options:NSRegularExpressionSearch range:NSMakeRange(0, cpuName.length)];
        // remove trailing whitespace
        cpuName = [cpuName stringByTrimmingTrailingWhitespace];
    }
    return cpuName;
}

//
// extract "2019" from "Copyright © 2016-2019 Katsura Shareware\nAll rights reserved."
//
- (NSString *)copyrightYear
{
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    df.dateFormat = @"yyyy";
    df.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    NSString *copyrightYear = [df stringFromDate:[NSDate date]];
    NSDictionary *infoPlist = [[NSBundle mainBundle] infoDictionary];
    NSString *copyrightString = infoPlist[@"NSHumanReadableCopyright"];
    NSError *error = nil;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\\d{4}-(\\d{4})" options:0 error:&error];
    NSTextCheckingResult *match = [re firstMatchInString:copyrightString options:0 range:NSMakeRange(0, copyrightString.length)];
    if (match)
    {
        NSRange range = [match rangeAtIndex:1];
        copyrightYear = [copyrightString substringWithRange:range];
        KSLog(@"matched! %@", copyrightYear);
    }
    return copyrightYear;
}

- (NSString *)usage
{
    NSString *usage = [DiskUtil usageWithMountInfo:_targetMountInfo];
    return usage;
}
//
// CrystalkDiskMark 6.0.2 text output example:
// https://linustechtips.com/main/topic/1009145-what-do-crystaldiskmark-results-actually-mean-samsung-860-evo-sata-iii-samsung-850-evo-usb-30/
//
// -----------------------------------------------------------------------
// CrystalDiskMark 6.0.2 x64 (C) 2007-2018 hiyohiyo
//                           Crystal Dew World : https://crystalmark.info/
// -----------------------------------------------------------------------
// * MB/s = 1,000,000 bytes/s [SATA/600 = 600,000,000 bytes/s]
// * KB = 1000 bytes, KiB = 1024 bytes
//
//
//
//    Sequential Read (Q= 32,T= 1) :   471.231 MB/s
//   Sequential Write (Q= 32,T= 1) :   324.382 MB/s
//   Random Read 4KiB (Q=  8,T= 8) :   393.900 MB/s [  96167.0 IOPS]
//  Random Write 4KiB (Q=  8,T= 8) :   321.975 MB/s [  78607.2 IOPS]
//   Random Read 4KiB (Q= 32,T= 1) :   384.970 MB/s [  93986.8 IOPS]
//  Random Write 4KiB (Q= 32,T= 1) :   326.315 MB/s [  79666.7 IOPS]
//   Random Read 4KiB (Q=  1,T= 1) :    33.779 MB/s [   8246.8 IOPS]
//  Random Write 4KiB (Q=  1,T= 1) :   134.580 MB/s [  32856.4 IOPS]
//
//
//
//   Test : 1024 MiB [C: 26.4% (122.8/465.2 GiB)] (x5)  [Interval=5 sec]
//   Date : 2018/12/15 0:48:36
//     OS : Windows 10  [10.0 Build 17134] (x64)
//

//
// CrystalDiskMark 5.2.0 text output example:
// https://superuser.com/questions/1146194/why-would-crystaldiskmark-report-a-drive-as-faster-in-some-tests-with-bitlocke
//
// -----------------------------------------------------------------------
// CrystalDiskMark 5.2.0 x64 (C) 2007-2016 hiyohiyo
//                            Crystal Dew World : http://crystalmark.info/
// -----------------------------------------------------------------------
// * MB/s = 1,000,000 bytes/s [SATA/600 = 600,000,000 bytes/s]
// * KB = 1000 bytes, KiB = 1024 bytes
//
//    Sequential Read (Q= 32,T= 1) :   140.647 MB/s
//   Sequential Write (Q= 32,T= 1) :    89.082 MB/s
//   Random Read 4KiB (Q= 32,T= 1) :    33.730 MB/s [  8234.9 IOPS]
//  Random Write 4KiB (Q= 32,T= 1) :    15.586 MB/s [  3805.2 IOPS]
//          Sequential Read (T= 1) :   156.034 MB/s
//         Sequential Write (T= 1) :    96.884 MB/s
//    Random Read 4KiB (Q= 1,T= 1) :    10.380 MB/s [  2534.2 IOPS]
//   Random Write 4KiB (Q= 1,T= 1) :    15.317 MB/s [  3739.5 IOPS]
//
//   Test : 1024 MiB [E: 0.4% (26.4/7167.0 MiB)] (x5)  [Interval=5 sec]
//   Date : 2016/11/15 21:52:26
//     OS : Windows 10 Professional [10.0 Build 14393] (x64)
//

- (NSString *)scoreString
{
    //
    // ---------------------------------------------------------------------
    // AmorphousDiskMark 4.0.1 (C) 2016-2023 Katsura Shareware
    //                     Katsura Shareware : https://katsurashareware.com/
    // ---------------------------------------------------------------------
    // * MB/s = 1,000,000 bytes/s [SATA/600 = 600,000,000 bytes/s]
    // * KB = 1,000 bytes, KiB = 1,024 bytes
    // * MB = 1,000,000 bytes, MiB = 1,048,576 bytes
    //
    //   Sequential Read 1MiB (QD=  32) :    471.21 MB/s [  96167.0 IOPS]
    //  Sequantial Write 1MiB (QD=  32) :    324.32 MB/s [  96167.0 IOPS]
    //      Sequential Read 1MiB (QD=1) :    471.25 MB/s [  96167.0 IOPS]
    //     Sequential Write 1MiB (QD=1) :    324.36 MB/s [  96167.0 IOPS]
    //       Random Read 4KiB (QD=  32) :    471.23 MB/s [  96167.0 IOPS]
    //      Random Write 4KiB (QD=  32) :    324.34 MB/s [  96167.0 IOPS]
    //          Random Read 4KiB (QD=1) :    471.27 MB/s [  96167.0 IOPS]
    //         Random Write 4KiB (QD=1) :    324.38 MB/s [  96167.0 IOPS]
    //
    //     Test : 1 GiB  (x5)  [Interval=3 sec]
    //   Volume : Macintosh HD: 93% used (432/465 GiB)
    //   Device : APPLE SSD SM0512F
    //     Date : 2019-10-15T04:09:09Z
    //       OS : macOS 10.14.6 18G103
    //
    // $ sysctl kern.osversion
    // kern.osversion: 11E53
    //
    // $ grep -A1 CFBundleShortVersionString /Applications/AmorphousDiskMark.app/Contents/Info.plist
    // <key>CFBundleShortVersionString</key>
    // <string>1.2</string>
    //
    // $ grep -A1 NSHumanReadableCopyright /Applications/AmorphousDiskMark.app/Contents/Info.plist
    // <key>NSHumanReadableCopyright</key>
    // <string>Copyright © 2016-2019 Katsura Shareware\nAll rights reserved.</string>
    //
    KSLog(@"scores: %@", _scores);
    NSString *scoreHeaderFormat =
    @"---------------------------------------------------------------------\n"
    @"AmorphousDiskMark %@ (C) 2016-%@ Katsura Shareware\n"
    @"                    Katsura Shareware : https://katsurashareware.com/\n"
    @"---------------------------------------------------------------------\n"
    @"* MB/s = 1,000,000 bytes/s [SATA/600 = 600,000,000 bytes/s]\n"
    @"* KB = 1,000 bytes, KiB = 1,024 bytes\n"
    @"* MB = 1,000,000 bytes, MiB = 1,048,576 bytes\n"
    @"\n";
    NSString *scoreFormat =
    @"  Sequential Read 1MiB (QD=%@) : %@ MB/s [%@ IOPS]\n"
    @" Sequential Write 1MiB (QD=%@) : %@ MB/s [%@ IOPS]\n"
    @"     Sequential Read 1MiB (QD=1) : %@ MB/s [%@ IOPS]\n"
    @"    Sequential Write 1MiB (QD=1) : %@ MB/s [%@ IOPS]\n"
    @"      Random Read 4KiB (QD=%@) : %@ MB/s [%@ IOPS]\n"
    @"     Random Write 4KiB (QD=%@) : %@ MB/s [%@ IOPS]\n"
    @"         Random Read 4KiB (QD=1) : %@ MB/s [%@ IOPS]\n"
    @"        Random Write 4KiB (QD=1) : %@ MB/s [%@ IOPS]\n"
    @"\n";
    NSString *scoreFooterFormat =
    @"    Test : %@ (x%@)%@ [Interval=%@ sec]%@\n"
    @"  Volume : %@: %@\n"
    @"  Device : %@\n"
    @"     CPU : %@\n"
    @"    Date : %@\n"
    @"      OS : macOS %@ %@\n"
    @"\n";
    NSString *appVersion = [self appVersion];
    NSString *copyrightYear = [self copyrightYear];
    NSString *sqd = [NSString stringWithFormat:@"%4d", [self testSeqQD].intValue];
    NSString *rqd = [NSString stringWithFormat:@"%4d", [self testRandomQD].intValue];
    NSString *mbpsr[4], *mbpsw[4], *iopsr[4], *iopsw[4];
    for (NSInteger kind = kSeqQTButtonTag; kind <= k4KButtonTag; kind++)
    {
        NSString *rkey = [NSString stringWithFormat:@"%ld,r", (unsigned long)kind];
        NSDictionary *dict = _scores[rkey];
        NSNumber *mbps = dict[@"mbps"];
        mbpsr[kind - 1] = [NSString stringWithFormat:@"%9.2f", mbps.floatValue];
        NSNumber *iops = dict[@"iops"];
        iopsr[kind - 1] = [NSString stringWithFormat:@"%9.1f", iops.floatValue];
        NSString *wkey = [NSString stringWithFormat:@"%ld,w", (unsigned long)kind];
        dict = _scores[wkey];
        mbps = dict[@"mbps"];
        mbpsw[kind - 1] = [NSString stringWithFormat:@"%9.2f", mbps.floatValue];
        iops = dict[@"iops"];
        iopsw[kind - 1] = [NSString stringWithFormat:@"%9.1f", iops.floatValue];
    }
    NSString *testSize = [DiskMark humanReadableBlockSize:[self testSize].unsignedIntegerValue];
    NSString *volumeName = _targetMountInfo[@"daVolumeName"];
    NSString *deviceModel = _targetMountInfo[@"daDeviceModel"];
    NSString *usage = [self usage];
    NSNumber *testIteration = [self testIteration];
    NSNumber *testRandomValues = [self testRandomValues];
    NSString *testValue = @"";
    if (!testRandomValues.boolValue)
    {
        testValue = @" <0Fill>";
    }
    NSNumber *testInterval = [self testInterval];
    NSNumber *testDuration = [self testDuration];
    NSInteger durationLimit = testDuration.integerValue;
    NSString *testLimit = @"";
    if (durationLimit == 0)
    {
        testLimit = @" [No Limit]";
    }
    else if (durationLimit != 5)
    {
        testLimit = [NSString stringWithFormat:@" [Limit=%@ sec]", testDuration];
    }
    NSDateFormatter *RFC3339DateFormatter = [[NSDateFormatter alloc] init];
    RFC3339DateFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    RFC3339DateFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
    RFC3339DateFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    NSString *dateTime = [RFC3339DateFormatter stringFromDate:[NSDate date]];
    NSString *osBuildVersion = [self osBuildVersion];
    NSString *osVersion = [self osVersionWithBuildVersion:osBuildVersion];
    NSString *sh = [NSString stringWithFormat:scoreHeaderFormat, appVersion, copyrightYear];
    NSString *s = [NSString stringWithFormat:scoreFormat, sqd, mbpsr[0], iopsr[0], sqd, mbpsw[0], iopsw[0], mbpsr[1], iopsr[1], mbpsw[1], iopsw[1], rqd, mbpsr[2], iopsr[2], rqd, mbpsw[2], iopsw[2], mbpsr[3], iopsr[3], mbpsw[3], iopsw[3]];
    NSString *cpuName = [self cpuName];
    NSString *sf = [NSString stringWithFormat:scoreFooterFormat, testSize, testIteration, testValue, testInterval, testLimit, volumeName, usage, deviceModel, cpuName, dateTime, osVersion, osBuildVersion];
    return [NSString stringWithFormat:@"%@%@%@", sh, s, sf];
}

- (IBAction)copy:(id)sender
{
#pragma unused(sender)
    
    KSLog(@"%s: entered (sender: %@)", __func__, sender);

    NSString *scoreString = [self scoreString];
    KSLog(@"scoreString: %@", scoreString);
    NSArray *pasteBoardObjects = @[scoreString];
    NSImage *windowImage = [_window windowImage];
    if (windowImage != nil)
    {
        pasteBoardObjects = @[windowImage, scoreString];
    }
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb writeObjects:pasteBoardObjects];
}

#pragma mark --- save/save as ---

- (IBAction)saveDocument:(id)sender
{
#pragma unused(sender)
    
    NSSavePanel *savePanel = [NSSavePanel savePanel];
    
    // capture the window image before the sheet brings the main window behind (diactivates)
    NSData *data = [[_window windowImage] PNGRepresentation];
    
    // only support PNG.
    savePanel.allowedFileTypes = @[@"png"];
    // the user gets to decide to show or hide the file extension.
    savePanel.canSelectHiddenExtension = YES;
    // use the model name as the default save file name.
    savePanel.nameFieldStringValue = _mModelName.stringValue;
    [savePanel beginSheetModalForWindow:_window completionHandler:^(NSInteger result) {
        if (result == NSModalResponseOK)
        {
            // save the image as a PNG file
            [data writeToURL:savePanel.URL atomically:NO];
        }
    }];
}

- (IBAction)saveDocumentAs:(id)sender
{
    [self saveDocument:sender];
}

@end
