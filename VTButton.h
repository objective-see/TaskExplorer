//
//  vtButton.h
//  KnockKnock
//
//  Created by Patrick Wardle on 3/26/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//

#import "Binary.h"
#import <Cocoa/Cocoa.h>

//#import "ItemTableController.h"

@class TaskTableController;

@interface VTButton : NSButton
{
    
}

//properties

//parent object
@property(assign)TaskTableController *delegate;

//File object
@property(nonatomic, retain)Binary* binary;

//button's row index

//flag indicating press
@property BOOL mouseDown;

//flag indicating exit
@property BOOL mouseExit;



@end
