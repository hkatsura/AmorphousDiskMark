//
//  DMTextView.h
//  AmorphousDiskMark
//
//  Created by Hidetomo Katsura on 10/10/2016.
//  Copyright © 2016 Katsura Shareware. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "Common.h"

@interface DMTextView : NSTextView

@property (assign, nonatomic) BOOL enabled;

// multiple values: e.g. {"mbps":"33.33","iops":"1234.4"}
@property (nonatomic) NSDictionary *values;

// select which value to show, and triggers redraw. key: "mbps" ==> "33.33"
@property (nonatomic) NSString *key;

@end
