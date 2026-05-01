//
//  DiskUtil.m
//  AmorphousDiskMark
//
//  Created by Hidetomo Katsura on 10/8/2016.
//  Copyright © 2016 Katsura Shareware. All rights reserved.
//

#import "DiskUtil.h"
#import "DiskMark.h"

#import <DiskArbitration/DiskArbitration.h>

#import <sys/mount.h>

#include <Cocoa/Cocoa.h>

@interface DiskUtil ()

@property (assign) id <DiskUtilDelegate> delegate;

@end

@implementation DiskUtil

// singleton DASessionRef
+ (DASessionRef)daSession
{
    static DASessionRef daSession = NULL;
    
    if (daSession == NULL)
    {
        daSession = DASessionCreate(kCFAllocatorDefault);
    }
    KSLog(@"%s: daSession: %p", __func__, daSession);
    
    return daSession;
}

+ (instancetype)diskUtilWithDelegate:(id <DiskUtilDelegate>)delegate
{
    return [[DiskUtil alloc] initWithDelegate:(id <DiskUtilDelegate>)delegate];
}

+ (NSString *)randomFilename
{
    // Combine two arc4random() calls for 64 bits of entropy instead of 32.
    // This makes accidental collisions essentially impossible and hardens against
    // any attempt to predict the filename in advance.
    uint64_t r = ((uint64_t)arc4random() << 32) | (uint64_t)arc4random();
    return [NSString stringWithFormat:@".us.katsura.adm-%d-%016llx", [[NSProcessInfo processInfo] processIdentifier], r];
}

// i probably should make sure the same file name doesn't already exist.
+ (NSString *)testFilePathForDirectory:(NSString *)directory
{
    return [NSString stringWithFormat:@"%@/%@", directory, [self randomFilename]];
}

+ (NSError *)warmupPath:(NSString *)path
{
    // write and read a random value to the given path
    // to try to wake (warm) the storage device up.

    // getting the file system stat help? maybe not.
    // it's probably already cached on memory.
    struct statfs buf;
    statfs(path.UTF8String, &buf);
    
    // write something if writable (it better be).
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm isWritableFileAtPath:path])
    {
        BOOL written;
        NSURL *URL = [NSURL fileURLWithPath:[NSString stringWithFormat:@"%@/%@", path, [self randomFilename]]];
        KSLog(@"%s: random file URL: %@", __func__, URL);
        uint8_t v = (uint8_t)random();
        NSError *error = nil;
        NSData *data = [NSData dataWithBytes:&v length:1];
        written = [data writeToURL:URL options:(NSDataWritingOptions)0 error:&error];
        if (written)
        {
            // and delete the file right away.
            [fm removeItemAtURL:URL error:nil];
        }
        
        return error;
    }
    else
    {
        return [NSError errorWithDomain:NSPOSIXErrorDomain code:EACCES userInfo:nil];
    }
}

static void diskArbitrationCallBack(DADiskRef disk, CFArrayRef keys, void *context)
{
    NSArray *array = (__bridge NSArray *)keys;
    NSDictionary *dict = nil;
    if (disk != NULL)
    {
        NSDictionary *desc = CFBridgingRelease(DADiskCopyDescription(disk));
        NSMutableDictionary *md = [NSMutableDictionary dictionary];
        for (NSString *key in array)
        {
            id o = desc[key];
            if (o)
            {
                [md setObject:o forKey:key];
            }
        }
        dict = [NSDictionary dictionaryWithDictionary:md];
    }
    KSLog(@"%s: (disk: %@, keys: %@)", __func__, dict, array);

    NSNotification *n = [NSNotification notificationWithName:@"KSDescriptionChangedNotification" object:nil userInfo:dict];
    [(__bridge DiskUtil *)context volumesChanged:n];
}

- (instancetype)initWithDelegate:(id <DiskUtilDelegate>)delegate
{
    self = [super init];
    if (self != nil)
    {
        self.delegate = delegate;
        self.daSession = [DiskUtil daSession];
        self.mountInfo = [DiskUtil scanMountInfo];
        KSLog(@"%s: mountInfo: %@", __func__, _mountInfo);

        // NSWorkspace mount/unmount works with NFS mount which is good. but not with NFS unmount.
        NSNotificationCenter *nc = [[NSWorkspace sharedWorkspace] notificationCenter];
        [nc addObserver:self selector:@selector(volumesChanged:) name:NSWorkspaceDidMountNotification object:nil];
        [nc addObserver:self selector:@selector(volumesChanged:) name:NSWorkspaceDidUnmountNotification object:nil];

        // we need DiskArbitration description changed to get the volume name change notification.
        DARegisterDiskDescriptionChangedCallback(_daSession, kDADiskDescriptionMatchVolumeMountable, kDADiskDescriptionWatchVolumePath, diskArbitrationCallBack, (__bridge void *)self);
        DASessionScheduleWithRunLoop(_daSession, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
    }
    
    return self;
}

- (void)dealloc
{
    // unregister the volume mount callback
    if (_daSession != NULL)
    {
        DAUnregisterCallback(_daSession, diskArbitrationCallBack, (__bridge void *)self);
        DASessionUnscheduleFromRunLoop(_daSession, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
    }

    NSNotificationCenter *nc = [[NSWorkspace sharedWorkspace] notificationCenter];
    [nc removeObserver:self name:NSWorkspaceDidMountNotification object:nil];
    [nc removeObserver:self name:NSWorkspaceDidUnmountNotification object:nil];
    self.mountInfo = nil;
}

- (void)volumesChanged:(NSNotification *)notification
{
    KSLog(@"%s: notification: %@", __func__, notification);
    
    // 2016-10-14 20:17:50.580 AmorphousDiskMark[48649:5492468] -[DiskUtil volumesChanged:]: notification: NSConcreteNotification 0x620000042880 {name = NSWorkspaceDidMountNotification; object = <NSWorkspace: 0x6380000001c0>; userInfo = {
    //NSDevicePath = "/net/mac/vrl";
    //NSWorkspaceVolumeLocalizedNameKey = vrl;
    //NSWorkspaceVolumeURLKey = "file:///net/mac/vrl/";

    // 2016-10-14 20:22:12.170 AmorphousDiskMark[48679:5494481] -[DiskUtil volumesChanged:]: notification: NSConcreteNotification 0x6380000401e0 {name = NSWorkspaceDidUnmountNotification; object = <NSWorkspace: 0x6080000002f0>; userInfo = {
    //NSDevicePath = "/Volumes/SDUSB64GB";
    //NSWorkspaceVolumeLocalizedNameKey = SDUSB64GB;
    //NSWorkspaceVolumeURLKey = "file:///Volumes/SDUSB64GB/";
    
    // update the mount info first
    self.mountInfo = [DiskUtil scanMountInfo];

    // then call the delegate
    if ([notification.name isEqualToString:NSWorkspaceDidMountNotification])
    {
        [_delegate didMountDiskUtil:self volume:notification.userInfo];
    }
    else if ([notification.name isEqualToString:NSWorkspaceDidUnmountNotification])
    {
        [_delegate didUnmountDiskUtil:self volume:notification.userInfo];
    }
    else
    {
        [_delegate didChangeDiskUtil:self volume:notification.userInfo];
    }
}

+ (BOOL)shouldSkipFSType:(NSString *)fstype
{
    // devfs: /dev
    // autofs: /home, /net, /Network/Servers (i guess i could include these but skipping these for now)
    // nullfs: /private/var/folders/.../<UUID> (a downloaded app runs from this "nullfs" read-only mount point)
    return [@[@"devfs", @"autofs", @"nullfs"] containsObject:fstype];
}

+ (BOOL)isReadOnlyPath:(NSString *)path
{
    // special case: a boot volume "/"
    if ([path isEqualToString:@"/"])
    {
        path = @"/tmp";
    }
    
    // and only writable mount points should be enabled.
    NSFileManager *fm = [NSFileManager defaultManager];
    return ![fm isWritableFileAtPath:path];
}

//
// special file systems:
//  devfs (/dev)
//  autofs (/net)
//
// local file systems:
//  hfs:   hfs (Mac OS Extended)
//  msdos: MS-DOS (FAT)
//  ntfs:  Windows NT File System (NTSF)
//  exfat: Extended File Allocation Table (exFAT)
//  udf:   Universal Disk Format (UDF)
//         (CD/DVD/BD)
//
// remote file systems:
//  smbfs
//  nfs
//  afpfs
//
// supported file systems by macOS:
//  https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemDetails/FileSystemDetails.html
//
+ (NSString *)localizedFileSystemNameForKind:(NSString *)fstype type:(NSString *)type
{
    if ([fstype isEqualToString:@"apfs"])
    {
        return (type.length && ![type isEqualToString:@"APFS"])? type: NSLocalizedString(@"Apple File System (APFS)", "Apple File System (APFS)");
    }
    else if ([fstype isEqualToString:@"hfs"])
    {
        return type.length? type: NSLocalizedString(@"Mac OS Extended: HFS+", "Mac OS Extended: HFS+");
    }
    else if ([fstype isEqualToString:@"msdos"])
    {
        return type.length? type: NSLocalizedString(@"MS-DOS (FAT)", "MS-DOS (FAT)");
    }
    else if ([fstype isEqualToString:@"exfat"])
    {
        return type.length? type: NSLocalizedString(@"Extended File Allocation Table: exFAT", "Extended File Allocation Table: exFAT");
    }
    else if ([fstype isEqualToString:@"ntfs"])
    {
        // for a 4K block NTFS USB flash drive, the type is "MS-DOS (FAT12)" for some reason
        return NSLocalizedString(@"Windows NT File System (NTFS)", "Windows NT File System (NTFS)");
    }
    else if ([fstype isEqualToString:@"udf"])
    {
        // no "type" for UDF (CD-ROM)
        return NSLocalizedString(@"Universal Disk Format: UDF", "Universal Disk Format: UDF");
    }
    else if ([fstype isEqualToString:@"smbfs"])
    {
        // no "type" info for remote mounts.
        return NSLocalizedString(@"Server Message Block: SMB", "Server Message Block: SMB");
    }
    else if ([fstype isEqualToString:@"nfs"])
    {
        // no "type" info for remote mounts.
        return NSLocalizedString(@"Network File System: NFS", "Network File System: NFS");
    }
    else if ([fstype isEqualToString:@"afpfs"])
    {
        // no "type" info for remote mounts.
        return NSLocalizedString(@"Apple Filing Protocol: AFP", "Apple Filing Protocol: AFP");
    }
    else if (type.length)
    {
        // unknow file system. but the system seems to know.
        return type;
    }
    else
    {
        NSLog(@"warning: unknown file system: %@", fstype);
        return fstype;
    }
}

//
// size < 1,000: 999 B
// size < 1,000,000: 999 KB
// size < 1,000,000,000: 999 MB
// size < 1,000,000,000,000: 999 GB
// size < 1,000,000,000,000,000: 999 TB
// size < 1,000,000,000,000,000,000: 999 PB
//

#define KB (1000ULL)
#define MB (1000ULL * 1000)
#define GB (1000ULL * 1000 * 1000)
#define TB (1000ULL * 1000 * 1000 * 1000)
#define PB (1000ULL * 1000 * 1000 * 1000 * 1000)

+ (NSString *)humanReadableSize:(uint64_t)size
{
    if (size < KB)
    {
        return [NSString stringWithFormat:NSLocalizedString(@"%lld B", "%lld B"), size];
    }
    else if (size < MB)
    {
        return [NSString stringWithFormat:NSLocalizedString(@"%.2f KB", "%.2f KB"), (double)size / KB];
    }
    else if (size < GB)
    {
        return [NSString stringWithFormat:NSLocalizedString(@"%.2f MB", "%.2f MB"), (double)size / MB];
    }
    else if (size < TB)
    {
        return [NSString stringWithFormat:NSLocalizedString(@"%.2f GB", "%.2f GB"), (double)size / GB];
    }
    else if (size < PB)
    {
        return [NSString stringWithFormat:NSLocalizedString(@"%.2f TB", "%.2f TB"), (double)size / TB];
    }
    else
    {
        return [NSString stringWithFormat:NSLocalizedString(@"%.2f PB", "%.2f PB"), (double)size / PB];
    }
}

+ (NSString *)physicalStoreWithMediaPath:(NSString *)mediaPath
{
    NSString *physicalStore = @"";
    if (mediaPath.length != 0) {
        io_registry_entry_t entry = IORegistryEntryFromPath(kIOMasterPortDefault, mediaPath.UTF8String);
        if (entry == MACH_PORT_NULL) {
            NSLog(@"error: IORegistryEntryFromPath");
            return physicalStore;
        }
        while (entry != MACH_PORT_NULL) {
            //kern_return_t IOObjectGetClass( io_object_t object, io_name_t className);
            io_name_t className;
            kern_return_t kr = IOObjectGetClass(entry, className);
            if (kr == kIOReturnSuccess) {
                KSLog(@"className: %s", className);
                if (strcmp(className, "IOMedia") == 0) {
                    // IOMedia found!
                    CFMutableDictionaryRef props = NULL;
                    kr = IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0);
                    if (kr != kIOReturnSuccess) {
                        NSLog(@"error: IORegistryEntryCreateCFProperties: kr: %@", @(kr));
                    } else {
                        KSLog(@"props: %@", props);
                        NSDictionary *dict = (__bridge_transfer NSDictionary *)props;
                        //physicalStore = dict[@"BSD Name"];
                        physicalStore = [dict objectForKey:@"BSD Name"];
                    }
                    IOObjectRelease(entry);
                    entry = MACH_PORT_NULL;
                    break;
                }
            }
            //kern_return_t IORegistryEntryGetParentEntry( io_registry_entry_t entry, const io_name_t plane, io_registry_entry_t *parent);
            io_registry_entry_t parent;
            kr = IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent);
            if (kr != kIOReturnSuccess) {
                NSLog(@"error: IORegistryEntryGetParentEntry: kr: %@", @(kr));
                break;
            } else {
                IOObjectRelease(entry);
                entry = parent;
            }
        }
        if (entry != MACH_PORT_NULL) {
            IOObjectRelease(entry);
        }
    }
    return physicalStore;
}

//
// scanMountInfo returns an array of dictionary with
// the following key/value pairs.
//
// bsize = 4096;
// daDeviceModel = "Hitachi HDS5C3020ALA632";
// daVolumeName = "Macintosh HD";
// daVolumeType = "Mac OS Extended (Journaled)";
// freeSize = 833071616000;
// fromname = "/dev/disk0s2";
// fstype = hfs;
// isBootVolume = 1;
// isReadOnly = 0;
// onname = "/";
// percentUsed = 59;
// size = 1999539175424;
//
+ (NSArray<NSDictionary *> *)scanMountInfo
{
    int i, c;
    struct statfs *mounts;
    NSMutableArray *ma;
    
    c = getmntinfo(&mounts, MNT_WAIT);
    KSLog(@"%s: getmntinfo: %d", __func__, c);
    
    if (c == 0)
    {
        NSLog(@"error: getmntinfo() failed");
        
        return nil;
    }

    NSFileManager *fm = [[NSFileManager alloc ] init];

    //
    // the first entry is  usually the boot volume "/".
    //
    // i need to detect the " - Data" APFS volume for the boot APFS volume
    // using the BSD name (e.g. "disk2s1") in order for the volume popup button
    // to select the boot volume.
    //
    // on macOS 10.15 beta 10, the read/write " - Data" volume is mounted at
    // "/System/Volumes/Data".
    //
    ma = [NSMutableArray array];
    for (i = 0; i < c; i++)
    {
        NSString *fromname, *onname, *daVolumeName, *daDeviceVendor, *daDeviceModel, *daVolumeType, *apfsPhysicalStore;
        
        KSLog(@"[%d]: fstyle: %s, to: %s, from: %s, f_flags: 0x%08x (MNT_RDONLY: 0x%08x)", i, mounts[i].f_fstypename, mounts[i].f_mntonname, mounts[i].f_mntfromname, mounts[i].f_flags, (uint32_t)MNT_RDONLY);
        
        fromname = [NSString stringWithUTF8String:mounts[i].f_mntfromname];
        onname = [NSString stringWithUTF8String:mounts[i].f_mntonname];
        if ((fromname == nil) || (onname == nil))
        {
            // no name. skip.
            KSLog(@"[%d]: skip: no name", i);
            continue;
        }

        // check if it's the boot volume "/"
        BOOL isBootVolume = [onname isEqualToString:@"/"];

        //
        // on macOS 11 beta, the boot volume "/" has the "snapshot" bit set.
        // so, make sure not to skip the boot volume "/".
        //
        BOOL isSnapshot = ((mounts[i].f_flags & MNT_SNAPSHOT) != 0);
        if (isSnapshot && !isBootVolume) {
            // ignore Time Machine snapshot mounts
            KSLog(@"[%d]: skip: time machine snapshot", i);
            continue;
        }

        // i only want the user recognizable mount points.
        NSString *fstype = [NSString stringWithUTF8String:mounts[i].f_fstypename];
        if ([self shouldSkipFSType:fstype])
        {
            // skip unrecognizable file system
            KSLog(@"[%d]: skip: unrecognizable file system", i);
            continue;
        }

        // skip "don't browse" and not NFS and not "/"
        BOOL dontBrowse = ((mounts[i].f_flags & MNT_DONTBROWSE) != 0);
        BOOL isNFS = [fstype isEqualToString:@"nfs"];
        KSLog(@"isNFS: %s", isNFS? "YES": "NO");
        KSLog(@"dontBrowse: %s", dontBrowse? "YES": "NO");
        if (dontBrowse && !isNFS && !isBootVolume) {
            // skip the read/write Data APFS volume, the VM APFS volume, etc.
            KSLog(@"[%d]: skip: don't browse and not NFS and not boot volume", i);
            continue;
        }
        
        BOOL isLocal = ((mounts[i].f_flags & MNT_LOCAL) != 0);

        // CD/DVD/BD will be MNT_RDONLY. gray out in the storage popup button.
        BOOL isReadOnly = ((mounts[i].f_flags & MNT_RDONLY) != 0);

        // FIXME!!! we need to find a way to mark the read-only media
        // such as CD/DVD as read-only if the MNT_RDONLY flag is not
        // set properly. we can no longer rely on isWritableFileAtPath:
        // since it returns NO until the user "allow" the access to
        // the given path.
#if 0
        // MNT_RDONLY is actually not set for non-read-only media.
        // so, i need to figure it out myself.
        if (!isReadOnly)
        {
            isReadOnly = [self isReadOnlyPath:onname];
        }
#endif
        // get "disk" (local storage) info
        daVolumeName = nil;  // DAVolumeName
        daDeviceVendor = nil;  // DADeviceVendor
        daDeviceModel = nil;  // DADeviceModel
        daVolumeType = nil;  // DAVolumeType
        apfsPhysicalStore = @"";
        NSDictionary *daMediaIcon = nil;  // DAMediaIcon
        NSString *daDevicePath = nil; // DADevicePath

        NSURL *url = [NSURL fileURLWithPath:onname];
        DADiskRef disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, [self daSession], (__bridge CFURLRef)url);
        if (disk != NULL)
        {
            NSDictionary *diskinfo = (__bridge_transfer NSDictionary *)DADiskCopyDescription(disk);
            CFRelease(disk);
            KSLog(@"[%d]: disk description: %@", i, diskinfo);
            // this should never happen
            if (diskinfo == nil)
            {
                KSLog(@"[%d]: skip: no disk info", i);
                continue;
            }

            daVolumeName = diskinfo[(__bridge NSString *)kDADiskDescriptionVolumeNameKey];
            daDeviceVendor = diskinfo[(__bridge NSString *)kDADiskDescriptionDeviceVendorKey];
            daDeviceModel = diskinfo[(__bridge NSString *)kDADiskDescriptionDeviceModelKey];
            // macOS 10.11+: kDADiskDescriptionVolumeTypeKey
            // use the hardcoded "DAVolumeType" here to support macOS 10.8+.
            // NOTE: DAVolumeType doesn't exist for APFS on macOS 10.12 or older.
            daVolumeType = diskinfo[@"DAVolumeType"];
            daMediaIcon = diskinfo[(__bridge NSString *)kDADiskDescriptionMediaIconKey];
            daDevicePath = diskinfo[(__bridge NSString *)kDADiskDescriptionDevicePathKey];

            if ([fstype isEqualToString:@"apfs"])
            {
                // get the physical store device from an APFS synthesized device
                NSString *daMediaPath = diskinfo[(__bridge NSString *)kDADiskDescriptionMediaPathKey];
                apfsPhysicalStore = [self physicalStoreWithMediaPath:daMediaPath];
            }

            // make sure the icon dicitonary is not nil
            if (daMediaIcon == nil)
            {
                daMediaIcon = @{};
            }

            // make sure the device path string is not nil
            if (daDevicePath == nil)
            {
                daDevicePath = @"";
            }

            // some devices don't have the vendor name.
            if (daDeviceVendor != nil)
            {
                // combine the vendor name and model name here.
                daDeviceModel = [@[daDeviceVendor, daDeviceModel] componentsJoinedByString:@" "];
            }
            
            if (daDeviceModel == nil)
            {
                // there will be no "device" info for remote storages.
                daDeviceModel = [self localizedFileSystemNameForKind:fstype type:daVolumeType];
            }
            else
            {
                //
                // some devices have white space at the end of its name.
                //
                // "Hitachi HDS722020ALA330                 "
                // "ST4000DM000-1F2168                      "
                //
                daDeviceModel = [daDeviceModel stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            }
        }
        
        // daDeviceModel:
        //  "OPTIARC DVD RW AD-7170A" (built-in optical drive)
        //  "ST4000DM000-1F2168" (Seagate hard drive)
        //  "Hitachi HDS722020ALA330" (Hitachi hard drive)
        //  "Apple Disk Image"
        //  "Server Message Block: SMB"
        //  "Network File System: NFS"
        if (daDeviceModel == nil)
        {
            daDeviceModel = @"Unknown Device";
        }
        
        if (daVolumeName == nil)
        {
            // for remove storage, Disk Arbitration doesn't get the volume name.
            daVolumeName = [onname lastPathComponent];
        }
        
        // for some file systems, there is no volume type .
        if (daVolumeType == nil)
        {
            // for remove storage, Disk Arbitration doesn't get the volume name.
            daVolumeType = @"";
        }
        
        // uint64_t	f_blocks;	/* total data blocks in file system */
        // uint64_t	f_bfree;	/* free blocks in fs */
        // uint64_t	f_bavail;	/* free blocks avail to non-superuser */

        //
        // f_bfree of the APFS volume on the APFS container partition with multiple APFS volumes
        // is incorrect. it's reporting the total capaticy of the APFS container minus the used
        // blocks by the given APFS volume.
        //
        // APFS container (500GB capacity. 40GB free):
        //   APFS volume 1 (11GB used)  ==> f_bfree * f_bsize = 489GB free (should be 40GB free)
        //   APFS volume 2 (440GB used) ==> f_bfree * f_bsize = 60GB free (should be 40GB free)
        //

        // available disk space
        uint64_t bsize = mounts[i].f_bsize;
        NSError *error = nil;
        NSDictionary<NSFileAttributeKey, id> *attrs = [fm attributesOfFileSystemForPath:onname error:&error];
        KSLog(@"[%d]: file system attrs: %@", i, attrs);
        NSNumber *fsSize = attrs[NSFileSystemSize];
        uint64_t size = fsSize.unsignedIntegerValue;
        NSNumber *fsFreeSize = attrs[NSFileSystemFreeSize];
        uint64_t freeSize = fsFreeSize.unsignedIntegerValue;
        KSLog(@"[%d]: mounts[i].f_blocks * bsize: %@, mounts[i].f_bfree * bsize: %@", i, @(mounts[i].f_blocks * bsize), @(mounts[i].f_bfree * bsize));
        if (error != nil) {
            // fallback to f_bfree/f_blocks if attributesOfFileSystemForPath: fails.
            NSLog(@"error: %@", error);
            freeSize = mounts[i].f_bfree * bsize;
            size = mounts[i].f_blocks * bsize;
        }
        uint64_t percentUsed = 100 - ((size != 0)? (freeSize * 100 / size): 0);
        KSLog(@"[%d]: blockSize: %llu, freeSize: %llu, size: %llu, used: %llu", i, bsize, freeSize, size, percentUsed);
        
        //
        // fromname: "/dev/disk0s2" or "//hkatsura@mac/stage" for remote volumes
        // onmame:   "/" for the boot volume or "/Volumes/4TB" for non-boot volumes
        // apfsPhysicalStore: "disk0s2"
        //
        [ma addObject:@{@"fromname": fromname, @"onname": onname, @"daVolumeName": daVolumeName, @"daDeviceModel": daDeviceModel, @"daVolumeType": daVolumeType, @"isBootVolume": @(isBootVolume), @"isReadOnly": @(isReadOnly), @"size": @(size), @"freeSize": @(freeSize), @"bsize": @(bsize), @"percentUsed": @(percentUsed), @"fstype": fstype, @"isLocal": @(isLocal), @"daMediaIcon": daMediaIcon, @"daDevicePath": daDevicePath, @"apfsPhysicalStore": apfsPhysicalStore}];
    }
    
    return [NSArray arrayWithArray:ma];
}

+ (NSString *)volumeNameAtPath:(NSString *)path {
    KSLog(@"%s: path: %@", __func__, path);
    // int statfs(const char *path, struct statfs *buf);
    struct statfs s;
    int r = statfs(path.UTF8String, &s);
    if (r != 0) {
        return nil;
    }
    KSLog(@"%s: f_mntonname: %s, f_mntfromname: %s", __func__, s.f_mntonname, s.f_mntfromname);
    NSURL *url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:s.f_mntonname]];
    DADiskRef disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, [self daSession], (__bridge CFURLRef)url);
    CFDictionaryRef desc = DADiskCopyDescription(disk);
    NSDictionary *dict = (__bridge_transfer NSDictionary *)desc;
    KSLog(@"disk: %@, desc: %@", disk, dict);
    CFRelease(disk);
    return dict[@"DAVolumeName"];
}

+ (NSString *)mountPointForPath:(NSString *)path {
    KSLog(@"%s: path: %@", __func__, path);
    // int statfs(const char *path, struct statfs *buf);
    struct statfs s;
    int r = statfs(path.UTF8String, &s);
    if (r != 0) {
        return path;
    }
    KSLog(@"%s: f_mntonname: %s, f_mntfromname: %s", __func__, s.f_mntonname, s.f_mntfromname);
    NSString *mp = [NSString stringWithUTF8String:s.f_mntonname];
    if ([mp isEqualToString:@"/System/Volumes/Data"]) {
        // special case. the APFS read/write boot volume is mounted at
        // "/System/Volumes/Data".
        mp = @"/";
    }
    return mp;
}

+ (NSString *)usageWithMountInfo:(NSDictionary *)mount
{
    NSNumber *percentUsed = mount[@"percentUsed"];
    percentUsed = percentUsed? percentUsed: @(0);
    NSString *usage = [DiskMark humanReadableUsageWithMountInfo:mount];
    return [NSString stringWithFormat:@"%@%% used (%@)", percentUsed, usage];
}
@end
