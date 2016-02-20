//
//  HSTracker-Bridging-Header.h
//  HSTracker
//
//  Created by Benjamin Michotte on 19/02/16.
//  Copyright © 2016 Benjamin Michotte. All rights reserved.
//

#ifndef HSTracker_Bridging_Header_h
#define HSTracker_Bridging_Header_h

#import <RegExCategories/RegExCategories.h>

#define LOG_LEVEL_DEF ddLogLevel

#import <CocoaLumberjack/CocoaLumberjack.h>

#ifdef DEBUG
static const DDLogLevel ddLogLevel = DDLogLevelVerbose;
#else
static const DDLogLevel ddLogLevel = DDLogLevelInfo;
#endif

#import <MagicalRecord/MagicalRecord.h>

#endif /* HSTracker_Bridging_Header_h */
