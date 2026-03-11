//
//  DiskUtil.h
//  AmorphousDiskMark
//
//  Created by Hidetomo Katsura on 10/8/2016.
//  Copyright © 2016 Katsura Shareware. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "Common.h"

@class DiskUtil;

@protocol DiskUtilDelegate <NSObject>

- (void)didMountDiskUtil:(DiskUtil *)diskUtil volume:(NSDictionary *)volume;
- (void)didUnmountDiskUtil:(DiskUtil *)diskUtil volume:(NSDictionary *)volume;
- (void)didChangeDiskUtil:(DiskUtil *)diskUtil volume:(NSDictionary *)volume;

@end

@interface DiskUtil : NSObject

@property (assign) DASessionRef daSession;
@property (strong) NSArray<NSDictionary *> *mountInfo;

+ (instancetype)diskUtilWithDelegate:(id <DiskUtilDelegate>)delegate;

+ (NSError *)warmupPath:(NSString *)path;
+ (NSString *)testFilePathForDirectory:(NSString *)directory;

+ (NSString *)localizedFileSystemNameForKind:(NSString *)fstype type:(NSString *)type;
+ (NSString *)humanReadableSize:(uint64_t)size;

+ (NSString *)volumeNameAtPath:(NSString *)path;
+ (NSString *)mountPointForPath:(NSString *)path;

+ (NSString *)usageWithMountInfo:(NSDictionary *)mount;

@end
