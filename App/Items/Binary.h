//
//  Binary.h
//  TaskExplorer
//
//  Created by Patrick Wardle on 2/19/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//

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

//platform binary (per ES / csops)
// ->set for task binaries, from the extension's process info
@property BOOL isPlatformBinary;

//excluded from VirusTotal lookups?
// ->apple-signed, platform, or dyld-cache binaries; won't be malware, and (personal) API keys are limited to ~500 lookups/day
@property(nonatomic, readonly)BOOL isExcludedFromVT;

//loaded in
// ...host tasks (for dylibs; resolved from 'hosts')
@property(nonatomic, readonly)NSArray* loadedIn;

/* (KVC) QUERY PROPERTIES */
// ->readonly, computed; used by #keyword predicates & the assistant tools

//signer (enum Signer)
@property(nonatomic, readonly)NSNumber* signer;

//signed by apple (or in dyld shared cache)
@property(nonatomic, readonly)BOOL isApple;

//validly signed
@property(nonatomic, readonly)BOOL isSigned;

//flagged by VT
@property(nonatomic, readonly)BOOL isFlagged;

//unknown to VT
@property(nonatomic, readonly)BOOL isUnknownToVT;

//team id (from signing info)
@property(nonatomic, readonly)NSString* teamID;

//signing id (from signing info)
@property(nonatomic, readonly)NSString* signingID;

//hashes (md5, sha1)
@property(atomic, retain)NSDictionary* hashes;

//signing info
@property(atomic, retain)NSDictionary* signingInfo;

//signing info being generated (by another thread)?
@property BOOL generatingInfo;

//encrypted flag
@property BOOL isEncrypted;

//packed flag
@property BOOL isPacked;

//not found
@property BOOL notFound;

//in dyld cache
@property BOOL inCache;

/* VIRUS TOTAL INFO */

//dictionary returned by VT
@property (atomic, retain)NSDictionary* vtInfo;


/* METHODS */

//init method
-(id)initWithParams:(NSDictionary*)params;

//get task's name
// ->either from bundle or path's last component
-(NSString*)getName;

//get an icon for a process
-(NSImage*)getIcon;

//generate (binary) info via the extension: signing info & mach-o flags
// ->pid: dynamic signing check (0: static); no-op if already generated; should be called in the background
-(void)generateInfo:(pid_t)pid auditToken:(NSData*)auditToken;

//get signing info (which takes a while to generate)
// ->this method should be called in the background
-(void)generatedSigningInfo;

//get detailed info (which takes a while to generate)
// ->only shown to user if they click 'info' so this method should be called in the background
-(void)generateDetailedInfo;

//format the signing info dictionary
-(NSString*)formatSigningInfo;


@end
