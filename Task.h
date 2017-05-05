//
//  Task.h
//  TaskExplorer
//
//  Created by Patrick Wardle on 5/2/15.
//  Copyright (c) 2015 Objective-See, LLC. All rights reserved.
//

#import "Binary.h"
#import <Foundation/Foundation.h>


/*

//32bit
struct dyld_image_info_32 {
    int	imageLoadAddress;
    int	imageFilePath;
    int imageFileModDate;
};
 
*/

@interface Task : NSObject
{
    //pid
    NSNumber* pid;
    
    //uid
    //uid_t uid;
    
    //main binary
    Binary* binary;
    
    //parent id
    NSNumber* ppid;
    
    //children (for tree view)
    NSMutableArray* children;
}


@property (nonatomic, retain)NSNumber* pid;

//main binary
@property(nonatomic, retain)Binary* binary;

//process args
@property(nonatomic, retain)NSMutableArray* arguments;

//loaded dylibs
@property(nonatomic, retain)NSMutableArray* dylibs;

//open files
@property(nonatomic, retain)NSMutableArray* files;

//connections
@property(nonatomic, retain)NSMutableArray* connections;

//uid
@property uid_t uid;

//parent's pid
@property (nonatomic, retain)NSNumber* ppid;

//children
@property (nonatomic, retain)NSMutableArray* children;


/* METHODS */

//init w/ a pid + path
// note: icons are dynamically determined only when process is shown in alert
-(id)initWithPID:(NSNumber*)taskPID;

//get task's path
// ->via 'proc_pidpath()' or via task's args ('KERN_PROCARGS2')
-(NSString*)getPath;

//get command-line args
-(void)getArguments;

//enumerate all dylibs
// ->new ones are added to 'existingDylibs' (global) dictionary
-(void)enumerateDylibs:(NSMutableDictionary*)allDylibs shouldWait:(BOOL)shouldWait;

//enumerate all open files
-(void)enumerateFiles:(BOOL)shouldWait;

//enumerate network sockets/connections
-(void)enumerateNetworking:(BOOL)shouldWait;

//convert self to JSON string
-(NSString*)toJSON;

@end
