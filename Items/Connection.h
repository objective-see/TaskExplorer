//
//  Extension.h
//  TaskExplorer
//
//  Created by Patrick Wardle on 2/19/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//

#import "ItemBase.h"
#import <Foundation/Foundation.h>

@interface Connection : ItemBase
{
    
}

//local ip addr
@property(nonatomic, retain)NSString* localIPAddr;

//local port
@property(nonatomic, retain)NSNumber* localPort;

//remote ip addr
@property(nonatomic, retain)NSString* remoteIPAddr;

//remote port
@property(nonatomic, retain)NSNumber* remotePort;

//socket type
@property(nonatomic, retain)NSString* type;

//socket family
@property(nonatomic, retain)NSString* family;

//socket proto
@property(nonatomic, retain)NSString* proto;

//socket state
@property(nonatomic, retain)NSString* state;

//pretty print of connnection
@property(nonatomic, retain)NSMutableString* endpoints;


/* METHODS */

//set icon
-(void)setConnectionIcon;

//return a string representation of the connection
-(void)setConnectionString;



@end
