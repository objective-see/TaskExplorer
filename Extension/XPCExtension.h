//
//  file: XPCExtension.h
//  project: TaskExplorer (extension)
//  description: interface for XPC methods, invoked by app (header)
//
//  created by Patrick Wardle
//  copyright (c) 2026 Objective-See. All rights reserved.
//

#ifndef XPCExtension_h
#define XPCExtension_h

#import <Foundation/Foundation.h>

#import "XPCExtensionProto.h"

@interface XPCExtension : NSObject <XPCExtensionProtocol>
{

}

@end

#endif /* XPCExtension_h */
