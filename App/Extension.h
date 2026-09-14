//
//  Extension.h
//  TaskExplorer (app)
//
//  Created by Patrick Wardle on 9/12/26.
//  Copyright (c) 2026 Objective-See. All rights reserved.
//
//  note: (de)activates the (endpoint security) system extension

#ifndef Extension_h
#define Extension_h

#import <os/log.h>
#import <Foundation/Foundation.h>
#import <SystemExtensions/SystemExtensions.h>

typedef void(^replyBlockType)(NSError*);

@interface Extension : NSObject <OSSystemExtensionRequestDelegate>

/* PROPERTIES */

//reply
@property(nonatomic, copy)replyBlockType replyBlock;

//flag
// set when request needs user approval
@property BOOL needsApproval;

/* METHODS */

//submit request to toggle extension
-(void)toggleExtension:(NSUInteger)action reply:(replyBlockType)reply NS_SWIFT_NAME(toggleExtension(_:reply:));

//check if extension is running
-(BOOL)isExtensionRunning;

//deactivate extension (synchronously)
// ->stops the extension (process), but approval is retained, so no re-approval on next activation
//   note: blocks (up to 'timeout' seconds), so call from a background thread
-(BOOL)deactivate:(NSTimeInterval)timeout;

@end

#endif /* Extension_h */
