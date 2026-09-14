//
//  MachO.h
//  MachOParser
//
//  Created by Patrick Wardle on 2/6/15.
//  Copyright (c) 2015 Objective-See, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>

/* CONSTS */

//dictionary keys
#define KEY_BINARY_PATH @"binaryPath"
#define KEY_MACHO_HEADERS @"machoHeaders"
#define KEY_LOAD_COMMANDS @"loadCommands"

#define KEY_HEADER_OFFSET @"headerOffset"
#define KEY_HEADER_SIZE @"headerSize"
#define KEY_HEADER_BINARY_TYPE @"headerType"
#define KEY_HEADER_BYTE_ORDER @"headerByteOrder"
#define KEY_IS_PACKED @"isPacked"
#define KEY_IS_ENCRYPTED @"isEncryted"

#define KEY_LC_RPATHS @"lcRpath"
#define KEY_LC_REEXPORT_DYLIBS @"lcRexports"
#define KEY_LC_LOAD_DYLIBS @"lcLoadDylib"
#define KEY_LC_LOAD_WEAK_DYLIBS @"lcLoadWeakDylib"


@interface MachO : NSObject
{
    
}

//info dictionary
// ->contains everything parsed out of the file
@property(nonatomic, retain)NSMutableDictionary* binaryInfo;

//file offset of the 'best' slice (the one the loader would pick on this machine), via macho_best_slice_in_fd()
// ->nil if unavailable; used so classification (e.g. encrypted) only looks at the slice that actually runs
@property(nonatomic, retain)NSNumber* bestSliceOffset;

//binary's data
@property(nonatomic, retain)NSData* binaryData;

//segment names found in various packers
@property(nonatomic, retain)NSSet* packerSegmentNames;


/* METHODS */

//parse a binary
// ->extract all required/interesting stuff
-(BOOL)parse:(NSString*)binaryPath classify:(BOOL)shouldClassify;


@end
