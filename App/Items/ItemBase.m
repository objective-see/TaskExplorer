//
//  ItemBase.m
//  TaskExplorer
//
//  Created by Patrick Wardle on 9/25/14.
//  Copyright (c) 2014 Objective-See. All rights reserved.
//

#import "Task.h"
#import "Consts.h"
#import "ItemBase.h"
#import "TaskEnumerator.h"

#define kErrFormat @"%@ not implemented in subclass %@"
#define kExceptName @"TaskExplorer Item"

/* GLOBALS */

//task enumerator
extern TaskEnumerator* taskEnumerator;

@implementation ItemBase

@synthesize name;
@synthesize path;
@synthesize hosts;
@synthesize attributes;

//init method
-(id)initWithParams:(NSDictionary*)params
{
    //super
    self = [super init];
    if(nil != self)
    {
        //extract/save name
        self.name = params[KEY_RESULT_NAME];

        //extract/save path
        self.path = params[KEY_RESULT_PATH];

        //init hosts
        hosts = [NSMutableSet set];
    }

    return self;
}

//return a path that can be opened in Finder.app
-(NSString*)pathForFinder
{
    return self.path;
}

//add a host (pid)
-(void)addHost:(NSNumber*)pid
{
    //sanity check
    if(nil == pid)
    {
        //bail
        return;
    }

    //sync
    @synchronized(self.hosts)
    {
        //add
        [self.hosts addObject:pid];
    }

    return;
}

//remove a host (pid)
-(void)removeHost:(NSNumber*)pid
{
    //sanity check
    if(nil == pid)
    {
        //bail
        return;
    }

    //sync
    @synchronized(self.hosts)
    {
        //remove
        [self.hosts removeObject:pid];
    }

    return;
}

//is item hosted by pid?
-(BOOL)isHostedBy:(NSNumber*)pid
{
    //flag
    BOOL isHosted = NO;

    //sync
    @synchronized(self.hosts)
    {
        //check
        isHosted = [self.hosts containsObject:pid];
    }

    return isHosted;
}

//number of hosts
-(NSUInteger)hostCount
{
    //count
    NSUInteger count = 0;

    //sync
    @synchronized(self.hosts)
    {
        //count
        count = self.hosts.count;
    }

    return count;
}

//host tasks
// ->resolves host pids to (live) task objects
-(NSArray<Task*>*)hostTasks
{
    //tasks
    NSMutableArray* tasks = nil;

    //(copy of) host pids
    NSArray* pids = nil;

    //task
    Task* task = nil;

    //init
    tasks = [NSMutableArray array];

    //sync
    @synchronized(self.hosts)
    {
        //copy
        pids = [self.hosts.allObjects sortedArrayUsingSelector:@selector(compare:)];
    }

    //resolve each
    for(NSNumber* pid in pids)
    {
        //sync
        @synchronized(taskEnumerator.tasks)
        {
            //lookup
            task = taskEnumerator.tasks[pid];
        }

        //add
        if(nil != task)
        {
            //add
            [tasks addObject:task];
        }
    }

    return tasks;
}

/* REQUIRED METHODS */

//stubs for inherited methods
// throw exceptions as they should be implemented in sub-classes

//convert object to JSON string
-(NSString*)toJSON
{
    @throw [NSException exceptionWithName:kExceptName
                                   reason:[NSString stringWithFormat:kErrFormat, NSStringFromSelector(_cmd), [self class]]
                                 userInfo:nil];
    return nil;
}

@end
