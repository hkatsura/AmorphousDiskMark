//
//  DiskMark.h
//  AmorphousDiskMark
//
//  Created by Hidetomo Katsura on 10/9/2016.
//  Copyright © 2016 Katsura Shareware. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "Common.h"

//
// CDM uses the Microsoft diskspd command.
//
// Wikipida: https://en.wikipedia.org/wiki/Diskspd
// pdf:      https://github.com/Microsoft/diskspd/blob/master/DiskSpd_Documentation.pdf
// github:   https://github.com/microsoft/diskspd
//

//
// based on the arguments Microsoft's diskspd command takes,
// we need the followings in order to run somewhat compatible
// disk benchmarks with CrystalDiskMark which uses the diskspd
// implementation.
//
// 1. -b: block size: 1M, 128K, or 4K
// 2. -d: test duration: hardcoded to 5 seconds
// 3. -o: queue depth: 1, 2, 4, 8, 16, 32, 64, 128, 256, 512
// 4. -t: thread: 1, ..., 64
// 5. -W: warmup time: 5 seconds
// 6. -r: random
// 7. -S: disable software caching
// 8. -w: write percentage: 0: no writes (i.e. read test), 100: 100% writes (i.e. write test)
//
// and the number of test runs (default: 5 times), test size (default: 1 GiB), and the target storage.
//
// CrystalDiskMark
//  * Multi Seq: -b128K, -d5, -oQQQ, -tTTT, -W, -S, -wWWW
//  * Multi 4K: -b4K, -d5, -oQQQ, -tTTT, -W, -r, -S, -wWWW
//  * Single Seq: -b1M, -d5, -o1, -t1, -W, -S, -wWWW
//  * Single 4K: -b4K, -d5, -o1, -t1, -W, -r, -S, -wWWW
//  QQQ: number of queues, TTT: number of threads, WWW: Read=0%, Write=100%
//
// "-d5" means that the test "duration" is limited to 5 seconds. this is why CDM doesn't have
// the lengthy test issue with the slow hard drive 4K tests.
//   https://github.com/Microsoft/diskspd/wiki/Command-line-and-parameters
//

//
// i made a design decision to use QD=1 ... 1024 instead of the max Q512T64 (QD=32K)
// approach which is somewhat difficult to do on macOS due to a lack of async i/o
// API with a completion callback.
//
// the number of maximum threads per task is 2048 on macOS as of this writing. this
// limits the mamxium number of QDs (queue depths).
//
// if needed, i would need to use child processes to run more i/o requets from more
// than 2048 threads. it might become diffcult to measure accurate results.
//
// the maximum number of threads per system is 10,240 as of this writing.
//
// $ sysctl kern.num_threads kern.num_taskthreads
// kern.num_threads: 10240
// kern.num_taskthreads: 2048
//
// katsura 10/16/2016
//
// NOTE: POSIX AIO (Asynchronous I/O), aio.h, on macOS only supports only 16 queues.
//       #define AIO_LISTIO_MAX 16
//

// Test buttons
enum
{
    kAllTestKind,
    kSeqQTTestKind,
    kSeqTestKind,
    k4KQTTestKind,
    k4KTestKind
};

extern NSString *DMIsRandom;
extern NSString *DMInterval;

extern NSString *DMSeqQD;
extern NSString *DMRandomQD;

extern NSString *DMSeqQueue;
extern NSString *DMSeqThread;
extern NSString *DMRandomQueue;
extern NSString *DMRandomThread;

extern NSString *DMIteration;
extern NSString *DMMiBSize;
extern NSString *DMPath;

extern NSString *DMKind;
extern NSString *DMBlockSize;

extern NSString *DMUnitType;

extern NSString *DMDuration;

@class DiskMark;

@protocol DiskMarkDelegate <NSObject>

- (void)didProgressDiskMark:(DiskMark *)diskMark progress:(NSDictionary *)progress;
- (void)didMeasureDiskMark:(DiskMark *)diskMark measurements:(NSDictionary *)measurements;
- (void)didFinishDiskMark:(DiskMark *)diskMark withError:(NSError *)error;

@end

@interface DiskMark : NSObject

+ (NSString *)humanReadableBlockSize:(uint64_t)blocksize;
+ (NSString *)humanReadableUsageWithMountInfo:(NSDictionary *)mount;

+ (id)diskMarkWithAttributes:(NSDictionary *)attrs delegate:(id <DiskMarkDelegate>)delegate;

- (id)initWithAttributes:(NSDictionary *)attrs delegate:(id <DiskMarkDelegate>)delegate;

- (void)stop;
- (void)waitUntilStop;

- (BOOL)isRunning;

@end
