//
//  Common.h
//  AmorphousDiskMark
//
//  Created by Hidetomo Katsura on 10/19/2016.
//  Copyright © 2016 Katsura Shareware. All rights reserved.
//

//
// the goal is to support all the way back to 10.6.x.
//
// but i don't have a Mac with 10.6. so, the initial
// release will set the Deployment Target to 10.8.
//

#ifndef Common_h
#define Common_h

#define DO_LOG  0

#if DO_LOG
#define KSLog   NSLog
#define DMPrintf printf
#else
#define KSLog(...)
#define DMPrintf(...)
#endif

#define KiB (1024ULL)
#define MiB (1024ULL * 1024)
#define GiB (1024ULL * 1024 * 1024)
#define TiB (1024ULL * 1024 * 1024 * 1024)

#define KB (1000ULL)
#define MB (1000ULL * 1000)
#define GB (1000ULL * 1000 * 1000)
#define TB (1000ULL * 1000 * 1000 * 1000)

#endif /* Common_h */
