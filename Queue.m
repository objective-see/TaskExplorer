//
//  Queue.m
//  BlockBlock
//
//  Created by Patrick Wardle on 9/26/14.
//  Copyright (c) 2014 Synack. All rights reserved.
//

#import "Queue.h"
#import "Consts.h"
#import "Binary.h"
#import "VirusTotal.h"
#import "AppDelegate.h"

@implementation Queue

@synthesize eventQueue;
@synthesize queueCondition;
@synthesize qProcessorThread;

-(id)init
{
    //init super
    self = [super init];
    if(nil != self)
    {
        //init queue
        eventQueue = [NSMutableArray array];
        
        //init empty condition
        queueCondition = [[NSCondition alloc] init];
        
        //spin up thread to watch/process queue
        self.qProcessorThread = [[NSThread alloc] initWithTarget:self selector:@selector(processQueue:) object:nil];
        
        //start it
        [self.qProcessorThread start];

    }
    
    return self;
}

//process events from Q
-(void)processQueue:(id)threadParam
{
    //Binary obj
    Binary* binary = nil;
    
    //nap for a bit
    // ->don't want UI thread, etc to suffer
    [NSThread sleepForTimeInterval:5.0f];
    
    //VT object
    VirusTotal* vtObject = nil;
    
    //grab VT object
    vtObject = ((AppDelegate*)[[NSApplication sharedApplication] delegate]).virusTotalObj;
    
    //for ever
    while(YES)
    {
        //pool
        @autoreleasepool {
    
        //lock
        [self.queueCondition lock];
        
        //wait while queue is empty
        while(YES == [self.eventQueue empty])
        {
            //wait
            [self.queueCondition wait];
        }
        
        //get item off queue
        binary = [eventQueue dequeue];
            
        //sanity check
        if(YES != [binary isKindOfClass:[Binary class]])
        {
            //ignore
            continue;
        }
        
        //process
        //->for now, just hash, etc
        [binary generateDetailedInfo];
            
        //add item for VT processing
        [vtObject addItem:binary];
        
            
        //unlock
        [self.queueCondition unlock];
            
        //pool
        }
        
    }//foreverz process queue
        
    return;
}


//add an object to the queue
-(void)enqueue:(id)anObject
{
    //lock
    [self.queueCondition lock];
    
    //add to queue
    [self.eventQueue enqueue:anObject];
    
    //signal
    [self.queueCondition signal];
    
    //unlock
    [self.queueCondition unlock];
    
    return;
}

//process binary
-(void)processBinary:(Binary*)binary
{
    
}

@end
