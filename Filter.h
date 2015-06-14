//
//  Filter.h
//  KnockKnock
//
//  Created by Patrick Wardle on 2/21/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//
#import "File.h"
#import "Binary.h"

#import <Foundation/Foundation.h>

@interface Filter : NSObject
{
    
}

//white listed file hashes
@property(nonatomic, retain)NSDictionary* trustedFiles;

//white listed commands
@property(nonatomic, retain)NSDictionary* knownCommands;

//white listed extensions
@property(nonatomic, retain)NSDictionary* trustedExtensions;


/* METHODS */

//load a (JSON) white list
// ->file hashes, known commands, etc
-(NSDictionary*)loadWhitelist:(NSString*)fileName;

//check if a File obj is whitelisted
-(BOOL)isTrustedFile:(Binary*)fileObj;

//check if a Command obj is whitelisted
//-(BOOL)isKnownCommand:(Command*)commandObj;

//check if a Extension obj is whitelisted
//-(BOOL)isTrustedExtension:(Extension*)extensionObj;



@end
