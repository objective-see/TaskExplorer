//
//  file: XPCExtensionProto.h
//  project: TaskExplorer (shared)
//  description: methods exported by the (system) extension
//
//  created by Patrick Wardle
//  copyright (c) 2026 Objective-See. All rights reserved.
//

#ifndef XPCExtensionProto_h
#define XPCExtensionProto_h

#import <Foundation/Foundation.h>
#import <sys/types.h>

@protocol XPCExtensionProtocol

//check in
// used by the client to confirm the extension is up & accepting XPC connections
-(void)checkIn:(void (^)(BOOL))reply;

//check if extension has full disk access
// note: required for endpoint security (es_new_client fails w/ ERR_NOT_PERMITTED otherwise)
-(void)hasFullDiskAccess:(void (^)(BOOL))reply;

//enumerate all (running) processes
// reply: array of process dictionaries (see KEY_PROCESS_* in Consts.h)
-(void)enumerateProcesses:(void (^)(NSArray*))reply;

//enumerate (loaded) dylibs for a process
// reply: array of paths
-(void)enumerateDylibs:(pid_t)pid reply:(void (^)(NSArray*))reply;

//enumerate (open) files for a process
// reply: array of {path, fileType} dictionaries (see KEY_RESULT_PATH / KEY_FILE_TYPE); nil on failure
-(void)enumerateFiles:(pid_t)pid reply:(void (^)(NSArray*))reply;

//enumerate ALL dylibs (incl. those from the dyld shared cache) via vmmap
// ->slow-ish (~ms to ~2s per process), so used on demand / for the optional global index
-(void)enumerateAllDylibs:(pid_t)pid reply:(void (^)(NSArray*))reply;

//enumerate (all) network connections
// reply: array of connection dictionaries (see KEY_* in Consts.h)
-(void)enumerateConnections:(void (^)(NSArray*))reply;

//extract binary info (as root): code signing info & mach-o flags (encrypted/packed)
// ->these read the binary, which the app can't always do (e.g. 0511 root binaries such as sudo)
//   pid: dynamic signing check (then static via path, if that fails); pid 0: static check via path
//   reply: KEY_BINARY_SIGNING_INFO, KEY_BINARY_ENCRYPTED, KEY_BINARY_PACKED
-(void)extractBinaryInfo:(pid_t)pid auditToken:(NSData*)auditToken path:(NSString*)path reply:(void (^)(NSDictionary*))reply;

//hash a file (as root)
// ->separate (lazy) call, as hashing reads the whole file; reply: KEY_HASH_MD5, KEY_HASH_SHA1
-(void)hashFile:(NSString*)path reply:(void (^)(NSDictionary*))reply;

//start monitoring
// ES (exec/exit/mmap) + network (timer)
// events are delivered via the client's XPCAppProtocol
-(void)startMonitoring:(void (^)(BOOL))reply;

//stop monitoring
-(void)stopMonitoring:(void (^)(BOOL))reply;

@end

#endif /* XPCExtensionProto_h */
