//
//  kkRowCell.m
//  KnockKnock
//
//  Created by Patrick Wardle on 4/6/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//

#import "kkRowCell.h"

@implementation kkRowCell

@synthesize tag;


//draw method
- (void)drawRect:(NSRect)dirtyRect
{
    //draw custom color
    if(nil != self.color)
    {
        //set color
        [self.color set];
        
        //fill
        NSRectFill([self bounds]);
    }
}

//set background color
// ->always light!
- (void)setBackgroundStyle:(NSBackgroundStyle)backgroundStyle
{
    [super setBackgroundStyle: NSBackgroundStyleLight];
}


@end
