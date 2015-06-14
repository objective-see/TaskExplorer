//
//  serviceInterface.h
//  TaskExplorer
//
//  Created by Patrick Wardle on 5/27/15.
//  Copyright (c) 2015 Lucas Derraugh. All rights reserved.
//

#ifndef TaskExplorer_serviceInterface_h
#define TaskExplorer_serviceInterface_h

#import "Task.h"

@protocol remoteTaskProto
//- (void)compressFile:(NSFileHandle *)inFile toFile:(NSFileHandle *)outFile withReply:(void (^)(NSError *error))reply;

//enumerate loaded dylibs in a task
-(void)enumerateDylibs:(NSNumber*)taskPID withReply:(void (^)(NSMutableArray *))reply;

//enumerate open files in a task
-(void)enumerateFiles:(NSNumber*)taskPID withReply:(void (^)(NSMutableArray *))reply;

//enumerate network connections
-(void)enumerateNetwork:(NSNumber*)taskPID withReply:(void (^)(NSMutableArray *))reply;

@end



#endif
