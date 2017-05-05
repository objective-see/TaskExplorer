//
//  File.m
//  TaskExplorer
//
//  Created by Patrick Wardle on 2/19/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//
#import "File.h"
#import "Consts.h"
#import "Utilities.h"
#import "AppDelegate.h"

#import <syslog.h>

@implementation File

@synthesize type;


//init method
-(id)initWithParams:(NSDictionary*)params
{
    //super
    // ->saves path, etc
    self = [super initWithParams:params];
    if(self)
    {
        //extract name
        self.name = [[self.path lastPathComponent] stringByDeletingPathExtension];
     
        //set icon
        self.icon = [[NSWorkspace sharedWorkspace] iconForFile:self.path];
        
        //grab attributes
        self.attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:self.path error:nil];
    }
           
//bail
bail:
    
    return self;
}

//set file type
// ->invokes 'file' cmd, the parses out result
-(void)setFileType
{
    //results from 'file' cmd
    NSString* results = nil;
    
    //array of parsed results
    NSArray* parsedResults = nil;
    
    //exec 'file' to get file type
    results = [[NSString alloc] initWithData:execTask(FILE, @[self.path], YES) encoding:NSUTF8StringEncoding];
    if(nil == results)
    {
        //bail
        goto bail;
    }
    
    //parse results
    // ->format: <file path>: <file types>
    parsedResults = [results componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@":\n"]];
    
    //sanity check
    // ->should be two items in array, <file path> and <file type>
    if(parsedResults.count < 2)
    {
        //bail
        goto bail;
    }
    
    //file type comes second
    // ->also trim whitespace
    self.type = [parsedResults[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
//bail
bail:
    
    return;
}


//get detailed info (which takes a while to generate)
// ->only shown to user if they click 'info' so this method is called in the background
-(void)generateDetailedInfo
{
    //set type
    [self setFileType];
    
    return;
}

//override method
// ->hash
-(NSUInteger)hash
{
    return [self.path hash];
}

//override method
// ->equality check
-(BOOL)isEqual:(id)object
{
    //flag
    BOOL objEqual = NO;
    
    //check self
    if(self == object)
    {
        //match
        objEqual = YES;
        
        //bail
        goto bail;
    }
    
    //check for type
    if(YES != [object isKindOfClass:[File class]])
    {
        //no match
        objEqual = NO;
        
        //bail
        goto bail;
    }
    
    //do check
    if(YES == [((File*)object).path isEqualToString:self.path])
    {
        //happy
        objEqual = YES;
        
        //bail
        goto bail;
    }
    
//bail
bail:
    
    return objEqual;
}

//convert object to JSON string
-(NSString*)toJSON
{
    //json string
    NSString *json = nil;
    
    //attributes
    NSMutableString* attributesJSON = nil;
    
    //init 
    attributesJSON = [NSMutableString string];
    
    //when attributes are nil
    // ->init default string
    if(nil == self.attributes)
    {
        //init
        [attributesJSON appendString:@"\"unknown\""];
    }
    
    //file has attributes
    // ->add each
    else
    {
        //start
        [attributesJSON appendString:@"{"];
        
        //add each attributes
        for(NSString* attribute in self.attributes)
        {
            //skip NSFileExtendedAttributes
            // ->binary format
            if(YES == [attribute isEqualToString:@"NSFileExtendedAttributes"])
            {
                //skip
                continue;
            }
            
            //add
            [attributesJSON appendFormat:@"\"%@\":\"%@\",", attribute, self.attributes[attribute]];
        }
        
        //remove last ','
        if(YES == [attributesJSON hasSuffix:@","])
        {
            //remove
            [attributesJSON deleteCharactersInRange:NSMakeRange([attributesJSON length]-1, 1)];
        }
        
        //end
        [attributesJSON appendString:@"}"];
    }
    
    //init json
    json = [NSString stringWithFormat:@"\"name\": \"%@\", \"path\": \"%@\", \"type\": \"%@\", \"attributes\": %@", self.name, self.path, self.type, attributesJSON];
    
    return json;
}


@end
