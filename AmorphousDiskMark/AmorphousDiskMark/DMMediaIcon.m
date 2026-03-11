//
//  DMMediaIcon.m
//  AmorphousDiskMark
//
//  Created by Hidetomo Katsura on 10/5/19.
//  Copyright © 2019 Katsura Shareware. All rights reserved.
//

#import "DMMediaIcon.h"

@implementation DMMediaIcon

//
// media icons are stored in the Resources directory of the storage
// driver kernel extensions.
//
// /System/Library/Extensions/
// /Library/Extensions/
//
// $ find /System/Library/Extensions -name USBHD.icns
// /System/Library/Extensions/IOSCSIArchitectureModelFamily.kext/Contents/Resources/USBHD.icns
// $ find /System/Library/Extensions -name Internal.icns
// /System/Library/Extensions/IOStorageFamily.kext/Contents/Resources/Internal.icns
//

static NSMutableDictionary *sMediaBundles;
static NSLock *sMediaBundlesLock;

+ (void)initialize {
    if (sMediaBundles == nil) {
        NSMutableDictionary *md = [NSMutableDictionary dictionary];
        // pre-cache known media icon sources
        NSDictionary *preCache = @{@"com.apple.iokit.IOSCSIArchitectureModelFamily": @"/System/Library/Extensions/IOSCSIArchitectureModelFamily.kext", @"com.apple.iokit.IOStorageFamily": @"/System/Library/Extensions/IOStorageFamily.kext"};
        for (NSString *key in preCache) {
            NSString *path = preCache[key];
            NSBundle *b = [NSBundle bundleWithPath:path];
            if (b != nil) {
                [md setObject:b forKey:key];
            }
        }
        sMediaBundles = md;
    }
    if (sMediaBundlesLock == nil) {
        sMediaBundlesLock = [[NSLock alloc] init];
    }
}

//
// scan /S/L/E/ and /L/E/ and find the kernel extension bundle (.kext) with the given
// bundle identifier.
//
// the DriverKit (/System/Library/DriverExtensions/, /Library/DriverExtensions/)
// on macOS 10.15 may introduce new paths to search.
//
+ (NSBundle *)bundleWithIdentifier:(NSString *)identifier {
    // sanity check
    if (identifier.length == 0) {
        return nil;
    }

    // check the cached bundles first
    [sMediaBundlesLock lock];
    NSBundle *b = sMediaBundles[identifier];
    [sMediaBundlesLock unlock];
    if (b != nil) {
        return b;
    }

    // not in the cache. do search...
    NSFileManager *fm = [[NSFileManager alloc] init];
    NSArray *dirs = @[@"/System/Library/Extensions", @"/Library/Extensions"];
    BOOL found = NO;
    for (NSString *dir in dirs) {
        // shallow directory search with contentsOfDirectoryAtPath:
        NSArray<NSString *> *a = [fm contentsOfDirectoryAtPath:dir error:NULL];
        for (NSString *path in a) {
            b = [NSBundle bundleWithPath:[dir stringByAppendingPathComponent:path]];
            if ([identifier isEqualToString:b.bundleIdentifier]) {
                found = YES;
                break;
            }
        }
        if (found) {
            break;
        }
    }
    if (found) {
        [sMediaBundlesLock lock];
        [sMediaBundles setObject:b forKey:identifier];
        [sMediaBundlesLock unlock];
    }
    return b;
}

+ (NSImage *)iconWithDictionary:(NSDictionary *)dict {
    NSString *bi = dict[@"CFBundleIdentifier"];
    NSString *f = dict[@"IOBundleResourceFile"];
    return [self iconForIdentifier:bi file:f];
}

+ (NSImage *)iconForIdentifier:(NSString *)identifier file:(NSString *)file {
    NSBundle *b = [self bundleWithIdentifier:identifier];
    NSImage *i = [b imageForResource:file.stringByDeletingPathExtension];
    return i;
}

@end
