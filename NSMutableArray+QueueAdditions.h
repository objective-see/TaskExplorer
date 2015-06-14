//
//  NSMutableArray+QueueAdditions.h
//  BlockBlock
//
//  Created by Patrick Wardle on 9/26/14.
//  Copyright (c) 2014 Synack. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSMutableArray (QueueAdditions)
{
    
}

//METHODS

//remove first object
-(id)dequeue;

//add to end
-(void)enqueue:(id)obj;

//check if empty
-(BOOL)empty;

@end
