//
//  DMMediaIcon.h
//  AmorphousDiskMark
//
//  Created by Hidetomo Katsura on 10/5/19.
//  Copyright © 2019 Katsura Shareware. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface DMMediaIcon : NSObject

+ (NSImage *)iconWithDictionary:(NSDictionary *)dict;
+ (NSImage *)iconForIdentifier:(NSString *)identifier file:(NSString *)file;

@end

NS_ASSUME_NONNULL_END
