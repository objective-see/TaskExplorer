//
//  CustomTextField.m
//  SearchField
//
//  Created by Patrick Wardle on 8/27/15.
//
//

#import "CustomTextField.h"
#import "AppDelegate.h"

@implementation CustomTextField

@synthesize owner;
@synthesize lastMovement;

//subclass override
// ->see: http://stackoverflow.com/questions/5163646/how-to-make-nssearchfield-send-action-upon-autocompletion/5360535#5360535
-(void)insertCompletion:(NSString *)word forPartialWordRange:(NSRange)charRange movement:(NSInteger)movement isFinal:(BOOL)flag
{
    //suppress completion if user types a space
    if(movement == NSRightTextMovement)
    {
        //bail
        goto bail;
    }
    
    //ignore if 2x 'enter'
    if( (movement == NSReturnTextMovement) &&
        (self.lastMovement == NSReturnTextMovement) )
    {
        //bail
        goto bail;
    }
    
    //update
    self.lastMovement = movement;
     
    //show full replacements
    if(0 != charRange.location)
    {
        //update length
        charRange.length += charRange.location;
        
        //reset location
        charRange.location = 0;
    }
    
    //insert completion
    // ->will use updated char range!
    [super insertCompletion:word forPartialWordRange:charRange movement:movement isFinal:flag];
    
    //on enter
    // ->call up into app delegate to process (filter)
    if(movement == NSReturnTextMovement)
    {
        //call up into owner to process
        [owner filterAutoComplete:self];
    }
    
//bail
bail:
    
    return;
}

@end
