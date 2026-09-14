//
//  XPCApp.h
//  TaskExplorer (app)
//
//  Created by Patrick Wardle on 9/12/26.
//  Copyright (c) 2026 Objective-See. All rights reserved.
//
//  note: methods invoked by the extension (event delivery)

#ifndef XPCApp_h
#define XPCApp_h

#import <Foundation/Foundation.h>

#import "XPCAppProto.h"

@interface XPCApp : NSObject <XPCAppProtocol>
{

}

@end

#endif /* XPCApp_h */
