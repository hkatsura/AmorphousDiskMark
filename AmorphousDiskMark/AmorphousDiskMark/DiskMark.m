//
//  DiskMark.m
//  AmorphousDiskMark
//
//  Created by Hidetomo Katsura on 10/9/2016.
//  Copyright © 2016-2020 Katsura Shareware. All rights reserved.
//

//
// reference:
//  CrystalDiskMark finishes "All" tests with 1 iteration, 0 interval, 1GiB
//  on Samsung 840 EVO 500GB SSD in about 90 seconds.
//
#import "DiskMark.h"
#import "DiskUtil.h"

#include <stdlib.h>
#include <stdatomic.h>
#include <pthread.h>
#include <sys/mman.h>
#include <mach/mach_time.h>


//
// randomSegments
//  the test file size won't be more than 16 TiB anytime soon. so, a 32-bit index should
//  be sufficient for now. and at that point, the block size probably won't be 4KiB.
//
//  16 TiB test file size ==> 4,294,967,296 segments @ 4KiB
//  50 GiB test file size ==> 13,107,200 segments @ 4KiB (32-bit: 4,294,967,296, 16-bit: 65,536)
//

@interface NSMutableArray (DiskMark)

- (float)median;
- (float)max;
- (float)min;

@end

@implementation NSMutableArray (DiskMark)

- (float)median
{
    // the array contains NSNumber elements
    NSArray *array = [self sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        return [obj1 compare:obj2];
    }];
    
    KSLog(@"%s: sorted array: %@", __func__, array);
    
    NSUInteger c = array.count;
    if (c == 0)
    {
        return 0.0;
    }
    else if (c & 1)
    {
        KSLog(@"%s: className: %@", __func__, [array[0] className]);
        // odd
        //
        // 0  1  2
        // 12 13 14
        //    ^^
        //    13
        return [array[c / 2] floatValue];
    }
    else
    {
        KSLog(@"%s: className: %@", __func__, [array[0] className]);
        // even (need to calculate the average
        //
        // 0  1  2  3
        // 12 13 14 15
        //    ^^ ^^
        //    13.50 <== (13 + 14) / 2
        NSUInteger i = c / 2;
        return ([array[i - 1] floatValue] + [array[i] floatValue]) / 2;
    }
}

- (float)max
{
    return [[self valueForKeyPath:@"@max.self"] floatValue];
}

- (float)min
{
    return [[self valueForKeyPath:@"@min.self"] floatValue];
}

@end

@interface DiskMark ()

@property (strong) NSDictionary *attrs;
@property (strong) id <DiskMarkDelegate> delegate;

@property (assign) BOOL all;  // YES: all tests, NO: individual test
@property (assign) BOOL write;  // YES: write, NO: read
@property (assign) BOOL stopped;
@property (assign) BOOL done;  // YES: when the test thread completes

@property (assign) BOOL timedOut;  // set to YES by the 5-second duration limit timer
@property (strong) NSTimer *timeOutTimer;

@property (strong) NSError *error;

@property (assign) NSInteger kind;  // test kind: all, seqQT, 4kQT, seq, 4k
@property (assign) NSInteger run;   // current run count
@property (assign) NSInteger runs;  // requested total number of runs

@property (strong) NSString *testFilePath;
@property (assign) int fd;
@property (assign) uint64_t testSize;
@property (assign) uint64_t blocksize;
@property (assign) void *wired;
@property (assign) uint64_t wiredSize;
@property (assign) BOOL malloced;
@property (assign) void *randomSegments;  // array of uint32_t
@property (assign) uint64_t randomSegmentSize;
@property (assign) BOOL randomSegmentMalloced;

@property (assign) double timebase;

@property (strong) NSMutableArray *mbpsReadScores;
@property (strong) NSMutableArray *iopsReadScores;
@property (strong) NSMutableArray *mbpsWriteScores;
@property (strong) NSMutableArray *iopsWriteScores;

@property (strong) NSLocale *locale;

// app nap
@property (strong) id <NSObject> activity;

@end

@implementation DiskMark

// if you are changing the user default key name (DMIteration, DMMiBSize), make sure to change the key path in MainMenu.xib as well.

// 3.0: changed the default interation and size from 1x512MiB to 5x1GiB to match CDM7.
//      changed the default interval from 3 seconds to 5 seconds to match CDM7.
//      changed the seuential (multi-thread) test block size from 128 KiB to 1 MiB to match CDM7.
//      changed the default sequential queue depth from 32 to 8 to match CDM7.
//      changed the default random queue depth from 32 to 64 to try to get slightly closer to CDM7 Q32/T16 (i.e. 32 x 16 = 512).

NSString *DMIsRandom = @"DMIsRandom";
NSString *DMInterval = @"DMIntervalV3";

NSString *DMSeqQD = @"DMSeqQDV3";
NSString *DMRandomQD = @"DMRandomQDV3";

//NSString *DMSeqQueue = @"DMSeqQueue";
//NSString *DMSeqThread = @"DMSeqThread";
//NSString *DMRandomQueue = @"DMRandomQueue";
//NSString *DMRandomThread = @"DMRandomThread";

NSString *DMIteration = @"DMIterationV3";
NSString *DMMiBSize = @"DMMiBSizeV3";
NSString *DMPath = @"DMPath";

NSString *DMKind = @"DMKind";

NSString *DMUnitType = @"DMUnitType";

NSString *DMDuration = @"DMDuration";

+ (instancetype)diskMarkWithAttributes:(NSDictionary *)attrs delegate:(id <DiskMarkDelegate>)delegate
{
    KSLog(@"%s: attrs: %@, delegate: %@", __func__, attrs, delegate);
    return [[DiskMark alloc] initWithAttributes:attrs delegate:delegate];
}

// Durstenfeld's shuffle algorithm
- (void)shuffle
{
    if (_randomSegmentSize == 0)
    {
        // not a random read/write test. just return.
        return;
    }
    
    uint32_t *p = _randomSegments;
    uint32_t segments = (uint32_t)(_testSize / (4 * KiB));
    for (uint32_t i = segments - 1; i > 0; i--)
    {
        // Pick a random index from 0 to i (inclusive)
        uint32_t j = arc4random_uniform((uint32_t)(i + 1));
        uint32_t t = p[j];
        p[j] = p[i];
        p[i] = t;
    }
}

- (void)fillValues
{
    if ([_attrs[DMIsRandom] boolValue])
    {
        arc4random_buf(_wired, _wiredSize);
    }
    else
    {
        bzero(_wired, _wiredSize);
    }
    
#if DO_LOG
    const uint8_t *cp = _wired;
    KSLog(@"%s: wired[%p]: start: %02X %02X %02X %02X", __func__, _wired, cp[0], cp[1], cp[2], cp[3]);
    KSLog(@"%s: wired[%p]: end: %02X %02X %02X %02X", __func__, _wired, cp[_wiredSize - 4], cp[_wiredSize - 3], cp[_wiredSize - 2], cp[_wiredSize - 1]);
#endif
}

- (void)wire
{
    int prot = PROT_READ | PROT_WRITE;
    int flags = MAP_ANON | MAP_PRIVATE;
    
    //void * mmap(void *addr, size_t len, int prot, int flags, int fd, off_t offset);
    if (_randomSegmentSize != 0)
    {
        _randomSegments = mmap(NULL, _randomSegmentSize, prot, flags, VM_MAKE_TAG(VM_MEMORY_APPLICATION_SPECIFIC_1), 0);
        if (MAP_FAILED == _randomSegments)
        {
            KSLog(@"errno: %d \"%s\"", (int)errno, strerror(errno));
            // mmap() failed. try valloc() which allocates a page-aligned memry block.
            _randomSegments = valloc(_randomSegmentSize);
            _randomSegmentMalloced = YES;
        }
        
        KSLog(@"calling mlock (randomSegments: %p, length: %lld)...", _randomSegments, _randomSegmentSize);
        int r = mlock(_randomSegments, _randomSegmentSize);
        if ((r != 0) || DO_LOG)
        {
            KSLog(@"mlock(randomSegments): result: %d", r);
        }
        
        // set sequencial segment indexes
        uint32_t *p = _randomSegments;
        uint32_t segments = (uint32_t)(_testSize / (4 * KiB));
        for (uint32_t i = 0; i < segments; i++)
        {
            *p++ = i;
        }
        
        // then, shuffle
        [self shuffle];
    }
    
    _wired = mmap(NULL, _wiredSize, prot, flags, VM_MAKE_TAG(VM_MEMORY_APPLICATION_SPECIFIC_1 + 1), 0);
    KSLog(@"wired: %p", _wired);
    if (MAP_FAILED == _wired)
    {
        KSLog(@"errno: %d \"%s\"", (int)errno, strerror(errno));
        // mmap() failed. try valloc() which allocates a page-aligned memry block.
        _wired = valloc(_wiredSize);
        _malloced = YES;
    }
    
    KSLog(@"calling mlock (wired: %p, length: %lld)...", _wired, _wiredSize);
    int r = mlock(_wired, _wiredSize);
    if ((r != 0) || DO_LOG)
    {
        KSLog(@"mlock(wired): result: %d", r);
    }
    
    // fill random or zero values
    [self fillValues];
}

- (instancetype)initWithAttributes:(NSDictionary *)attrs delegate:(id <DiskMarkDelegate>)delegate
{
    self = [super init];
    if (self != nil)
    {
        mach_timebase_info_data_t mti;
        kern_return_t kr = mach_timebase_info(&mti);
        KSLog(@"kr: %d", (int)kr);
        _timebase = (kr == KERN_SUCCESS)? ((double)mti.numer / (double)mti.denom): 1.0;
        KSLog(@"timebase: %f", _timebase);

        self.attrs = attrs;
        self.delegate = delegate;
        self.mbpsReadScores = [NSMutableArray array];
        self.iopsReadScores = [NSMutableArray array];
        self.mbpsWriteScores = [NSMutableArray array];
        self.iopsWriteScores = [NSMutableArray array];

        self.locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];
        
        self.testFilePath = [DiskUtil testFilePathForDirectory:_attrs[DMPath]];
        KSLog(@"%s: testFilePath random file: %@", __func__, _testFilePath);
        
        _testSize = [_attrs[DMMiBSize] unsignedIntegerValue];

        NSInteger kind = [attrs[DMKind] integerValue];
        if (kind == kAllTestKind)
        {
            _all = YES;

            // set the first test kind (SeqQT)
            _kind = kSeqQTTestKind;
        }
        else
        {
            _all = NO;
            _kind = kind;
        }

        _wiredSize = 1 * MiB;
        _randomSegmentSize = ((kind == kAllTestKind) || (kind == k4KQTTestKind) || (kind == k4KTestKind))? _testSize / (4 * KiB) * sizeof(uint32_t): 0;
        [self wire];
        
        // DISPATCH_QUEUE_PRIORITY_HIGH
        // DISPATCH_QUEUE_PRIORITY_DEFAULT
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            [self start];
        });
    }
    
    return self;
}

- (void)unwire
{
    int r;

    if (_wired != NULL)
    {
        r = munlock(_wired, _wiredSize);
        if ((r != 0) || DO_LOG)
        {
            KSLog(@"munlock(wired): result: %d", r);
        }

        if (_malloced)
        {
            free(_wired);
        }
        else
        {
            r = munmap(_wired, _wiredSize);
            if ((r != 0) || DO_LOG)
            {
                KSLog(@"munmap(wired): result: %d", r);
            }
        }
        _wired = NULL;
    }
    
    if (_randomSegments != NULL)
    {
        r = munlock(_randomSegments, _randomSegmentSize);
        if ((r != 0) || DO_LOG)
        {
            KSLog(@"munlock(randomSegments): result: %d", r);
        }
        
        if (_randomSegmentMalloced)
        {
            free(_randomSegments);
        }
        else
        {
            r = munmap(_randomSegments, _randomSegmentSize);
            if ((r != 0) || DO_LOG)
            {
                KSLog(@"munmap(randomSegments): result: %d", r);
            }
        }
        _randomSegments = NULL;
    }
}

- (void)dealloc
{
    KSLog(@"%s: called", __func__);

    [self stop];
    [self waitUntilStop];

    [self unwire];
}

//
// Sequential Read/Write 1MiB (default: QD32)
// Sequential Read/Write 1MiB (default: QD1)
// Random Read/Write 4KiB (default: QD64)
// Random Read/Write 4KiB (default: QD1)
//
- (NSString *)testKindString
{
    NSString *string = @"";
    NSString *readWrite = _write? NSLocalizedString(@"Write", "Write"): NSLocalizedString(@"Read", "Read");
    switch (_kind)
    {
        case kSeqQTTestKind:
        {
            string = [NSString stringWithFormat:NSLocalizedString(@"Sequential %@", "Sequential %@"), readWrite];
            break;
        }
        case k4KQTTestKind:
        {
            string = [NSString stringWithFormat:NSLocalizedString(@"Random %@", "Random %@"), readWrite];
            break;
        }
        case kSeqTestKind:
        {
            string = [NSString stringWithFormat:NSLocalizedString(@"Sequential %@", "Sequential %@"), readWrite];
            break;
        }
        case k4KTestKind:
        {
            string = [NSString stringWithFormat:NSLocalizedString(@"Random %@", "Random %@"), readWrite];
            break;
        }
        default:
        {
            // this should never happen.
            break;
        }
    }
    
    return string;
}

- (void)sendPrepareMessage
{
    // "Preparing Sequential Read..."
    NSString *message = [NSString stringWithFormat:NSLocalizedString(@"Preparing %@...", "Preparing %@..."), [self testKindString]];
    KSLog(@"%s: message: %@", __func__, message);

    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_delegate didProgressDiskMark:self progress:@{@"message": message, @"progress": @(0)}];
    });
}

- (void)sendIterationMessage
{
    // "Sequential Read [1/5]"
    NSString *message = [NSString stringWithFormat:NSLocalizedString(@"%@ [%d/%d]", "%@ [%d/%d]"), [self testKindString], (int)_run, (int)_runs];
    NSInteger progress = 100 * _run / _runs;
    KSLog(@"%s: message: %@ (progress: %d)", __func__, message, (int)progress);

    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_delegate didProgressDiskMark:self progress:@{@"message": message, @"progress": @(progress)}];
    });
}

// CDM: "Interval Time 1/3 sec"
- (void)sendIntervalMessage:(NSInteger)seconds of:(NSInteger)interval
{
    // "Interval 1/5 second"
    NSString *message = [NSString stringWithFormat:NSLocalizedString(@"Interval %d/%d second", "Interval %d/%d second"), (int)seconds, (int)interval];
    KSLog(@"%s: message: %@", __func__, message);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_delegate didProgressDiskMark:self progress:@{@"message": message}];
    });
}

//
// CDM7:
//   two fraction digits for MB/s. "0.00", "10.00", "100.00", "1000.00", up to "99999.99" (total 7 digits).
//   three fraction digits for GB/s. "0.000", "10.000", ..., up to "9999.999" (total 7 digits).
//   one fraction digit for IOPS. "0.0", "1.0", ..., "10000.0", up to "999999.9" (total 7 digits).
//   two franction digits for microseconds (latency). up to "99999.99" (total 7 digits).
//
// CDM8:
//   two fraction digits for MB/s. "0.00", "10.00", "100.00", "1000.00", up to "9999999.99" (total 9 digits).
//   three fraction digits for GB/s. "0.000", "10.000", ..., up to "999999.999" (total 9 digits).
//   one fraction digit for IOPS. "0.00", "1.00", ..., "10000.00", up to "9999999.99" (total 9 digits).
//   two franction digits for microseconds (latency). up to "9999999.99" (total 9 digits).
//
- (NSString *)mbpsString:(float)result
{
    NSNumberFormatter *nf = [[NSNumberFormatter alloc] init];
    nf.locale = _locale;
    nf.minimumIntegerDigits = 1;
    nf.minimumFractionDigits = 2;
    nf.maximumFractionDigits = 2;
    nf.usesGroupingSeparator = YES;
    nf.numberStyle = NSNumberFormatterDecimalStyle;
    return [NSString stringWithFormat:@"%@ MB/s", [nf stringFromNumber:@(result)]];
}

+ (NSString *)humanReadableBlockSize:(uint64_t)blocksize
{
    if (blocksize < KiB)
    {
        return [NSString stringWithFormat:NSLocalizedString(@"%lld B", "%lld B"), blocksize];
    }
    else if (blocksize < MiB)
    {
        return [NSString stringWithFormat:NSLocalizedString(@"%lld KiB", "%lld KiB"), blocksize / KiB];
    }
    else if (blocksize < GiB)
    {
        return [NSString stringWithFormat:NSLocalizedString(@"%lld MiB", "%lld MiB"), blocksize/ MiB];
    }
    else if (blocksize < TiB)
    {
        return [NSString stringWithFormat:NSLocalizedString(@"%lld GiB", "%lld GiB"), blocksize/ GiB];
    }
    else
    {
        return [NSString stringWithFormat:NSLocalizedString(@"%lld TiB", "%lld TiB"), blocksize/ TiB];
    }
}

+ (NSString *)humanReadableUsageWithMountInfo:(NSDictionary *)mount
{
    if (mount == nil)
    {
        return @"0/0 MiB";
    }
    NSNumber *size = mount[@"size"];
    NSNumber *freeSize = mount[@"freeSize"];
    uint64_t totalSize = size.unsignedIntegerValue;
    uint64_t availableSize = freeSize.unsignedIntegerValue;
    uint64_t usedSize = totalSize - availableSize;
    // %@/%@ MiB
    NSString *usedString, *totalString;
    if (totalSize < KiB)
    {
        usedString = [NSString stringWithFormat:@"%lld", usedSize];
        totalString = [NSString stringWithFormat:NSLocalizedString(@"%lld B", "%lld B"), totalSize];
    }
    else if (totalSize < MiB)
    {
        usedString = [NSString stringWithFormat:@"%lld", usedSize / KiB];
        totalString = [NSString stringWithFormat:NSLocalizedString(@"%lld KiB", "%lld KiB"), totalSize / KiB];
    }
    else if (totalSize < GiB)
    {
        usedString = [NSString stringWithFormat:@"%lld", usedSize / MiB];
        totalString = [NSString stringWithFormat:NSLocalizedString(@"%lld MiB", "%lld MiB"), totalSize/ MiB];
    }
    else if (totalSize < TiB)
    {
        usedString = [NSString stringWithFormat:@"%lld", usedSize / GiB];
        totalString = [NSString stringWithFormat:NSLocalizedString(@"%lld GiB", "%lld GiB"), totalSize/ GiB];
    }
    else
    {
        usedString = [NSString stringWithFormat:@"%lld", usedSize / TiB];
        totalString = [NSString stringWithFormat:NSLocalizedString(@"%lld TiB", "%lld TiB"), totalSize/ TiB];
    }
    return [NSString stringWithFormat:@"%@/%@", usedString, totalString];
}

- (NSString *)iopsString:(float)iops
{
    NSNumberFormatter *nf = [[NSNumberFormatter alloc] init];
    nf.locale = _locale;
    nf.minimumIntegerDigits = 1;
    nf.minimumFractionDigits = 1;
    nf.maximumFractionDigits = 1;
    nf.usesGroupingSeparator = YES;
    nf.numberStyle = NSNumberFormatterDecimalStyle;
    NSString *iopsString = [nf stringFromNumber:@(iops)];
    return [NSString stringWithFormat:NSLocalizedString(@"%@ IOPS @ %@", "%@ IOPS @ %@"), iopsString, [DiskMark humanReadableBlockSize:_blocksize]];
}

- (void)sendResult
{
#if 0
    // fake results
    
    float mbps = 345.6;  // MB/s
    float iops = 70000.0;  // IOPS
    
    // hack. remove me. this is for a nice screenshot just like CrystalDiskMark.
    switch (_kind)
    {
        case kSeqQTTestKind:
        {
            mbps = _write? 1314.0: 2691.0;  // MB/s
            break;
        }
        case k4KQTTestKind:
        {
            mbps = _write? 1270.0: 1917.0;  // MB/s
            break;
        }
        case kSeqTestKind:
        {
            mbps = _write? 1263.0: 1276.0;  // MB/s
            break;
        }
        case k4KTestKind:
        {
            mbps = _write? 357.1: 38.10;  // MB/s
            break;
        }
        default:
        {
            // this should never happen.
            break;
        }
    }
#else
    float mbps;  // MB/s
    float iops;  // IOPS
    
    // return the median value
    if (_write)
    {
        mbps = [_mbpsWriteScores median];
        iops = [_iopsWriteScores median];
        KSLog(@"write mbps: min: %f, max: %f", [_mbpsWriteScores min], [_mbpsWriteScores max]);
        KSLog(@"write iops: min: %f, max: %f", [_iopsWriteScores min], [_iopsWriteScores max]);
    }
    else
    {
        mbps = [_mbpsReadScores median];
        iops = [_iopsReadScores median];
        KSLog(@"read mbps: min: %f, max: %f", [_mbpsReadScores min], [_mbpsReadScores max]);
        KSLog(@"read iops: min: %f, max: %f", [_iopsReadScores min], [_iopsReadScores max]);
    }
#endif
// debug. fake 100x results.
#if 0
    NSLog(@"DEBUGGING... multiplying the results by 100!");
    mbps *= 100.;
    iops *= 100.;
#endif
    NSString *mbpsString = [self mbpsString:mbps];
    NSString *iopsString = [self iopsString:iops];
    NSString *toolTip = [NSString stringWithFormat:@"%@\n%@", mbpsString, iopsString];
    NSUInteger kind = _kind;
    BOOL isRead = !_write;

    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_delegate didMeasureDiskMark:self measurements:@{@"kind": @(kind), @"isRead": @(isRead), @"mbps": @(mbps), @"iops": @(iops), @"tooltip": toolTip}];
    });
}

typedef struct test_thread_input
{
    uint64_t blocksize;
    void *wired;
    uint64_t wiredsize;
    atomic_size_t *sc;
    size_t segments;
    uint32_t *randomSegments;
    int fd;
    int isRead;  // zero: write, non-zero: read
    int isRandom; // zero: sequencial, non-zero: random
    BOOL *pStopped;
    BOOL *pTimedOut;
} test_thread_input;

typedef struct test_thread_info
{
    const test_thread_input *i;
    int o;
} test_thread_info;

static void testThread(void *p)
{
    test_thread_info *tti = p;
    int r = 0;

    DMPrintf("%s [%p]: begin thread\n", __func__, pthread_self());

    while (!(*tti->i->pStopped))
    {
        size_t s = atomic_fetch_add(tti->i->sc, 1);
        if (s < tti->i->segments)
        {
            ssize_t ss;
            
            //printf("%s: s: segment: %lld\n", __func__, (uint64_t)s);
            if (tti->i->randomSegments)
            {
                // convert a sequential segment index to a random segment index
                s = tti->i->randomSegments[s];
                //printf("%s: random: %lld\n", __func__, (uint64_t)s);
            }
            
            if (tti->i->isRead)
            {
                // ssize_t pread(int d, void *buf, size_t nbyte, off_t offset);
                ss = pread(tti->i->fd, tti->i->wired, tti->i->blocksize, s * tti->i->blocksize);
            }
            else
            {
                // ssize_t pwrite(int fildes, const void *buf, size_t nbyte, off_t offset);
                ss = pwrite(tti->i->fd, tti->i->wired, tti->i->blocksize, s * tti->i->blocksize);
                
                // since this is writing the same block with the same random values,
                // i think a device with deduplicate writes will take adantage of
                // this fact and skip writes (different virtual blocks pointing to
                // one physical block).
                //
                // i might add an option to use different blocks with different
                // random values to avoid the false high performance from the
                // deduplicate.
                //
                // https://en.wikipedia.org/wiki/Flash_memory
                // https://en.wikipedia.org/wiki/Write_amplification
            }

            // check if pread/pwrite returned -1 (error in errno)
            if (ss == -1)
            {
                // pread/pwrite returned -1. stop the test.
                r = errno;
                break;
            }
            else if (*(tti->i->pTimedOut))
            {
                // timed out
                break;
            }
        }
        else
        {
            // the segment count (sc) is beyond the maximum
            // segment index. stop the test.
            break;
        }
    }
    
    tti->o = r;
    
#if DO_LOG
    const uint8_t *cp = tti->i->wired;
    DMPrintf("%s [%p]: wired[%p]: %02X %02X %02X %02X\n", __func__, pthread_self(), cp, cp[0], cp[1], cp[2], cp[3]);
    DMPrintf("%s [%p]: end thread: r: %d\n", __func__, pthread_self(), r);
#endif
}

- (void)timedOut:(NSTimer *)timer
{
#pragma unused(timer)
    KSLog(@"%s: timer: %@", __func__, timer);
    _timedOut = YES;
}

- (void)testWithQD:(NSUInteger)qd random:(BOOL)random
{
    atomic_size_t seg_count = 0;
    pthread_t threads[qd];
    test_thread_info tt[qd];
    test_thread_input tti;
    uint64_t q;
    size_t segments;
    uint64_t start, end, elapsed;
    double seconds;
    int r;
    
    segments = _testSize / _blocksize;
    
    tti.blocksize = _blocksize;
    tti.wired = _wired;
    tti.wiredsize = _wiredSize;
    tti.sc = &seg_count;
    tti.segments = segments;
    tti.fd = _fd;
    tti.isRead = !_write;
    tti.randomSegments = random? _randomSegments: NULL;
    tti.pStopped = &_stopped;
    tti.pTimedOut = &_timedOut;
    
    KSLog(@"%s: starting %s QD=%d %s test", __func__, random? "random": "sequential", (int)qd, _write? "write": "read");
    
    // clear thread array
    memset(threads, 0, sizeof(threads));

    _timedOut = NO;
    NSInteger duration = [_attrs[DMDuration] integerValue];
    if (duration != 0)
    {
        // start the test duration limit timer
        self.timeOutTimer = [NSTimer timerWithTimeInterval:duration target:self selector:@selector(timedOut:) userInfo:nil repeats:NO];
        [[NSRunLoop mainRunLoop] addTimer:_timeOutTimer forMode:NSRunLoopCommonModes];
        KSLog(@"%s: started the timer: %@", __func__, _timeOutTimer);
    }

    start = mach_absolute_time();
    
    // test
    for (q = 0; q < qd; q++)
    {
        tt[q].i = &tti;
        tt[q].o = 0;
        
        // int pthread_create(pthread_t *thread, const pthread_attr_t *attr, void *(*start_routine)(void *), void *arg);
        r = pthread_create(&threads[q], NULL, (void *)&testThread, &tt[q]);
        if ((r != 0) || DO_LOG)
        {
            KSLog(@"%s: pthread_create[%d] returned %d", __func__, (int)q, r);
        }
    }

    // block until all done
    for (q = 0; q < qd; q++)
    {
        pthread_t t = threads[q];
        if (t == NULL)
        {
            NSLog(@"error: pthread_t[%d] was NULL.", (int)q);
            continue;
        }
        
        r = pthread_join(t, NULL);
        if ((r != 0) || DO_LOG)
        {
            KSLog(@"%s: pthread_join[%d] returned %d", __func__, (int)q, r);
        }
        
        // record the first error
        if ((tt[q].o != 0) && (_error == nil))
        {
            _stopped = YES;
            self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:tt[q].o userInfo:@{@"comment": @"Failed to create a test file."}];
        }
    }
    
    if (_write)
    {
        // flush the write buffer
        r = fsync(_fd);
        if ((r != 0) || DO_LOG)
        {
            KSLog(@"%s: fsync: %d", __func__, r);
        }
    }
    
    end = mach_absolute_time();

    // invalided the test duration limit timer
    [_timeOutTimer invalidate];
    self.timeOutTimer = nil;

    elapsed = end - start;
    // convert absolute time ticks to nanoseconds to seconds
    seconds = elapsed * _timebase / 1000000000.0;
    KSLog(@"%s: seconds: %f", __func__, seconds);

    // calcluate the MB/s and IOPS scores
    float mbps, iops;
#if 0
    mbps = _testSize / seconds / MB;
    iops = segments / seconds;
#else
    size_t sc = (seg_count > segments)? segments: seg_count;
    uint64_t testedSize = sc * _blocksize;
    mbps = testedSize / seconds / MB;
    iops = sc / seconds;
    KSLog(@"segments: %d, seg_count: %d, sc: %d", (int)segments, (int)seg_count, (int)sc);
#endif
    KSLog(@"%s: %f MB/s, %f IOPS @ %lld", __func__, mbps, iops, _blocksize);
    if (_write)
    {
        [_mbpsWriteScores addObject:@(mbps)];
        [_iopsWriteScores addObject:@(iops)];
    }
    else
    {
        [_mbpsReadScores addObject:@(mbps)];
        [_iopsReadScores addObject:@(iops)];
    }
}

// run one test (read or write) and update the score arrays (mbps and iops arrays)
- (void)test
{
#if 0
    // do actual test here...
    NSInteger count = 100;
    while (count-- && !_stopped)
    {
        [NSThread sleepForTimeInterval:0.01];
    }
    
    if (!_stopped)
    {
        [self sendResult];
    }
#else
    switch (_kind)
    {
        case kSeqQTTestKind:
        {
            [self testWithQD:[_attrs[DMSeqQD] unsignedIntegerValue] random:NO];
            break;
        }
        case k4KQTTestKind:
        {
            [self testWithQD:[_attrs[DMRandomQD] unsignedIntegerValue] random:YES];
            break;
        }
        case kSeqTestKind:
        {
            [self testWithQD:1 random:NO];
            break;
        }
        case k4KTestKind:
        {
            [self testWithQD:1 random:YES];
            break;
        }
        default:
        {
            // this should never happen.
            break;
        }
    }

    if (!_stopped)
    {
        [self sendResult];
    }
#endif
}

- (void)clearScores
{
    // clear scores before running a different test
    [_mbpsReadScores removeAllObjects];
    [_iopsReadScores removeAllObjects];
    [_mbpsWriteScores removeAllObjects];
    [_iopsWriteScores removeAllObjects];
}

- (void)prepare
{
    const char *path = [_testFilePath UTF8String];
    
    switch (_kind)
    {
        case kSeqQTTestKind:
        {
            _blocksize = 1 * MiB;
            break;
        }
        case k4KQTTestKind:
        {
            _blocksize = 4 * KiB;
            break;
        }
        case kSeqTestKind:
        {
            _blocksize = 1 * MiB;
            break;
        }
        case k4KTestKind:
        {
            _blocksize = 4 * KiB;
            break;
        }
        default:
        {
            // this should never happen.
            _blocksize = 4 * KiB;
            break;
        }
    }
    
    // clean up any open file.
    // after the read test, the read file is still open at this point.
    [self cleanup];
    
    fstore_t fst;

    fst.fst_flags = F_ALLOCATECONTIG | F_ALLOCATEALL;
    fst.fst_posmode = F_PEOFPOSMODE;
    fst.fst_offset = 0;
    fst.fst_length = _testSize;

    // open a file
    if (_write)
    {
        int r;
        
        // open a file for writing
        KSLog(@"%s: creating a write test file %s...", __func__, path);
        _fd = open(path, O_CREAT | O_EXCL | O_RDWR, S_IRUSR | S_IWUSR);
        KSLog(@"%s: fd: %d", __func__, _fd);

        r = fcntl(_fd, F_PREALLOCATE, &fst); // enable PREALLOCATE
        if ((r != 0) || DO_LOG)
        {
            KSLog(@"%s: fcntl(F_PREALLOCATE, %lld): result: %d", __func__, (uint64_t)fst.fst_length, r);
        }
        
        r = fcntl(_fd, F_NOCACHE, 1); // enable NOCACHE (i.e. disable cache)
        if ((r != 0) || DO_LOG)
        {
            KSLog(@"%s: fcntl(F_NOCACHE, 1 /* disabled cache */): result: %d", __func__, r);
        }
    }
    else
    {
        int r;
        
        // open (create) a file for reading (write a file)
        KSLog(@"%s: creating a read test file %s...", __func__, path);
        _fd = open(path, O_CREAT | O_EXCL | O_RDWR, S_IRUSR | S_IWUSR);
        if (_fd < 0)
        {
            r = errno;
            
            _stopped = YES;
            self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:r userInfo:@{@"comment": @"Failed to create a test file."}];
            r = close(_fd);
            if ((r != 0) || DO_LOG)
            {
                KSLog(@"%s: close(%d): returned: %d", __func__, _fd, r);
            }
            return;
        }
        
        r = fcntl(_fd, F_PREALLOCATE, &fst); // enable PREALLOCATE
        if ((r != 0) || DO_LOG)
        {
            KSLog(@"%s: fcntl(F_PREALLOCATE, %lld): result: %d", __func__, (uint64_t)fst.fst_length, r);
        }
        
        r = fcntl(_fd, F_NOCACHE, 1); // enable NOCACHE (i.e. disable cache)
        if ((r != 0) || DO_LOG)
        {
            KSLog(@"%s: fcntl(F_NOCACHE, 1 /* disabled cache */): result: %d", __func__, r);
        }
        
        size_t segments = _testSize / _wiredSize;
        r = 0;
        for (size_t s = 0; s < segments; s++)
        {
            ssize_t ss = pwrite(_fd, _wired, _wiredSize, s * _wiredSize);
            if (ss != (ssize_t)_wiredSize)
            {
                // failed to write
                r = errno;
                break;
            }
        }
        
        if (r != 0)
        {
            _stopped = YES;
            self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:r userInfo:@{@"comment": @"Failed to create a test file."}];
            r = close(_fd);
            if ((r != 0) || DO_LOG)
            {
                KSLog(@"%s: close(%d): returned: %d", __func__, _fd, r);
            }
            return;
        }
        
        // close the read/write file
        r = close(_fd);
        if ((r != 0) || DO_LOG)
        {
            KSLog(@"%s: close(%d): returned: %d", __func__, _fd, r);
        }
        
        // open it as a "read-only" file
        _fd = open(path, O_RDONLY);
        if (_fd < 0)
        {
            r = errno;
            
            _stopped = YES;
            self.error = [NSError errorWithDomain:NSPOSIXErrorDomain code:r userInfo:@{@"comment": @"Failed to open the test file."}];
            r = close(_fd);
            if ((r != 0) || DO_LOG)
            {
                KSLog(@"%s: close(%d): returned: %d", __func__, _fd, r);
            }
            return;
        }

        r = fcntl(_fd, F_RDAHEAD, 0); // disable F_RDAHEAD
        if ((r != 0) || DO_LOG)
        {
            KSLog(@"%s: fcntl(F_RDAHEAD, 0): result: %d", __func__, r);
        }
        
        r = fcntl(_fd, F_NOCACHE, 1); // enable NOCACHE (i.e. disable cache)
        if ((r != 0) || DO_LOG)
        {
            KSLog(@"%s: fcntl(F_NOCACHE, 1 /* disabled cache */): result: %d", __func__, r);
        }
    }
}

- (void)cleanup
{
    KSLog(@"%s: fd: %d, testSize: %lld", __func__, _fd, _testSize);
    
    int r;
    
    if (_fd > 0)
    {
        //
        // if the write test ended without writing to all blocks,
        // close() will end up flushing the unwritten blocks to
        // the storage.
        //
        // so, truncate the file size to zero, then close in order
        // to avoid unnecessary writes at the end.
        //
        // NOTE: F_PUNCHHOLE is not supported on HFS.
        //
        if (_write)
        {
            //
            // truncating to zero still causes the flush on some
            // Macs (or devices or macOS versions?) for some reason.
            //
            lseek(_fd, 0, SEEK_SET);
            r = ftruncate(_fd, 0);
            if (r != 0)
            {
                KSLog(@"ftruncate(fd): result: %d (errno: %d \"%s\")", r, errno, strerror(errno));
            }
        }

        // close the test file
        r = close(_fd);
        if ((r != 0) || DO_LOG)
        {
            KSLog(@"close(fd): result: %d", r);
        }
        
        // deleting right after closing failed. so, sleep a little here.
        // would sleeping 1 second help?
        [NSThread sleepForTimeInterval:1.0];
        
        // delete the test file
        NSFileManager *fm = [NSFileManager defaultManager];
        NSURL *URL = [NSURL fileURLWithPath:_testFilePath];
        NSError *error = nil;
        if (![fm removeItemAtURL:URL error:&error])
        {
            KSLog(@"%s: error: %@", __func__, error);
        }

        // mark as closed (and removed)
        _fd = -1;
    }
}

// this runs on its own thread
- (void)start
{
    if (@available(macOS 10.9, *))
    {
        // disable app nap
        NSActivityOptions options = NSActivityUserInitiated;
        NSString *reason = @"measuring storage performance";
        _activity = [[NSProcessInfo processInfo] beginActivityWithOptions:options reason:reason];
        KSLog(@"%s: disabled the app nap (activity: %@)", __func__, _activity);
    }

    // start test here
    _done = NO;

ALL_TEST_LOOP:
    // start with the read test (or maybe the write first to create the read file as a side-effect. more efficient. less write)
    _write = NO;

    // run the read test first...
    [self sendPrepareMessage];

    // wake the device if sleeping
    [self warmup];
    if (_stopped)
    {
        goto DONE;
    }

    // prepare for the "read" test
    [self prepare];
    if (_stopped)
    {
        goto DONE;
    }

    // run test for a given number of iterations
    _runs = [_attrs[DMIteration] integerValue];
    
    for (_run = 1; _run <= _runs; _run++)
    {
        [self sendIterationMessage];
        [self test];  // read test
        if (_stopped)
        {
            goto DONE;
        }
        
        // re-shuffle the random segment sequence
        [self shuffle];
    }
    [self waitInterval];
    if (_stopped)
    {
        goto DONE;
    }
    // clean up the read test.
    [self cleanup];

    // then, run the write test.
    _write = YES;
    [self sendPrepareMessage];

    // wake the device if sleeping
    [self warmup];
    if (_stopped)
    {
        goto DONE;
    }

    // prepare for the "write" test
    [self prepare];
    if (_stopped)
    {
        goto DONE;
    }
    
    for (_run = 1; _run <= _runs; _run++)
    {
        // before each write test, change the randam
        // values so that SSDs don't skip writes.
        // i think SSDs might be skipping writes
        // if the same values were given for the
        // same block.
        [self fillValues];

        [self sendIterationMessage];
        [self test];  // read test
        if (_stopped)
        {
            goto DONE;
        }
        
        // re-shuffle the random segment sequence
        [self shuffle];
    }
    
    // if this is an all test, run the next test unless this is the last test.
    // all test sequence: kSeqQTTestKind, kSeqTestKind, k4KQTTestKind, k4KTestKind
    if (!_stopped && _all)
    {
        switch (_kind)
        {
            case kSeqQTTestKind:
            {
                [self cleanup];
                _kind = kSeqTestKind;
                [self waitInterval];
                if (_stopped)
                {
                    goto DONE;
                }
                [self clearScores];
                goto ALL_TEST_LOOP;
            }
            case kSeqTestKind:
            {
                [self cleanup];
                _kind = k4KQTTestKind;
                [self waitInterval];
                if (_stopped)
                {
                    goto DONE;
                }
                [self clearScores];
                goto ALL_TEST_LOOP;
                break;
            }
            case k4KQTTestKind:
            {
                [self cleanup];
                _kind = k4KTestKind;
                [self waitInterval];
                if (_stopped)
                {
                    goto DONE;
                }
                [self clearScores];
                goto ALL_TEST_LOOP;
                break;
            }
            case k4KTestKind:
            {
                // last test
                break;
            }
        }
    }
    
    // done
DONE:
    [self stop];
    [self cleanup];
    _done = YES;
    
    NSError *error = _error;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_delegate didFinishDiskMark:self withError:error];
    });
}

- (void)stop
{
    _stopped = YES;

    if (@available(macOS 10.9, *))
    {
        // enable the app nap
        KSLog(@"%s: enable the app nap (activity: %@)", __func__, _activity);
        if (_activity)
        {
            [[NSProcessInfo processInfo] endActivity:_activity];
            _activity = nil;
        }
    }
}

- (void)waitUntilStop
{
    KSLog(@"%s: block/spin until stop/done", __func__);

    // the test could still be running. wait up to 5 seconds
    NSUInteger count = 50;
    while (!_done && count--)
    {
        KSLog(@"%s: test (%d) is still running. wait for 100ms...", __func__, (int)_kind);
        
        // sleep for 100ms
        [NSThread sleepForTimeInterval:0.1];
    }

    KSLog(@"%s: done. exiting.", __func__);
}

- (void)waitInterval
{
    NSInteger interval = [_attrs[DMInterval] integerValue];
    KSLog(@"%s: interval: %d seconds", __func__, (int)interval);
    NSInteger count = (NSInteger)(interval / 0.1);
    // "3/3 second", "2/3 second", "1/3 second" (, "0/3 second")
    for (NSInteger i = 0; (i < count) && !_stopped; i++)
    {
        // 0 ==> interval seconds
        // ...
        // 10 ==> (interval - 1) seconds
        // ...
        if ((i % 10) == 0)
        {
            [self sendIntervalMessage:(interval - (i / 10)) of:interval];
        }
        [NSThread sleepForTimeInterval:0.1];
    }
}

- (void)warmup
{
    NSInteger count = 30;  // 3 x 0.1 second = 30
    for (NSInteger i = 0; (i < count) && !_stopped; i++)
    {
        if ((i == 0) || (i == 15))
        {
            NSError *error;
            
            // write/delete a file to wake up the device
            //
            // i assume the attempt to write to a sleeping
            // hard drive will cause this call to block.
            //
            // if the target is read-only, warmupPath will
            // return an error.
            error = [DiskUtil warmupPath:_attrs[DMPath]];
            if (error != nil)
            {
                _stopped = YES;
                self.error = error;
            }
        }
        [NSThread sleepForTimeInterval:0.1];
    }
}

- (BOOL)isRunning
{
    //return !_stopped;
    return !_done;
}

#if 0
- (NSDictionary *)a
{
    return nil;
}
#endif

@end
