//
//  Queue.m
//  TaskExplorer
//
//  Created by Patrick Wardle on 9/26/14.
//  Copyright (c) 2014 Objective-See. All rights reserved.
//

#import "Queue.h"
#import "Consts.h"
#import "Binary.h"
#import "VirusTotal.h"
#import "AppDelegate.h"

@implementation Queue

@synthesize itemsIn;
@synthesize itemsOut;
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
            
        //inc
        itemsOut++;
            
        //unlock
        [self.queueCondition unlock];
            
        //generate hashes, etc
        [binary generateDetailedInfo];
        
        //when connected
        // add item for VT processing
        if(YES == isConnected)
        {
            //add
            [virusTotal addItem:binary];
        }
            
        } //pool
        
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
    
    //inc
    itemsIn++;

    //signal
    [self.queueCondition signal];
    
    //unlock
    [self.queueCondition unlock];
    
    return;
}

@end
