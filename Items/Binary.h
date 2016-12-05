//
//  File.h
//  TaskExplorer
//
//  Created by Patrick Wardle on 2/19/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//

#import "MachO.h"
#import "ItemBase.h"

#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>

@interface Binary : ItemBase
{
    
}

/* PROPERTIES */

//name
@property(nonatomic, retain)NSString* name;

//path
@property(nonatomic, retain)NSString* path;

//bundle
@property(nonatomic, retain)NSBundle* bundle;

//flag for task (main) executable
@property BOOL isTaskBinary;

//hashes (md5, sha1)
@property(nonatomic, retain)NSDictionary* hashes;

//signing info
@property(nonatomic, retain)NSDictionary* signingInfo;

//macho parser
@property(nonatomic, retain)MachO* parser;

//encrypted flag
@property BOOL isEncrypted;

//packed flag
@property BOOL isPacked;

//not found
@property BOOL notFound;

/* VIRUS TOTAL INFO */

//dictionary returned by VT
@property (nonatomic, retain)NSDictionary* vtInfo;


/* METHODS */

//init method
-(id)initWithParams:(NSDictionary*)params;

//machO parse
-(BOOL)parse;

//get task's name
// ->either from bundle or path's last component
-(NSString*)getName;

//get an icon for a process
-(NSImage*)getIcon;

//get signing info (which takes a while to generate)
// ->this method should be called in the background
-(void)generatedSigningInfo;

//get detailed info (which takes a while to generate)
// ->only shown to user if they click 'info' so this method should be called in the background
-(void)generateDetailedInfo;

//format the signing info dictionary
-(NSString*)formatSigningInfo;


@end
