//
//  File: Signing.h
//  Project: TaskExplorer (shared)
//
//  Created by: Patrick Wardle
//  Copyright:  2017 Objective-See
//

#ifndef Signing_h
#define Signing_h

#import <Security/Security.h>
#import <Foundation/Foundation.h>

/* FUNCTIONS */

//get the signing info of a item
// pid specified: extract dynamic code signing info
// path specified: generate static code signing info
NSMutableDictionary* extractSigningInfo(pid_t pid, NSString* path, SecCSFlags flags);

//get the signing info of a (running) item via its audit token
// note: dynamic code signing check
NSMutableDictionary* extractSigningInfoForToken(audit_token_t* token, SecCSFlags flags);

//determine who signed item
NSNumber* extractSigner(SecStaticCodeRef code, SecCSFlags flags, BOOL isDynamic);

//validate a requirement
OSStatus validateRequirement(SecStaticCodeRef code, SecRequirementRef requirement, SecCSFlags flags, BOOL isDynamic);

//extract (names) of signing auths
NSMutableArray* extractSigningAuths(NSDictionary* signingDetails);

#endif
