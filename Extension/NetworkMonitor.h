//
//  file: NetworkMonitor.h
//  project: TaskExplorer (extension)
//  description: network (connection) monitor, via (private) NetworkStatistics framework (header)
//
//  created by Patrick Wardle
//  copyright (c) 2026 Objective-See. All rights reserved.
//

#ifndef NetworkMonitor_h
#define NetworkMonitor_h

#import <Foundation/Foundation.h>

//wish there was a `NetworkStatistics.h`
// mahalo J. Levin:
//   https://twitter.com/Morpheus______
//   http://newosxbook.com/src.jl?tree=listings&file=netbottom.c
//
// note: NetworkStatistics is a private framework (no SDK stub)
//       so we resolve its APIs at runtime via dlopen/dlsym

NS_ASSUME_NONNULL_BEGIN

typedef void *NStatSourceRef;
typedef NSObject* NStatManagerRef;

//function pointer types
typedef NStatManagerRef _Nullable (*NStatManagerCreate_t)(const struct __CFAllocator * _Nullable, dispatch_queue_t, void (^)(void * _Nullable, void * _Nullable));
typedef void (*NStatSourceSetDescriptionBlock_t)(NStatSourceRef arg, void (^)(NSDictionary*));
typedef void (*NStatSourceSetRemovedBlock_t)(NStatSourceRef arg, void (^)(void));
typedef void (*NStatManagerAddAll_t)(NStatManagerRef manager);
typedef void (*NStatManagerQueryAll_t)(NStatManagerRef manager, void (^)(void));
typedef void (*NStatManagerDestroy_t)(NStatManagerRef manager);
typedef int (*NStatManagerSetFlags_t)(NStatManagerRef, int Flags);

NS_ASSUME_NONNULL_END

/* TYPEDEFS */

//callback block
// array of connection dictionaries
typedef void (^NetworkCallbackBlock)(NSArray* _Nonnull);

@interface NetworkMonitor : NSObject

//(debug) callback counters

/* PROPERTIES */

//queue
@property(nullable) dispatch_queue_t queue;

//timer
@property(nullable) dispatch_source_t timer;

//nstat manager
@property(nullable) NStatManagerRef manager;

//connections
// key: nstat source, value: connection dictionary
@property(nonatomic, retain)NSMutableDictionary* _Nonnull connections;

/* METHODS */

//enumerate (all) connections
// async, invokes callback when done
-(void)enumerate:(NetworkCallbackBlock _Nonnull)callback;

//start (network) monitoring
// (re)enumerates every 'refreshRate' seconds, invoking callback each time
-(void)start:(NSUInteger)refreshRate callback:(NetworkCallbackBlock _Nonnull)callback;

//stop
-(void)stop;

@end

#endif /* NetworkMonitor_h */
