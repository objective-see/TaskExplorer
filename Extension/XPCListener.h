//
//  file: XPCListener.h
//  project: TaskExplorer (extension)
//  description: XPC listener for connections from the app (header)
//
//  created by Patrick Wardle
//  copyright (c) 2026 Objective-See. All rights reserved.
//

#ifndef XPCListener_h
#define XPCListener_h

#import <os/log.h>
#import <Foundation/Foundation.h>

#import "XPCExtensionProto.h"

//function def
OSStatus SecTaskValidateForRequirement(SecTaskRef task, CFStringRef requirement);

@interface XPCListener : NSObject <NSXPCListenerDelegate>
{

}

/* PROPERTIES */

//XPC listener
@property(nonatomic, retain)NSXPCListener* listener;

//XPC connection for (main) app
@property(weak)NSXPCConnection* client;

@end

#endif /* XPCListener_h */
