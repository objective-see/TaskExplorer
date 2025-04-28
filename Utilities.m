//
//  Utilities.m
//  TaskExplorer
//
//  Created by Patrick Wardle on 2/7/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//


#import "Consts.h"
#import "Utilities.h"

#import <dlfcn.h>
#import <signal.h>
#import <unistd.h>
#import <syslog.h>
#import <libproc.h>
#import <sys/sysctl.h>
#import <Security/Security.h>
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <CoreServices/CoreServices.h>
#import <Collaboration/Collaboration.h>
#import <SystemConfiguration/SystemConfiguration.h>

//TODO: remove
/*
//disable std err
void disableSTDERR()
{
    //file handle
    int devNull = -1;
    
    //open /dev/null
    devNull = open("/dev/null", O_RDWR);
    
    //dup
    dup2(devNull, STDERR_FILENO);
    
    //close
    close(devNull);
    
    return;
}


//loads a framework
// note: assumes it is in 'Framework' dir
NSBundle* loadFramework(NSString* name)
{
    //handle
    NSBundle* framework = nil;
    
    //framework path
    NSString* path = nil;
    
    //init path
    path = [NSString stringWithFormat:@"%@/../Frameworks/%@", [NSProcessInfo.processInfo.arguments[0] stringByDeletingLastPathComponent], name];
    
    //standardize path
    path = [path stringByStandardizingPath];
    
    //init framework (bundle)
    framework = [NSBundle bundleWithPath:path];
    if(NULL == framework)
    {
        //bail
        goto bail;
    }
    
    //load framework
    if(YES != [framework loadAndReturnError:nil])
    {
        //bail
        goto bail;
    }
    
bail:
    
    return framework;
}


//check if OS is supported
// ->Lion and newer
BOOL isSupportedOS()
{
    //return
    BOOL isSupported = NO;
    
    //major version
    SInt32 versionMajor = 0;
    
    //minor version
    SInt32 versionMinor = 0;
    
    //get major version
    versionMajor = getVersion(gestaltSystemVersionMajor);
    
    //get minor version
    versionMinor = getVersion(gestaltSystemVersionMinor);
    
    //sanity check
    if( (-1 == versionMajor) ||
        (-1 == versionMinor) )
    {
        //err
        goto bail;
    }
    
    //check that OS is supported
    // ->10.8+ ?
    if( (versionMajor == OS_MAJOR_VERSION_X) &&
        (versionMinor >= OS_MINOR_VERSION_LION) )
    {
        //set flag
        isSupported = YES;
    }
    
//bail
bail:
    
    return isSupported;
}
 
*/

//get OS's major or minor version
SInt32 getVersion(OSType selector)
{
    //version
    // ->major or minor
    SInt32 version = -1;
    
    //get version info
    if(noErr != Gestalt(selector, &version))
    {
        //reset version
        version = -1;
        
        //err
        goto bail;
    }
    
//bail
bail:
    
    return version;
}

/*
//get the signing info of a file
NSDictionary* extractSigningInfo(NSString* path)
{
    //info dictionary
    NSMutableDictionary* signingStatus = nil;
    
    //code
    SecStaticCodeRef staticCode = NULL;
    
    //status
    OSStatus status = !STATUS_SUCCESS;
    
    //signing information
    CFDictionaryRef signingInformation = NULL;
    
    //cert chain
    NSArray* certificateChain = nil;
    
    //index
    NSUInteger index = 0;
    
    //cert
    SecCertificateRef certificate = NULL;
    
    //common name on chert
    CFStringRef commonName = NULL;
    
    //init signing status
    signingStatus = [NSMutableDictionary dictionary];
    
    //create static code
    status = SecStaticCodeCreateWithPath((__bridge CFURLRef)([NSURL fileURLWithPath:path]), kSecCSDefaultFlags, &staticCode);
    
    //save signature status
    signingStatus[KEY_SIGNATURE_STATUS] = [NSNumber numberWithInt:status];
    
    //sanity check
    if(STATUS_SUCCESS != status)
    {
        //err msg
        //syslog(LOG_ERR, "OBJECTIVE-SEE ERROR: SecStaticCodeCreateWithPath() failed on %s with %d", [path UTF8String], status);
        
        //bail
        goto bail;
    }
    
    //check signature
    status = SecStaticCodeCheckValidityWithErrors(staticCode, kSecCSDoNotValidateResources, NULL, NULL);
    
    //(re)save signature status
    signingStatus[KEY_SIGNATURE_STATUS] = [NSNumber numberWithInt:status];
    
    //if file is signed
    // ->grab signing authorities
    if(STATUS_SUCCESS == status)
    {
        //grab signing authorities
        status = SecCodeCopySigningInformation(staticCode, kSecCSSigningInformation, &signingInformation);
        
        //sanity check
        if(STATUS_SUCCESS != status)
        {
            //err msg
            //syslog(LOG_ERR, "OBJECTIVE-SEE ERROR: SecCodeCopySigningInformation() failed on %s with %d", [path UTF8String], status);
            
            //bail
            goto bail;
        }
        
        //determine if binary is signed by Apple
        signingStatus[KEY_SIGNING_IS_APPLE] = [NSNumber numberWithBool:isApple(path)];
    }
    //error
    // ->not signed, or something else, so no need to check cert's names
    else
    {
        //bail
        goto bail;
    }
    
    //init array for certificate names
    signingStatus[KEY_SIGNING_AUTHORITIES] = [NSMutableArray array];
    
    //get cert chain
    certificateChain = [(__bridge NSDictionary*)signingInformation objectForKey:(__bridge NSString*)kSecCodeInfoCertificates];
    
    //handle case there is no cert chain
    // ->adhoc? (/Library/Frameworks/OpenVPN.framework/Versions/Current/bin/openvpn-service)
    if(0 == certificateChain.count)
    {
        //set
        [signingStatus[KEY_SIGNING_AUTHORITIES] addObject:@"signed, but no signing authorities (adhoc?)"];
    }
    
    //got cert chain
    // ->add each to list
    else
    {
        //get name of all certs
        for(index = 0; index < certificateChain.count; index++)
        {
            //extract cert
            certificate = (__bridge SecCertificateRef)([certificateChain objectAtIndex:index]);
            
            //get common name
            status = SecCertificateCopyCommonName(certificate, &commonName);
            
            //skip ones that error out
            if( (STATUS_SUCCESS != status) ||
                (NULL == commonName))
            {
                //skip
                continue;
            }
            
            //save
            [signingStatus[KEY_SIGNING_AUTHORITIES] addObject:(__bridge NSString*)commonName];
            
            //release name
            CFRelease(commonName);
        }
    }
    
//bail
bail:
    
    //free signing info
    if(NULL != signingInformation)
    {
        //free
        CFRelease(signingInformation);
    }
    
    //free static code
    if(NULL != staticCode)
    {
        //free
        CFRelease(staticCode);
    }
    
    return signingStatus;
}

//determine if a file is signed by Apple proper
BOOL isApple(NSString* path)
{
    //flag
    BOOL isApple = NO;
    
    //code
    SecStaticCodeRef staticCode = NULL;
    
    //signing reqs
    SecRequirementRef requirementRef = NULL;
    
    //status
    OSStatus status = -1;
    
    //create static code
    status = SecStaticCodeCreateWithPath((__bridge CFURLRef)([NSURL fileURLWithPath:path]), kSecCSDefaultFlags, &staticCode);
    if(STATUS_SUCCESS != status)
    {
        //err msg
        syslog(LOG_ERR, "OBJECTIVE-SEE ERROR: SecStaticCodeCreateWithPath() failed on %s with %d", [path UTF8String], status);
        
        //bail
        goto bail;
    }
    
    //create req string w/ 'anchor apple'
    // (3rd party: 'anchor apple generic')
    status = SecRequirementCreateWithString(CFSTR("anchor apple"), kSecCSDefaultFlags, &requirementRef);
    if( (STATUS_SUCCESS != status) ||
        (requirementRef == NULL) )
    {
        //err msg
        syslog(LOG_ERR, "OBJECTIVE-SEE ERROR: SecRequirementCreateWithString() failed on %s with %d", [path UTF8String], status);
        
        //bail
        goto bail;
    }
    
    //check if file is signed by apple by checking if it conforms to req string
    // note: ignore 'errSecCSBadResource' as lots of signed apple files return this issue :/
    status = SecStaticCodeCheckValidity(staticCode, kSecCSDefaultFlags, requirementRef);
    if( (STATUS_SUCCESS != status) &&
        (errSecCSBadResource != status) )
    {
        //bail
        // ->just means app isn't signed by apple
        goto bail;
    }
    
    //ok, happy (SecStaticCodeCheckValidity() didn't fail)
    // ->file is signed by Apple
    isApple = YES;
    
//bail
bail:
    
    //free req reference
    if(NULL != requirementRef)
    {
        //free
        CFRelease(requirementRef);
    }

    //free static code
    if(NULL != staticCode)
    {
        //free
        CFRelease(staticCode);
    }

    return isApple;
}
*/

//given a directory and a filter predicate
// ->return all matches
NSArray* directoryContents(NSString* directory, NSString* predicate)
{
    //(unfiltered) directory contents
    NSArray* directoryContents = nil;
    
    //matches
    NSArray* matches = nil;
    
    //get (unfiltered) directory contents
    directoryContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:nil];
    
    //filter out matches
    if(nil != predicate)
    {
        //filter
        matches = [directoryContents filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:predicate]];
    }
    //no need to filter
    else
    {
        //no filter
        matches = directoryContents;
    }

    return matches;
}

//given a path to binary
// parse it back up to find app's bundle
NSBundle* findAppBundle(NSString* binaryPath)
{
    //app's bundle
    NSBundle* appBundle = nil;
    
    //app's path
    NSString* appPath = nil;
    
    //first just try full path
    appPath = binaryPath;
    
    //try to find the app's bundle/info dictionary
    do
    {
        //try to load app's bundle
        appBundle = [NSBundle bundleWithPath:appPath];
        
        //check for match
        // ->binary path's match
        if( (nil != appBundle) &&
            (YES == [appBundle.executablePath isEqualToString:binaryPath]))
        {
            //all done
            break;
        }
        
        //always unset bundle var since it's being returned
        // ->and at this point, its not a match
        appBundle = nil;
        
        //remove last part
        // ->will try this next
        appPath = [appPath stringByDeletingLastPathComponent];
        
        //scan until we get to root
        // ->of course, loop will be exited if app info dictionary is found/loaded
    } while( (nil != appPath) &&
             (YES != [appPath isEqualToString:@"/"]) &&
             (YES != [appPath isEqualToString:@""]) );
    
    return appBundle;
}

//hash a file
// ->md5 and sha1
NSDictionary* hashFile(NSString* filePath)
{
    //file hashes
    NSDictionary* hashes = nil;
    
    //file's contents
    NSData* fileContents = nil;
    
    //hash digest (md5)
    uint8_t digestMD5[CC_MD5_DIGEST_LENGTH] = {0};
    
    //md5 hash as string
    NSMutableString* md5 = nil;
    
    //hash digest (sha1)
    uint8_t digestSHA1[CC_SHA1_DIGEST_LENGTH] = {0};
    
    //sha1 hash as string
    NSMutableString* sha1 = nil;
    
    //index var
    NSUInteger index = 0;
    
    //init md5 hash string
    md5 = [NSMutableString string];
    
    //init sha1 hash string
    sha1 = [NSMutableString string];
    
    //load file
    if(nil == (fileContents = [NSData dataWithContentsOfFile:filePath]))
    {
        //err msg
        //syslog(LOG_ERR, "OBJECTIVE-SEE ERROR: couldn't load %s to hash", [filePath UTF8String]);
        
        //bail
        goto bail;
    }
    
    //md5 it
    CC_MD5(fileContents.bytes, (unsigned int)fileContents.length, digestMD5);
    
    //convert to NSString
    // ->iterate over each bytes in computed digest and format
    for(index=0; index < CC_MD5_DIGEST_LENGTH; index++)
    {
        //format/append
        [md5 appendFormat:@"%02lX", (unsigned long)digestMD5[index]];
    }
    
    //sha1 it
    CC_SHA1(fileContents.bytes, (unsigned int)fileContents.length, digestSHA1);
    
    //convert to NSString
    // ->iterate over each bytes in computed digest and format
    for(index=0; index < CC_SHA1_DIGEST_LENGTH; index++)
    {
        //format/append
        [sha1 appendFormat:@"%02lX", (unsigned long)digestSHA1[index]];
    }
    
    //init hash dictionary
    hashes = @{KEY_HASH_MD5: md5, KEY_HASH_SHA1: sha1};
    
//bail
bail:
    
    return hashes;
}

//get app's version
// ->extracted from Info.plist
NSString* getAppVersion()
{
    //read and return 'CFBundleVersion' from bundle
    return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
}

//convert a textview to a clickable hyperlink
void makeTextViewHyperlink(NSTextField* textField, NSURL* url)
{
    //hyperlink
    NSMutableAttributedString *hyperlinkString = nil;
    
    //range
    NSRange range = {0};
    
    //init hyper link
    hyperlinkString = [[NSMutableAttributedString alloc] initWithString:textField.stringValue];
    
    //init range
    range = NSMakeRange(0, [hyperlinkString length]);
   
    //start editing
    [hyperlinkString beginEditing];
    
    //add url
    [hyperlinkString addAttribute:NSLinkAttributeName value:url range:range];
    
    //make it blue
    [hyperlinkString addAttribute:NSForegroundColorAttributeName value:[NSColor blueColor] range:NSMakeRange(0, [hyperlinkString length])];
    
    //underline
    [hyperlinkString addAttribute:
     NSUnderlineStyleAttributeName value:[NSNumber numberWithInt:NSSingleUnderlineStyle] range:NSMakeRange(0, [hyperlinkString length])];
    
    //done editing
    [hyperlinkString endEditing];
    
    //set text
    [textField setAttributedStringValue:hyperlinkString];
    
    return;
}

//set the color of an attributed string
NSMutableAttributedString* setStringColor(NSAttributedString* string, NSColor* color)
{
    //colored string
    NSMutableAttributedString *coloredString = nil;

    //alloc/init colored string from existing one
    coloredString = [[NSMutableAttributedString alloc] initWithAttributedString:string];
    
    //set color
    [coloredString addAttribute:NSForegroundColorAttributeName value:color range:NSMakeRange(0, [coloredString length])];
    
    return coloredString;
}

//exec a process with args
// if 'shouldWait' is set, wait and return stdout/in and termination status
NSMutableDictionary* execTask(NSString* binaryPath, NSArray* arguments, BOOL shouldWait)
{
    //task
    NSTask* task = nil;
    
    //output pipe for stdout
    NSPipe* stdOutPipe = nil;
    
    //output pipe for stderr
    NSPipe* stdErrPipe = nil;
    
    //read handle for stdout
    NSFileHandle* stdOutReadHandle = nil;
    
    //read handle for stderr
    NSFileHandle* stdErrReadHandle = nil;
    
    //results dictionary
    NSMutableDictionary* results = nil;
    
    //output for stdout
    NSMutableData *stdOutData = nil;
    
    //output for stderr
    NSMutableData *stdErrData = nil;
    
    //init dictionary for results
    results = [NSMutableDictionary dictionary];
    
    //init task
    task = [NSTask new];
    
    //only setup pipes if wait flag is set
    if(YES == shouldWait)
    {
        //init stdout pipe
        stdOutPipe = [NSPipe pipe];
        
        //init stderr pipe
        stdErrPipe = [NSPipe pipe];
        
        //init stdout read handle
        stdOutReadHandle = [stdOutPipe fileHandleForReading];
        
        //init stderr read handle
        stdErrReadHandle = [stdErrPipe fileHandleForReading];
        
        //init stdout output buffer
        stdOutData = [NSMutableData data];
        
        //init stderr output buffer
        stdErrData = [NSMutableData data];
        
        //set task's stdout
        task.standardOutput = stdOutPipe;
        
        //set task's stderr
        task.standardError = stdErrPipe;
    }
    
    //set task's path
    task.launchPath = binaryPath;
    
    //set task's args
    if(nil != arguments)
    {
        //set
        task.arguments = arguments;
    }
    
    //wrap task launch
    @try
    {
        //launch
        [task launch];
    }
    @catch(NSException *exception)
    {
        //bail
        goto bail;
    }
    
    //no need to wait
    // can just bail w/ no output
    if(YES != shouldWait)
    {
        //bail
        goto bail;
    }
    
    //read in stdout/stderr
    while(YES == [task isRunning])
    {
        //accumulate stdout
        [stdOutData appendData:[stdOutReadHandle readDataToEndOfFile]];
        
        //accumulate stderr
        [stdErrData appendData:[stdErrReadHandle readDataToEndOfFile]];
    }
    
    //grab any leftover stdout
    [stdOutData appendData:[stdOutReadHandle readDataToEndOfFile]];
    
    //grab any leftover stderr
    [stdErrData appendData:[stdErrReadHandle readDataToEndOfFile]];
    
    //add stdout
    if(0 != stdOutData.length)
    {
        //add
        results[STDOUT] = stdOutData;
    }
    
    //add stderr
    if(0 != stdErrData.length)
    {
        //add
        results[STDERR] = stdErrData;
    }
    
    //add exit code
    results[EXIT_CODE] = [NSNumber numberWithInteger:task.terminationStatus];
    
bail:
    
    return results;
}


//wait until a window is non nil
// ->then make it modal
void makeModal(NSWindowController* windowController)
{
    //wait up to 1 second window to be non-nil
    // ->then make modal
    for(int i=0; i<20; i++)
    {
        //can make it modal once we have a window
        if(nil != windowController.window)
        {
            //make modal on main thread
            dispatch_sync(dispatch_get_main_queue(), ^{
                
                //make app front
                [NSApp activateIgnoringOtherApps:YES];
                
                //modal
                [[NSApplication sharedApplication] runModalForWindow:windowController.window];
                
            });
            
            //all done
            break;
        }
        
        //nap
        [NSThread sleepForTimeInterval:0.05f];

    }//until 1 second
    
    return;
}

//given a pid, get its parent (ppid)
pid_t getParentID(int pid)
{
    //parent id
    pid_t parentID = -1;
    
    //kinfo_proc struct
    struct kinfo_proc processStruct = {0};
    
    //size
    size_t procBufferSize = sizeof(processStruct);
    
    //syscall result
    int sysctlResult = -1;
    
    //init mib
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pid};
    
    //make syscall
    sysctlResult = sysctl(mib, sizeof(mib)/sizeof(*mib), &processStruct, &procBufferSize, NULL, 0);
    
    //check if got ppid
    if( (STATUS_SUCCESS == sysctlResult) &&
        (0 != procBufferSize) )
    {
        //save ppid
        parentID = processStruct.kp_eproc.e_ppid;
    }
    
    return parentID;
}

//get path to XPC service
NSString* getPath2XPC()
{
    //path to XPC service
    NSString* xpcService = nil;
    
    //build path
    xpcService = [NSString stringWithFormat:@"%@/Contents/XPCServices/%@", [[NSBundle mainBundle] bundlePath], XPC_SERVICE];
    
    //make sure its there
    if(YES != [[NSFileManager defaultManager] fileExistsAtPath:xpcService])
    {
        //nope
        // ->nil out
        xpcService = nil;
    }
    
    return xpcService;
}

//get path to kernel
NSString* path2Kernel()
{
    //kernel path
    NSString* kernel;
    
    //check Yosemite's location first
    if(YES == [[NSFileManager defaultManager] fileExistsAtPath:KERNEL_YOSEMITE])
    {
        //set
        kernel = KERNEL_YOSEMITE;
    }
    //go w/ older location
    else
    {
        //set
        kernel = KERNEL_PRE_YOSEMITE;
    }
    
    return kernel;
}

//determine if process is (still) alive
BOOL isAlive(pid_t targetPID)
{
    //flag
    BOOL isAlive = YES;
    
    //reset errno
    errno = 0;
    
    //'management info base' array
    int mib[4] = {0};
    
    //kinfo proc
    struct kinfo_proc procInfo = {0};
    
    //try 'kill' with 0
    // ->no harm done, but will fail with 'ESRCH' if process is dead
    kill(targetPID, 0);
    
    //dead proc -> 'ESRCH'
    // ->'No such process'
    if(ESRCH == errno)
    {
        //dead
        isAlive = NO;
        
        //bail
        goto bail;
    }
    
    //size
    size_t size = 0;
    
    //init mib
    mib[0] = CTL_KERN;
    mib[1] = KERN_PROC;
    mib[2] = KERN_PROC_PID;
    mib[3] = targetPID;
    
    //init size
    size = sizeof(procInfo);

    //get task's flags
    // ->allows to check for zombies
    if(0 == sysctl(mib, sizeof(mib)/sizeof(*mib), &procInfo, &size, NULL, 0))
    {
        //check for zombies
        if(((procInfo.kp_proc.p_stat) & SZOMB) == SZOMB)
        {
            //dead
            isAlive = NO;
            
            //bail
            goto bail;
            
        }
    }
    
//bail
bail:
    
    return isAlive;
}

//check if computer has network connection
BOOL isNetworkConnected()
{
    //flag
    BOOL isConnected = NO;
    
    //sock addr stuct
    struct sockaddr zeroAddress = {0};
    
    //reachability ref
    SCNetworkReachabilityRef reachabilityRef = NULL;
    
    //reachability flags
    SCNetworkReachabilityFlags flags = 0;
    
    //reachable flag
    BOOL isReachable = NO;
    
    //connection required flag
    BOOL connectionRequired = NO;
    
    //ensure its cleared out
    bzero(&zeroAddress, sizeof(zeroAddress));
    
    //set size
    zeroAddress.sa_len = sizeof(zeroAddress);
    
    //set family
    zeroAddress.sa_family = AF_INET;
    
    //create reachability ref
    reachabilityRef = SCNetworkReachabilityCreateWithAddress(NULL, (const struct sockaddr*)&zeroAddress);
    
    //sanity check
    if(NULL == reachabilityRef)
    {
        //bail
        goto bail;
    }
    
    //get flags
    if(TRUE != SCNetworkReachabilityGetFlags(reachabilityRef, &flags))
    {
        //bail
        goto bail;
    }
    
    //set reachable flag
    isReachable = ((flags & kSCNetworkFlagsReachable) != 0);
    
    //set connection required flag
    connectionRequired = ((flags & kSCNetworkFlagsConnectionRequired) != 0);
    
    //finally
    // ->determine if network is available
    isConnected = (isReachable && !connectionRequired) ? YES : NO;
    
//bail
bail:
    
    //cleanup
    if(NULL != reachabilityRef)
    {
        //release
        CFRelease(reachabilityRef);
    }
    
    return isConnected;
}

//set or unset button's highlight
void buttonAppearance(NSTableView* table, NSEvent* event, BOOL shouldReset)
{
    //mouse point
    NSPoint mousePoint = {0};
    
    //row index
    NSUInteger rowIndex = -1;
    
    //current row
    NSTableCellView* currentRow = nil;
    
    //tag
    NSUInteger tag = 0;
    
    //button
    NSButton* button = nil;
    
    //image name
    NSString* imageName =  nil;
    
    //extract tag
    tag = [((NSDictionary*)event.userData)[@"tag"] unsignedIntegerValue];
    
    //restore button back to default (visual) state
    if(YES == shouldReset)
    {
        //set image name
        // ->'info'
        if(TABLE_ROW_INFO_BUTTON == tag)
        {
            //set
            imageName = @"info";
        }
        //set image name
        // ->'info'
        else if(TABLE_ROW_SHOW_BUTTON == tag)
        {
            //set
            imageName = @"show";
        }
    }
    //highlight button
    else
    {
        //set image name
        // ->'info'
        if(TABLE_ROW_INFO_BUTTON == tag)
        {
            //set
            imageName = @"infoOver";
        }
        //set image name
        // ->'info'
        else if(TABLE_ROW_SHOW_BUTTON == tag)
        {
            //set
            imageName = @"showOver";
        }
    }
    
    //grab mouse point
    mousePoint = [table convertPoint:[event locationInWindow] fromView:nil];
    
    //compute row indow
    rowIndex = [table rowAtPoint:mousePoint];
    
    //sanity check
    if(-1 == rowIndex)
    {
        //bail
        goto bail;
    }
    
    //get row that's about to be selected
    currentRow = [table viewAtColumn:0 row:rowIndex makeIfNecessary:YES];
    
    //get button
    // ->tag id of button, passed in userData var
    button = [currentRow viewWithTag:[((NSDictionary*)event.userData)[@"tag"] unsignedIntegerValue]];
    if(nil == button)
    {
        //bail
        goto bail;
    }
    
    //restore default button image
    // ->for 'info' and 'show' buttons
    if(nil != imageName)
    {
        //set image
        [button setImage:[NSImage imageNamed:imageName]];
    }
    
//bail
bail:
    
    return;
}

//check	if remote process is i386
BOOL Is32Bit(pid_t targetPID)
{
    //info struct
    struct proc_bsdshortinfo procInfo = {0};
    
    //flag
    BOOL isI386 = NO;
    
    //get proc info
    if(proc_pidinfo(targetPID, PROC_PIDT_SHORTBSDINFO, 0, &procInfo, PROC_PIDT_SHORTBSDINFO_SIZE) <= 0)
    {
        //error
        goto bail;
    }
    
    //check 64bit process flag
    if(PROC_FLAG_LP64 != (procInfo.pbsi_flags & PROC_FLAG_LP64))
    {
        //not x86_64
        // ->thus, i386
        isI386 = YES;
    }
    
//bail
bail:
    
    return isI386;    
}

//check if app is translocated
// ->based on http://lapcatsoftware.com/articles/detect-app-translocation.html
NSURL* getUnTranslocatedURL()
{
    //orignal URL
    NSURL* untranslocatedURL = nil;
    
    //function def for 'SecTranslocateIsTranslocatedURL'
    Boolean (*mySecTranslocateIsTranslocatedURL)(CFURLRef path, bool *isTranslocated, CFErrorRef * __nullable error);
    
    //function def for 'SecTranslocateCreateOriginalPathForURL'
    CFURLRef __nullable (*mySecTranslocateCreateOriginalPathForURL)(CFURLRef translocatedPath, CFErrorRef * __nullable error);
    
    //flag for API request
    bool isTranslocated = false;
    
    //handle for security framework
    void *handle = NULL;
    
    //app path
    NSURL* appPath = nil;
    
    //init app's path
    appPath = [NSURL fileURLWithPath:[[NSBundle mainBundle] bundlePath]];
    
    //check ignore pre-macOS Sierra
    if(floor(NSAppKitVersionNumber) <= APPKIT_VERSION_10_11)
    {
        //bail
        goto bail;
    }
    
    //open security framework
    handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY);
    if(NULL == handle)
    {
        //bail
        goto bail;
    }
    
    //get 'SecTranslocateIsTranslocatedURL' API
    mySecTranslocateIsTranslocatedURL = dlsym(handle, "SecTranslocateIsTranslocatedURL");
    if(NULL == mySecTranslocateIsTranslocatedURL)
    {
        //bail
        goto bail;
    }
    
    //get
    mySecTranslocateCreateOriginalPathForURL = dlsym(handle, "SecTranslocateCreateOriginalPathForURL");
    if(NULL == mySecTranslocateCreateOriginalPathForURL)
    {
        //bail
        goto bail;
    }
    
    //invoke it
    if(true != mySecTranslocateIsTranslocatedURL((__bridge CFURLRef)appPath, &isTranslocated, NULL))
    {
        //bail
        goto bail;
    }
   
    //bail if app isn't translocated
    if(true != isTranslocated)
    {
        //bail
        goto bail;
    }
    
    //get original URL
    untranslocatedURL = (__bridge NSURL*)mySecTranslocateCreateOriginalPathForURL((__bridge CFURLRef)appPath, NULL);

//bail
bail:
    
    //close handle
    if(NULL != handle)
    {
        //close
        dlclose(handle);
    }
    
    return untranslocatedURL;
}

//get all user
// includes name/home directory
NSMutableDictionary* allUsers()
{
    //users
    NSMutableDictionary* users = nil;
    
    //query
    CSIdentityQueryRef query = nil;
    
    //query results
    CFArrayRef results = NULL;
    
    //error
    CFErrorRef error = NULL;
    
    //identiry
    CBIdentity* identity = NULL;
    
    //alloc dictionary
    users = [NSMutableDictionary dictionary];
    
    //init query
    query = CSIdentityQueryCreate(NULL, kCSIdentityClassUser, CSGetLocalIdentityAuthority());
    
    //exec query
    if(true != CSIdentityQueryExecute(query, 0, &error))
    {
        //bail
        goto bail;
    }
    
    //grab results
    results = CSIdentityQueryCopyResults(query);
    
    //process all results
    // add user and home directory
    for (int i = 0; i < CFArrayGetCount(results); ++i)
    {
        //grab identity
        identity = [CBIdentity identityWithCSIdentity:(CSIdentityRef)CFArrayGetValueAtIndex(results, i)];
        
        //add user
        users[identity.UUIDString] = @{USER_NAME:identity.posixName, USER_DIRECTORY:NSHomeDirectoryForUser(identity.posixName)};
    }
    
bail:
    
    //release results
    if(NULL != results)
    {
        //release
        CFRelease(results);
    }
    
    //release query
    if(NULL != query)
    {
        //release
        CFRelease(query);
    }
    
    return users;
}

//give a list of paths
// convert any `~` to all or current user
NSMutableArray* expandPaths(const __strong NSString* const paths[], int count)
{
    //expanded paths
    NSMutableArray* expandedPaths = nil;
    
    //(current) path
    const NSString* path = nil;
    
    //all users
    NSMutableDictionary* users = nil;
    
    //grab all users
    users = allUsers();
    
    //alloc list
    expandedPaths = [NSMutableArray array];
    
    //iterate/expand
    for(NSInteger i = 0; i < count; i++)
    {
        //grab path
        path = paths[i];
        
        //no `~`?
        // just add and continue
        if(YES != [path hasPrefix:@"~"])
        {
            //add as is
            [expandedPaths addObject:path];
            
            //next
            continue;
        }
        
        //handle '~' case
        // root? add each user
        if(0 == geteuid())
        {
            //add each user
            for(NSString* user in users)
            {
                [expandedPaths addObject:[users[user][USER_DIRECTORY] stringByAppendingPathComponent:[path substringFromIndex:1]]];
            }
        }
        //otherwise
        // just convert to current user
        else
        {
            [expandedPaths addObject:[path stringByExpandingTildeInPath]];
        }
    }
    
    return expandedPaths;
}

//dark mode?
BOOL isDarkMode(void)
{
    return [NSApp.effectiveAppearance.name isEqualToString:NSAppearanceNameDarkAqua];
}


//bring an app to foreground (to get an icon in the dock) or background
void transformProcess(ProcessApplicationTransformState location)
{
    //process serial no
    ProcessSerialNumber processSerialNo;
    
    //init process stuct
    // ->high to 0
    processSerialNo.highLongOfPSN = 0;
    
    //init process stuct
    // ->low to self
    processSerialNo.lowLongOfPSN = kCurrentProcess;
    
    //transform to foreground
    TransformProcessType(&processSerialNo, location);
    
    return;
}

//check if file is in shared cache
// uses private _dyld_shared_cache_contains_path API
BOOL isInSharedCache(NSString* path)
{
    if (@available(macOS 11.0, *)) {
        return _dyld_shared_cache_contains_path(path.UTF8String);
    }
    return NO;
}
