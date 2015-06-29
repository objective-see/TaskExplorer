//
//  InfoWindowController.h
//  KnockKnock
//
//  Created by Patrick Wardle on 2/21/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class ItemBase;

@interface InfoWindowController : NSWindowController <NSWindowDelegate>
{
    
}

//properties in window
// ->attributes about the item
@property(weak)IBOutlet NSImageView *icon;
@property(weak)IBOutlet NSTextField *name;
@property(weak)IBOutlet NSTextField *path;
@property(weak)IBOutlet NSTextField *date;


//task-specific outlets
@property (weak) IBOutlet NSTextField *arguments;



//file window specific outlets
@property(weak)IBOutlet NSTextField *hashes;
@property(weak)IBOutlet NSTextField *size;
@property(weak)IBOutlet NSTextField *sign;

//file window specific outlets
@property (weak) IBOutlet NSTextField *type;

//network window specific outlets

@property (weak) IBOutlet NSTextField *connection;
@property (weak) IBOutlet NSTextField *protocol;
@property (weak) IBOutlet NSTextField *family;
@property (weak) IBOutlet NSTextField *state;



//window controller
@property(nonatomic, strong)InfoWindowController *windowController;

//item
@property(nonatomic, retain)ItemBase* itemObj;

/* METHODS */

//init method
// ->save item and load nib
-(id)initWithItem:(id)selectedItem;

//configure window
// ->add item's attributes (name, path, etc.)
-(void)configure;

//check if something is nil
// ->if so, return the default
-(NSString*)valueForStringItem:(NSString*)item default:(NSString*)defaultValue;

//close button handler
-(IBAction)closeWindow:(id)sender;

@end
