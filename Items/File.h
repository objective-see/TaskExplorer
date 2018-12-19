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

//get detailed info (which takes a while to generate)
// ->only shown to user if they click 'info' so this method is called in the background
-(void)generateDetailedInfo;

//set file type
// ->invokes 'file' cmd, the parses out result
-(void)setFileType;

@end
