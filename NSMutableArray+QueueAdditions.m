//
//  NSMutableArray+QueueAdditions.m
//  BlockBlock
//
//  Created by Patrick Wardle on 9/26/14.
//  Copyright (c) 2014 Synack. All rights reserved.
//

#import "NSMutableArray+QueueAdditions.h"

@implementation NSMutableArray (QueueAdditions)

//add object to tail (end) of queue
-(void)enqueue:(id)anObject
{
    //sync
    @synchronized(self)
    {
        //add object
        [self addObject: anObject];
    }
}

//grab next item in queue
-(id)dequeue
{
    //extract object
    id queueObject = nil;
    
    //sync
    @synchronized(self)
    {
        //check to make sure there are some items
        if(YES != [self empty])
        {
            //extract first one
            queueObject = [self objectAtIndex: 0];
            
            //delete it from queue
            [self removeObjectAtIndex: 0];
        }
        
    }//sync
    
    return queueObject;
}

// Checks if the queue is empty
-(BOOL)empty
{
    return ([self lastObject] == nil);
}

@end