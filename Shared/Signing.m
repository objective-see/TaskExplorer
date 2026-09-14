//
//  File: Signing.m
//  Project: TaskExplorer (shared)
//
//  Created by: Patrick Wardle
//  Copyright:  2017 Objective-See
//

#import "Consts.h"
#import "Signing.h"
#import "Utilities.h"

#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>

//extract details (id, team id, entitlements, auths) from signing details
// shared logic for both dynamic and static code checks
static void extractSigningDetails(NSMutableDictionary* signingInfo, CFDictionaryRef signingDetails);

//generate signing info from a (dynamic) code ref
static NSMutableDictionary* signingInfoForDynamicCode(SecCodeRef dynamicCode, SecCSFlags flags);

//get the signing info of a item
// pid specified: extract dynamic code signing info
// path specified: generate static code signing info
NSMutableDictionary* extractSigningInfo(pid_t pid, NSString* path, SecCSFlags flags)
{
    //info dictionary
    NSMutableDictionary* signingInfo = nil;

    //status
    OSStatus status = !errSecSuccess;

    //static code ref
    SecStaticCodeRef staticCode = NULL;

    //dynamic code ref
    SecCodeRef dynamicCode = NULL;

    //signing details
    CFDictionaryRef signingDetails = NULL;

    //dynamic code checks
    // no path, dynamic check via pid
    if(nil == path)
    {
        //init signing status
        signingInfo = [NSMutableDictionary dictionary];

        //generate dynamic code ref via pid
        status = SecCodeCopyGuestWithAttributes(NULL, (__bridge CFDictionaryRef _Nullable)(@{(__bridge NSString *)kSecGuestAttributePid : [NSNumber numberWithInt:pid]}), kSecCSDefaultFlags, &dynamicCode);
        if(errSecSuccess != status)
        {
            //set error
            signingInfo[KEY_SIGNATURE_STATUS] = [NSNumber numberWithInt:status];

            //bail
            goto bail;
        }

        //generate info
        signingInfo = signingInfoForDynamicCode(dynamicCode, flags);
    }

    //static code checks
    else
    {
        //init signing status
        signingInfo = [NSMutableDictionary dictionary];

        //create static code ref via path
        status = SecStaticCodeCreateWithPath((__bridge CFURLRef)([NSURL fileURLWithPath:path]), kSecCSDefaultFlags, &staticCode);
        if(errSecSuccess != status)
        {
            //set error
            signingInfo[KEY_SIGNATURE_STATUS] = [NSNumber numberWithInt:status];

            //bail
            goto bail;
        }

        //check signature
        status = SecStaticCodeCheckValidity(staticCode, flags, NULL);
        if(errSecSuccess != status)
        {
            //set error
            signingInfo[KEY_SIGNATURE_STATUS] = [NSNumber numberWithInt:status];

            //bail
            goto bail;
        }

        //happily signed
        signingInfo[KEY_SIGNATURE_STATUS] = [NSNumber numberWithInt:errSecSuccess];

        //determine signer
        // apple, app store, dev id, adhoc, etc...
        signingInfo[KEY_SIGNATURE_SIGNER] = extractSigner(staticCode, flags, NO);

        //extract signing info
        status = SecCodeCopySigningInformation(staticCode, kSecCSSigningInformation, &signingDetails);
        if(errSecSuccess != status)
        {
            //bail
            goto bail;
        }

        //extract details
        extractSigningDetails(signingInfo, signingDetails);
    }

bail:

    //free signing info
    if(NULL != signingDetails)
    {
        //free
        CFRelease(signingDetails);

        //unset
        signingDetails = NULL;
    }

    //free dynamic code
    if(NULL != dynamicCode)
    {
        //free
        CFRelease(dynamicCode);

        //unset
        dynamicCode = NULL;
    }

    //free static code
    if(NULL != staticCode)
    {
        //free
        CFRelease(staticCode);

        //unset
        staticCode = NULL;
    }

    return signingInfo;
}

//get the signing info of a (running) item via its audit token
// note: dynamic code signing check
NSMutableDictionary* extractSigningInfoForToken(audit_token_t* token, SecCSFlags flags)
{
    //info dictionary
    NSMutableDictionary* signingInfo = nil;

    //status
    OSStatus status = !errSecSuccess;

    //dynamic code ref
    SecCodeRef dynamicCode = NULL;

    //init signing status
    signingInfo = [NSMutableDictionary dictionary];

    //obtain dynamic code ref from (audit) token
    status = SecCodeCopyGuestWithAttributes(NULL, (__bridge CFDictionaryRef _Nullable)(@{(__bridge NSString *)kSecGuestAttributeAudit:[NSData dataWithBytes:token length:sizeof(audit_token_t)]}), kSecCSDefaultFlags, &dynamicCode);
    if(errSecSuccess != status)
    {
        //set error
        signingInfo[KEY_SIGNATURE_STATUS] = [NSNumber numberWithInt:status];

        //bail
        goto bail;
    }

    //generate info
    signingInfo = signingInfoForDynamicCode(dynamicCode, flags);

bail:

    //free dynamic code
    if(NULL != dynamicCode)
    {
        //free
        CFRelease(dynamicCode);

        //unset
        dynamicCode = NULL;
    }

    return signingInfo;
}

//generate signing info from a (dynamic) code ref
static NSMutableDictionary* signingInfoForDynamicCode(SecCodeRef dynamicCode, SecCSFlags flags)
{
    //info dictionary
    NSMutableDictionary* signingInfo = nil;

    //status
    OSStatus status = !errSecSuccess;

    //signing details
    CFDictionaryRef signingDetails = NULL;

    //init signing status
    signingInfo = [NSMutableDictionary dictionary];

    //validate code
    status = SecCodeCheckValidity(dynamicCode, flags, NULL);
    if(errSecSuccess != status)
    {
        //set error
        signingInfo[KEY_SIGNATURE_STATUS] = [NSNumber numberWithInt:status];

        //bail
        goto bail;
    }

    //happily signed
    signingInfo[KEY_SIGNATURE_STATUS] = [NSNumber numberWithInt:errSecSuccess];

    //determine signer
    // apple, app store, dev id, adhoc, etc...
    signingInfo[KEY_SIGNATURE_SIGNER] = extractSigner((SecStaticCodeRef)dynamicCode, flags, YES);

    //extract signing info
    status = SecCodeCopySigningInformation(dynamicCode, kSecCSSigningInformation, &signingDetails);
    if(errSecSuccess != status)
    {
        //bail
        goto bail;
    }

    //extract details
    extractSigningDetails(signingInfo, signingDetails);

bail:

    //free signing info
    if(NULL != signingDetails)
    {
        //free
        CFRelease(signingDetails);

        //unset
        signingDetails = NULL;
    }

    return signingInfo;
}

//extract details (id, team id, entitlements, auths) from signing details
// shared logic for both dynamic and static code checks
static NSString* hexString(NSData* data);

static void extractSigningDetails(NSMutableDictionary* signingInfo, CFDictionaryRef signingDetails)
{
    //signing authorities
    NSMutableArray* signingAuths = nil;

    //extract code signing id
    if(nil != [(__bridge NSDictionary*)signingDetails objectForKey:(__bridge NSString*)kSecCodeInfoIdentifier])
    {
        //extract/save
        signingInfo[KEY_SIGNATURE_IDENTIFIER] = [(__bridge NSDictionary*)signingDetails objectForKey:(__bridge NSString*)kSecCodeInfoIdentifier];
    }

    //extract team id
    if(nil != [(__bridge NSDictionary*)signingDetails objectForKey:(__bridge NSString*)kSecCodeInfoTeamIdentifier])
    {
        //extract/save
        signingInfo[KEY_SIGNATURE_TEAM_ID] = [(__bridge NSDictionary*)signingDetails objectForKey:(__bridge NSString*)kSecCodeInfoTeamIdentifier];
    }

    //extract entitlements
    if(nil != [(__bridge NSDictionary*)signingDetails objectForKey:(__bridge NSString*)kSecCodeInfoEntitlementsDict])
    {
        //extract/save
        signingInfo[KEY_SIGNATURE_ENTITLEMENTS] = [(__bridge NSDictionary*)signingDetails objectForKey:(__bridge NSString*)kSecCodeInfoEntitlementsDict];
    }

    //extract signing authorities
    signingAuths = extractSigningAuths((__bridge NSDictionary *)(signingDetails));
    if(0 != signingAuths.count)
    {
        //save
        signingInfo[KEY_SIGNATURE_AUTHORITIES] = signingAuths;
    }

    //extract code directory hashes ('cdhashes-full': one per hash type; typically SHA-1 & SHA-256)
    // ->as hex strings (plist/XPC friendly); same approach as WhatsYourSign
    {
        //all
        id cdHashes = ((__bridge NSDictionary*)signingDetails)[@"cdhashes-full"];
        NSArray* hashes = [cdHashes isKindOfClass:[NSDictionary class]] ? [(NSDictionary*)cdHashes allValues] :
                          ([cdHashes isKindOfClass:[NSArray class]] ? (NSArray*)cdHashes : @[]);

        //add each
        for(NSData* hash in hashes)
        {
            //sanity check
            if(YES != [hash isKindOfClass:[NSData class]])
            {
                //skip
                continue;
            }

            //by length
            if(CC_SHA1_DIGEST_LENGTH == hash.length)
            {
                //sha-1
                signingInfo[KEY_SIGNATURE_CDHASH_SHA1] = hexString(hash);
            }
            else if(CC_SHA256_DIGEST_LENGTH == hash.length)
            {
                //sha-256
                signingInfo[KEY_SIGNATURE_CDHASH_SHA256] = hexString(hash);
            }
        }

        //none? fall back to 'kSecCodeInfoUnique' (the sha-1 cdhash)
        if( (nil == signingInfo[KEY_SIGNATURE_CDHASH_SHA1]) &&
            (nil == signingInfo[KEY_SIGNATURE_CDHASH_SHA256]) )
        {
            //unique
            NSData* unique = ((__bridge NSDictionary*)signingDetails)[(__bridge NSString*)kSecCodeInfoUnique];
            if( (YES == [unique isKindOfClass:[NSData class]]) &&
                (CC_SHA1_DIGEST_LENGTH == unique.length) )
            {
                //save
                signingInfo[KEY_SIGNATURE_CDHASH_SHA1] = hexString(unique);
            }
        }
    }

    return;
}

//bytes -> (uppercase) hex string
static NSString* hexString(NSData* data)
{
    //hex
    NSMutableString* hex = [NSMutableString stringWithCapacity:data.length * 2];

    //bytes
    const unsigned char* bytes = data.bytes;

    //format each
    for(NSUInteger i = 0; i < data.length; i++)
    {
        //append
        [hex appendFormat:@"%02X", bytes[i]];
    }

    return hex;
}

//determine who signed item
NSNumber* extractSigner(SecStaticCodeRef code, SecCSFlags flags, BOOL isDynamic)
{
    //result
    NSNumber* signer = nil;

    //"anchor apple"
    static SecRequirementRef isApple = nil;

    //"anchor apple generic"
    static SecRequirementRef isDevID = nil;

    //"Apple Mac OS Application Signing"
    static SecRequirementRef isAppStore = nil;

    //"Apple iPhone OS Application Signing"
    static SecRequirementRef isiOSAppStore = nil;

    //Apple's app store team ids
    static NSSet* appleTeamIDs = nil;

    //signing details
    CFDictionaryRef signingDetails = NULL;

    //team id
    NSString* teamID = nil;

    //token
    static dispatch_once_t onceToken = 0;

    //only once
    // init requirements
    dispatch_once(&onceToken, ^{

        //init apple signing requirement
        SecRequirementCreateWithString(CFSTR("anchor apple"), kSecCSDefaultFlags, &isApple);

        //init dev id signing requirement
        SecRequirementCreateWithString(CFSTR("anchor apple generic"), kSecCSDefaultFlags, &isDevID);

        //init (macOS) app store signing requirement
        SecRequirementCreateWithString(CFSTR("anchor apple generic and certificate leaf [subject.CN] = \"Apple Mac OS Application Signing\""), kSecCSDefaultFlags, &isAppStore);

        //init (iOS) app store signing requirement
        SecRequirementCreateWithString(CFSTR("anchor apple generic and certificate leaf [subject.CN] = \"Apple iPhone OS Application Signing\""), kSecCSDefaultFlags, &isiOSAppStore);

        //init Apple's App Store team IDs
        appleTeamIDs = [NSSet setWithArray:@[@"K36BKF7T3D", @"74J34U3R6X", @"59GAB85EFG", @"APPLECOMPUTER"]];
    });

    //check 1: "is apple" (proper)
    if(errSecSuccess == validateRequirement(code, isApple, flags, isDynamic))
    {
        //set signer to apple
        signer = [NSNumber numberWithInt:Apple];
    }

    //check 2: "is app store"
    // note: this is more specific than dev id, so do it first
    else if(errSecSuccess == validateRequirement(code, isAppStore, flags, isDynamic))
    {
        //default signer to app store
        signer = [NSNumber numberWithInt:AppStore];

        //however, set back to apple
        // ...if it's one of apple's app store apps
        if(errSecSuccess == SecCodeCopySigningInformation(code, kSecCSSigningInformation, &signingDetails))
        {
            //extract team id
            // and check if it belongs to apple
            teamID = [(__bridge NSDictionary*)signingDetails objectForKey:(__bridge NSString*)kSecCodeInfoTeamIdentifier];
            if( (nil != teamID) &&
                (YES == [appleTeamIDs containsObject:teamID]))
            {
               //set signer to apple
               signer = [NSNumber numberWithInt:Apple];
            }

            //release
            CFRelease(signingDetails);
            signingDetails = NULL;
        }
    }

    //check 3: "is (iOS) app store"
    // note: this is more specific than dev id, so also do it first
    else if(errSecSuccess == validateRequirement(code, isiOSAppStore, flags, isDynamic))
    {
        //set signer to app store
        signer = [NSNumber numberWithInt:AppStore];
    }

    //check 4: "is dev id"
    else if(errSecSuccess == validateRequirement(code, isDevID, flags, isDynamic))
    {
        //set signer to dev id
        signer = [NSNumber numberWithInt:DevID];
    }

    //otherwise
    // has to be adhoc?
    else
    {
        //set signer to ad hoc
        signer = [NSNumber numberWithInt:AdHoc];
    }

    return signer;
}

//validate a requirement
OSStatus validateRequirement(SecStaticCodeRef code, SecRequirementRef requirement, SecCSFlags flags, BOOL isDynamic)
{
    //result
    OSStatus result = -1;

    //dynamic check?
    if(YES == isDynamic)
    {
        //validate dynamically
        result = SecCodeCheckValidity((SecCodeRef)code, flags, requirement);
    }
    //static check
    else
    {
        //validate statically
        result = SecStaticCodeCheckValidity(code, flags, requirement);
    }

    return result;
}

//extract (names) of signing auths
NSMutableArray* extractSigningAuths(NSDictionary* signingDetails)
{
    //signing auths
    NSMutableArray* authorities = nil;

    //cert chain
    NSArray* certificateChain = nil;

    //index
    NSUInteger index = 0;

    //cert
    SecCertificateRef certificate = NULL;

    //common name on chert
    CFStringRef commonName = NULL;

    //init array for certificate names
    authorities = [NSMutableArray array];

    //get cert chain
    certificateChain = [signingDetails objectForKey:(__bridge NSString*)kSecCodeInfoCertificates];
    if(0 == certificateChain.count)
    {
        //no certs
        goto bail;
    }

    //extract/save name of all certs
    for(index = 0; index < certificateChain.count; index++)
    {
        //reset
        commonName = NULL;

        //extract cert
        certificate = (__bridge SecCertificateRef)([certificateChain objectAtIndex:index]);

        //get common name
        if( (errSecSuccess == SecCertificateCopyCommonName(certificate, &commonName)) &&
            (NULL != commonName) )
        {
            //save
            [authorities addObject:(__bridge id _Nonnull)(commonName)];

            //release
            CFRelease(commonName);
        }
    }

bail:

    return authorities;
}
