//
//  CustomTextField.h
//  SearchField
//
//  Created by Patrick Wardle on 8/27/15.
//
//

#import <Cocoa/Cocoa.h>

//NSTextView subclass
// 1) fixes issue with non-alphanumeric characters in keyword matches
// 2) triggers action when user hits enter (1x)
@interface CustomTextField : NSTextView
{
    
}

//'owner'
@property (nonatomic, retain)id owner;

@end
