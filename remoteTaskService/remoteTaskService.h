//
//  remoteTaskService.h
//  remoteTaskService
//
//  Created by Patrick Wardle on 5/27/15.
//  Copyright (c) 2015 Lucas Derraugh. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "serviceInterface.h"

// This object implements the protocol which we have defined. It provides the actual behavior for the service. It is 'exported' by the service to make it available to the process hosting the service over an NSXPCConnection.
@interface remoteTaskService : NSObject <remoteTaskProto, NSXPCListenerDelegate>


//
+(remoteTaskService *)defaultService;

@end


//convert a socket type in to string
NSString* socketType2String(int type);

//convert a socket family into string
NSString* socketFamily2String(int family);

//convert a socket protocol into string
NSString* socketProto2String(int proto);

//convert a socket state into string
NSString* socketState2String(int state);
