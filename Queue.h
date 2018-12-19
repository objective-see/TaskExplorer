//
//  Queue.h
//  BlockBlock
//
//  Created by Patrick Wardle on 9/26/14.
//  Copyright (c) 2014 Synack. All rights reserved.
//

//from: https://github.com/esromneb/ios-queue-object/blob/master/NSMutableArray%2BQueueAdditions.h

#import <Foundation/Foundation.h>
#import "NSMutableArray+QueueAdditions.h"

@interface Queue : NSObject
{
    //the queue
    NSMutableArray* eventQueue;
    
    //queue processor thread
    NSThread* qProcessorThread;
    
    //condition for queue's status
    NSCondition* queueCondition;

}

/* PROPERTIES */

//items in
@property NSUInteger itemsIn;

//items out
@property NSUInteger itemsOut;

//event queue
@property(retain, atomic)NSMutableArray* eventQueue;

//thread to process events
@property (nonatomic, retain)NSThread* qProcessorThread;

//condition for queue
@property (nonatomic, retain)NSCondition* queueCondition;

//METHODS

//add an object to the queue
-(void)enqueue:(id)anObject;

//process events from queue
-(void)processQueue:(id)threadParam;

@end
