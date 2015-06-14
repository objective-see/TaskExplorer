//
//  File.h
//  KnockKnock
//
//  Created by Patrick Wardle on 2/19/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//

#import "ItemBase.h"

#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>

@interface File : ItemBase
{
    
}

/* PROPERTIES */

//name
@property(nonatomic, retain)NSString* name;

//path
@property(nonatomic, retain)NSString* path;

//plist
@property(nonatomic, retain)NSString* plist;

//bundle
@property(nonatomic, retain)NSBundle* bundle;

//hashes (md5, sha1)
@property(nonatomic, retain)NSDictionary* hashes;

//signing info
@property(nonatomic, retain)NSDictionary* signingInfo;




/* METHODS */

//init method
-(id)initWithParams:(NSDictionary*)params;

//get detailed info (which takes a while to generate)
// ->only shown to user if they click 'info' so this method is called in the background
-(void)generateDetailedInfo;

//format the signing info dictionary
-(NSString*)formatSigningInfo;


@end
