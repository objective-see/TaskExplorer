//
//  File.h
//  TaskExplorer
//
//  Created by Patrick Wardle on 2/19/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//

#import "ItemBase.h"

#import <Foundation/Foundation.h>

/* GLOBALS */

//(privacy) protected directories
extern NSArray* protectedDirectories;

@interface File : ItemBase
{
    
}

/* PROPERTIES */

//type
@property(nonatomic, retain)NSString* type;


/* METHODS */

//init method
-(id)initWithParams:(NSDictionary*)params;



@end
