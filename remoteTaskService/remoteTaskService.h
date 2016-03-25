//
//  remoteTaskService.h
//  remoteTaskService
//
//  Created by Patrick Wardle on 5/27/15.
//  Copyright (c) 2015 Objective-See, LLC. All rights reserved.
//

#import "serviceInterface.h"

#import <Foundation/Foundation.h>


// This object implements the protocol which we have defined. It provides the actual behavior for the service. It is 'exported' by the service to make it available to the process hosting the service over an NSXPCConnection.
@interface remoteTaskService : NSObject <remoteTaskProto, NSXPCListenerDelegate>

//default service
+(remoteTaskService *)defaultService;

@end

