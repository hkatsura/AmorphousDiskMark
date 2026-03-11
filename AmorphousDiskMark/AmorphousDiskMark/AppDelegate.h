//
//  AppDelegate.h
//  AmorphousDiskMark
//
//  Created by Hidetomo Katsura on 10/7/2016.
//  Copyright © 2016 Katsura Shareware. All rights reserved.
//
//  The UI layout was designed based on CrystalDiskMark for Windows
//  with author's permission.
//  http://crystalmark.info/
//

#import <Cocoa/Cocoa.h>

#import "Common.h"
#import "DiskMark.h"
#import "DiskUtil.h"

@interface AppDelegate : NSObject <NSApplicationDelegate, DiskMarkDelegate, DiskUtilDelegate>

- (IBAction)iaButton:(id)sender;
- (IBAction)iaIterationPopUpButton:(id)sender;
- (IBAction)iaSizePopUpButton:(id)sender;
- (IBAction)iaStoragePopUpButton:(id)sender;

- (IBAction)iaTestDataMenuItem:(id)sender;
- (IBAction)iaIntervalMenuItem:(id)sender;
- (IBAction)iaSeqQDMenuItem:(id)sender;
- (IBAction)iaRandomQDMenuItem:(id)sender;

- (IBAction)iaUnitPopUpButton:(id)sender;

@end

