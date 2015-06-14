//
//  InfoWindowController.m
//  KnockKnock
//
//  Created by Patrick Wardle on 2/21/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//

#import "Task.h"
#import "File.h"
#import "Binary.h"
#import "Connection.h"
#import "Consts.h"
#import "Utilities.h"
#import "InfoWindowController.h"

@interface InfoWindowController ()

@end

@implementation InfoWindowController

@synthesize itemObj;

//automatically invoked when window is loaded
// ->set to white
-(void)windowDidLoad
{
    //super
    [super windowDidLoad];
    
    //make white
    [self.window setBackgroundColor: NSColor.whiteColor];
    
    return;
}

//init method
// ->save item and load nib
-(id)initWithItem:(id)selectedItem
{
    self = [super init];
    if(nil != self)
    {
        //load task info window
        if(YES == [selectedItem isKindOfClass:[Task class]])
        {
            //load nib
            self.windowController = [[InfoWindowController alloc] initWithWindowNibName:@"TaskInfoWindow"];
        }
        //load binary info window
        else if(YES == [selectedItem isKindOfClass:[Binary class]])
        {
            //load nib
            self.windowController = [[InfoWindowController alloc] initWithWindowNibName:@"DylibInfoWindow"];
        }
        
        /*TODO: delete this and xibs?
        
        //load file info window
        else if(YES == [selectedItem isKindOfClass:[File class]])
        {
            //load nib
            self.windowController = [[InfoWindowController alloc] initWithWindowNibName:@"FileInfoWindow"];
        }
        //load extension info window
        else if(YES == [selectedItem isKindOfClass:[Connection class]])
        {
            //load nib
            self.windowController = [[InfoWindowController alloc] initWithWindowNibName:@"ConnectionInfoWindow"];
        }
        */
         
        //save item
        self.windowController.itemObj = selectedItem;
    }
        
    return self;
}


//automatically called when nib is loaded
// ->save self into iVar, and center window
-(void)awakeFromNib
{
    //configure UI
    [self configure];
    
    //center
    [self.window center];
}

//configure window
// ->add item's attributes (name, path, etc.)
-(void)configure
{
    //task
    // ->when showing info about a task
    Task* task = nil;
    
    //binary
    // ->when showing info about a dylib
    Binary* dylib = nil;
    
    //handle tasks
    if(YES == [self.itemObj isKindOfClass:[Task class]])
    {
        //cast as task
        task = (Task*)self.itemObj;
        
        //set icon
        self.icon.image = task.binary.icon;
        
        //set name
        [self.name setStringValue:[self valueForStringItem:task.binary.name default:@"unknown"]];
        
        //set command line
        // ->done just in time (first time)
        if(nil == task.arguments)
        {
            //get args
            [((Task*)self.itemObj) getArguments];
        }
        
        //set args
        [self.arguments setStringValue:[self valueForStringItem:[task.arguments componentsJoinedByString:@""] default:@"no arguments"]];
        
        /*
        //flagged files
        // ->make name red!
        if( (nil != ((File*)self.itemObj).vtInfo) &&
           (0 != [((File*)self.itemObj).vtInfo[VT_RESULTS_POSITIVES] unsignedIntegerValue]) )
        {
            //set color (light red)
            self.name.textColor = [NSColor redColor];
        }
        */
         
        //set path
        [self.path setStringValue:[self valueForStringItem:task.binary.path default:@"unknown"]];
        
        
        //set hash
        [self.hashes setStringValue:[NSString stringWithFormat:@"%@ / %@", task.binary.hashes[KEY_HASH_MD5], task.binary.hashes[KEY_HASH_SHA1]]];
        
        //set size
        [self.size setStringValue:[NSString stringWithFormat:@"%llu bytes", task.binary.attributes.fileSize]];
        
        //set date
        [self.date setStringValue:[NSString stringWithFormat:@"%@ (created) / %@ (modified)", task.binary.attributes.fileCreationDate, task.binary.attributes.fileModificationDate]];
        
        //set signing info
        [self.sign setStringValue:[self valueForStringItem:[task.binary formatSigningInfo] default:@"not signed"]];
    }
    
    //handle tasks
    else if(YES == [self.itemObj isKindOfClass:[Binary class]])
    {
        //type cast
        dylib = (Binary*)self.itemObj;
        
        //set icon
        self.icon.image = dylib.icon;
        
        //set name
        [self.name setStringValue:[self valueForStringItem:dylib.name default:@"unknown"]];
        
    
        /*
         //flagged files
         // ->make name red!
         if( (nil != ((File*)self.itemObj).vtInfo) &&
         (0 != [((File*)self.itemObj).vtInfo[VT_RESULTS_POSITIVES] unsignedIntegerValue]) )
         {
         //set color (light red)
         self.name.textColor = [NSColor redColor];
         }
         */
        
        //set path
        [self.path setStringValue:[self valueForStringItem:dylib.path default:@"unknown"]];
        
        
        //set hash
        [self.hashes setStringValue:[NSString stringWithFormat:@"%@ / %@", dylib.hashes[KEY_HASH_MD5], task.binary.hashes[KEY_HASH_SHA1]]];
        
        //set size
        [self.size setStringValue:[NSString stringWithFormat:@"%llu bytes", dylib.attributes.fileSize]];
        
        //set date
        [self.date setStringValue:[NSString stringWithFormat:@"%@ (created) / %@ (modified)", dylib.attributes.fileCreationDate, task.binary.attributes.fileModificationDate]];
        
        //set signing info
        [self.sign setStringValue:[self valueForStringItem:[dylib formatSigningInfo] default:@"not signed"]];
    }
    
    
    //handle File class
    else if(YES == [self.itemObj isKindOfClass:[File class]])
    {
        //set icon
        self.icon.image = getIconForBinary(self.itemObj.path, ((File*)itemObj).bundle);
        
        //set name
        [self.name setStringValue:self.itemObj.name];
        
        /*
        
        //flagged files
        // ->make name red!
        if( (nil != ((Binary*)self.itemObj).vtInfo) &&
            (0 != [((File*)self.itemObj).vtInfo[VT_RESULTS_POSITIVES] unsignedIntegerValue]) )
        {
            //set color (light red)
            self.name.textColor = [NSColor redColor];
        }
         
        */
        
        //set path
        [self.path setStringValue:self.itemObj.path];
        
        //set hash
        [self.hashes setStringValue:[NSString stringWithFormat:@"%@ / %@", ((File*)self.itemObj).hashes[KEY_HASH_MD5], ((File*)self.itemObj).hashes[KEY_HASH_SHA1]]];
        
        //set size
        [self.size setStringValue:[NSString stringWithFormat:@"%llu bytes", ((File*)self.itemObj).attributes.fileSize]];
        
        //set date
        [self.date setStringValue:[NSString stringWithFormat:@"%@ (created) / %@ (modified)", ((File*)self.itemObj).attributes.fileCreationDate, ((File*)self.itemObj).attributes.fileModificationDate]];
        
        //set plist
        if(nil != ((File*)self.itemObj).plist)
        {
            //set
            [self.plist setStringValue:((File*)self.itemObj).plist];
        }
        //no plist
        else
        {
            //set
            [self.plist setStringValue:@"no plist for item"];
        }
        
        //set signing info
        [self.sign setStringValue:[(File*)self.itemObj formatSigningInfo]];
    }
    
    /*
    //handle Extension class
    if(YES == [self.itemObj isKindOfClass:[Extension class]])
    {
        //set icon
        self.icon.image = getIconForBinary(((Extension*)itemObj).browser, nil);
        
        //set name
        [self.name setStringValue:self.itemObj.name];
        
        //set path
        [self.path setStringValue:self.itemObj.path];
        
        //set description
        // ->optional
        if(nil != ((Extension*)self.itemObj).details)
        {
            //set
            [self.details setStringValue:[NSString stringWithFormat:@"%@", ((Extension*)self.itemObj).details]];
        }
               
        //set id
        [self.identifier setStringValue:[NSString stringWithFormat:@"%@", ((Extension*)self.itemObj).identifier]];
        
        //set date
        [self.date setStringValue:[NSString stringWithFormat:@"%@ (created) / %@ (modified)", ((File*)self.itemObj).attributes.fileCreationDate, ((File*)self.itemObj).attributes.fileModificationDate]];
        
        //set signing info
        //[self.sign setStringValue:[(File*)self.itemObj formatSigningInfo]];
    }
    */
    
    return;
}

                
//check if something is nil
// ->if so, return the default
-(NSString*)valueForStringItem:(NSString*)item default:(NSString*)defaultValue
{
    //return value
    NSString* value = nil;
    
    //check if item is nil/blank
    if( (nil != item) &&
        (item.length != 0))
    {
        //just set to item
        value = item;
    }
    else
    {
        //set to default
        value = defaultValue;
    }
    
    return value;
}

//automatically invoked when user clicks 'close'
// ->just close window
-(IBAction)closeWindow:(id)sender
{
    //close
    [self.window close];
}
@end
