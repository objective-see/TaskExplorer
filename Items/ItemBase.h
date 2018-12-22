//
//  ItemBase.h
//  TaskExplorer
//
//  Created by Patrick Wardle on 9/25/14.
//  Copyright (c) 2014 Objective-See. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ItemBase : NSObject
{
    
}

//name
@property(retain, nonatomic)NSString* name;

//path
@property(retain, nonatomic)NSString* path;

//icon
@property(nonatomic, retain)NSImage* icon;

//file attributes
@property(nonatomic, retain)NSDictionary* attributes;

/* METHODS */

//init method
-(id)initWithParams:(NSDictionary*)params;

//return a path that can be opened in Finder.app
-(NSString*)pathForFinder;

//convert object to JSON string
-(NSString*)toJSON;

@end
