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
            
        //unlock
        [self.queueCondition unlock];
            
        //generate hashes, etc
        [binary generateDetailedInfo];

        //inc (after processing, so 'in == out' really means 'all done')
        itemsOut++;
        
        //when VT is enabled (api key, not disabled, & connected)
        // add item for VT processing (unless excluded: apple/platform/dyld-cache binaries)
        // note: an item whose signing check failed (extension hiccup) is queued anyway; the lookup retries the check
        if( (YES == [virusTotal isEnabled]) &&
            ( (YES != binary.isExcludedFromVT) ||
              (SIGNING_STATUS_XPC_FAILED == [binary.signingInfo[KEY_SIGNATURE_STATUS] intValue]) ) )
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
