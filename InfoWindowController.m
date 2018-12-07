//
//  InfoWindowController.m
//  TaskExplorer
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
    
    //no dark mode?
    // make window white
    if(YES != isDarkMode())
    {
        //make white
        self.window.backgroundColor = NSColor.whiteColor;
    }
    
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
        //load file info window
        else if(YES == [selectedItem isKindOfClass:[File class]])
        {
            //load nib
            self.windowController = [[InfoWindowController alloc] initWithWindowNibName:@"FileInfoWindow"];
        }
        
        //load networking info window
        else if(YES == [selectedItem isKindOfClass:[Connection class]])
        {
            //load nib
            self.windowController = [[InfoWindowController alloc] initWithWindowNibName:@"NetworkInfoWindow"];
        }
        
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
    
    //task arguments
    NSMutableString* taskArguments = nil;
    
    //binary
    // ->when showing info about a dylib
    Binary* dylib = nil;
    
    //file
    // ->when showing info about a file
    File* file = nil;
    
    //connection
    // ->when showing info about a connection
    Connection* connection = nil;

    //handle tasks
    if(YES == [self.itemObj isKindOfClass:[Task class]])
    {
        //cast as task
        task = (Task*)self.itemObj;
        
        //set icon
        self.icon.image = task.binary.icon;
        
        //set name
        [self.name setStringValue:[self valueForStringItem:task.binary.name default:@"unknown"]];
        
        //flagged items
        // ->make name red!
        if( (nil != task.binary.vtInfo) &&
            (0 != [task.binary.vtInfo[VT_RESULTS_POSITIVES] unsignedIntegerValue]) )
        {
            //red
            self.name.textColor = [NSColor redColor];
        }
        
        //set command line
        // ->done just in time (first time)
        if(nil == task.arguments)
        {
            //get args
            [((Task*)self.itemObj) getArguments];
        }
        
        //set default value for args
        self.arguments.stringValue = @"no arguments/unknown";
        
        //set any args
        // ->task path and name, make up the first to 'args', so skip/ignore those
        if(task.arguments.count > 2)
        {
            //alloc string to build up args
            taskArguments = [NSMutableString string];
            
            //build up args string
            // ->start at index 2, to skip path/name
            for(NSUInteger index = 2; index<task.arguments.count; index++)
            {
                //add arg
                [taskArguments appendFormat:@"%@ ", task.arguments[index]];
            }
            
            //set args into text field
            if(0 != taskArguments.length)
            {
                //add
                self.arguments.stringValue = taskArguments;
            }
        }
    
        //set path
        [self.path setStringValue:[self valueForStringItem:task.binary.path default:@"unknown"]];
        
        //hashes could still be, being generated
        // ->but don't want to wait, so just created em directly
        if(nil == task.binary.hashes[KEY_HASH_MD5])
        {
            //save hash
            task.binary.hashes = hashFile(task.binary.path);
        }
        
        //set hash
        [self.hashes setStringValue:[NSString stringWithFormat:@"%@ / %@", task.binary.hashes[KEY_HASH_MD5], task.binary.hashes[KEY_HASH_SHA1]]];
        
        //set size
        [self.size setStringValue:[NSString stringWithFormat:@"%llu bytes", task.binary.attributes.fileSize]];
        
        //set date
        [self.date setStringValue:[NSString stringWithFormat:@"%@ (created) / %@ (modified)", task.binary.attributes.fileCreationDate, task.binary.attributes.fileModificationDate]];
        
        //signing info still being generated?
        // ->but don't want to wait, so just created em directly
        if(nil == task.binary.signingInfo)
        {
            //generate signing info
            task.binary.signingInfo = extractSigningInfo(task.binary.path);
        }
        
        //set signing info
        [self.sign setStringValue:[self valueForStringItem:[task.binary formatSigningInfo] default:@"not signed"]];
    }
    
    //handle binaries (dylibs)
    else if(YES == [self.itemObj isKindOfClass:[Binary class]])
    {
        //cast as binary/dylib
        dylib = (Binary*)self.itemObj;
        
        //set icon
        self.icon.image = dylib.icon;
        
        //set name
        [self.name setStringValue:[self valueForStringItem:dylib.name default:@"unknown"]];
        
        //flagged items
        // ->make name red!
        if( (nil != dylib.vtInfo) &&
            (0 != [dylib.vtInfo[VT_RESULTS_POSITIVES] unsignedIntegerValue]) )
        {
            //red
            self.name.textColor = [NSColor redColor];
        }
        
        //set path
        [self.path setStringValue:[self valueForStringItem:dylib.path default:@"unknown"]];
        
        //hashes still being generated?
        // ->but don't want to wait, so just created em directly
        if(nil == dylib.hashes[KEY_HASH_MD5])
        {
            //save hash
            dylib.hashes = hashFile(dylib.path);
        }
        
        //set hash
        [self.hashes setStringValue:[NSString stringWithFormat:@"%@ / %@", dylib.hashes[KEY_HASH_MD5], dylib.hashes[KEY_HASH_SHA1]]];
        
        //set size
        [self.size setStringValue:[NSString stringWithFormat:@"%llu bytes", dylib.attributes.fileSize]];
        
        //set date
        [self.date setStringValue:[NSString stringWithFormat:@"%@ (created) / %@ (modified)", dylib.attributes.fileCreationDate, dylib.attributes.fileModificationDate]];
        
        //signing info still being generated?
        // ->but don't want to wait, so just created em directly
        if(nil == dylib.signingInfo)
        {
            //generate signing info
            dylib.signingInfo = extractSigningInfo(dylib.path);
        }
        
        //set signing info
        [self.sign setStringValue:[self valueForStringItem:[dylib formatSigningInfo] default:@"not signed"]];
    }
    
    //handle File class
    else if(YES == [self.itemObj isKindOfClass:[File class]])
    {
        //typecast
        file = (File*)self.itemObj;
        
        //first check if detailed info (such as 'type') was generated yet
        // ->when not, do it directly here
        if(nil == file.type)
        {
            //generated detailed info
            [file generateDetailedInfo];
        }
        
        //set icon
        self.icon.image = itemObj.icon;
        
        //set name
        [self.name setStringValue:self.itemObj.name];
        
        //set path
        [self.path setStringValue:self.itemObj.path];
        
        //set type
        [self.type setStringValue:[self valueForStringItem:file.type default:@"unknown"]];
        
        //set size
        [self.size setStringValue:[NSString stringWithFormat:@"%llu bytes", self.itemObj.attributes.fileSize]];
        
        //set date
        [self.date setStringValue:[NSString stringWithFormat:@"%@ (created) / %@ (modified)", self.itemObj.attributes.fileCreationDate, self.itemObj.attributes.fileModificationDate]];
    }
    
    //handle Connection class
    else if(YES == [self.itemObj isKindOfClass:[Connection class]])
    {
        //typecast
        connection = (Connection*)self.itemObj;
        
        //set icon
        self.icon.image = itemObj.icon;
        
        //set connection string
        [self.name setStringValue:connection.endpoints];
        
        //set type
        [self.type setStringValue:[self valueForStringItem:connection.type default:@"unknown"]];
        
        //set proto
        [self.protocol setStringValue:[self valueForStringItem:connection.proto default:@"unknown"]];
        
        //set family
        [self.family setStringValue:[self valueForStringItem:connection.family default:@"unknown"]];
        
        //set status
        [self.state setStringValue:[self valueForStringItem:connection.state default:@"unknown"]];
    }
    
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
