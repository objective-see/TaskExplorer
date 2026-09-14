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

#import <sys/stat.h>
#import <pwd.h>

@implementation File

@synthesize type;

//init method
-(id)initWithParams:(NSDictionary*)params
{
    //super
    // saves path, etc
    self = [super initWithParams:params];
    if(self)
    {
        //extract name
        self.name = [[self.path lastPathComponent] stringByDeletingPathExtension];

        //type (file, socket, directory, ...; from the extension)
        self.type = params[KEY_FILE_TYPE] ?: FILE_TYPE_UNKNOWN;

        //note: icon & attributes are generated lazily (see below)
        // ->files are created (in bulk) on the enumeration thread, so init must be cheap & never block
    }
    
    return self;
}

//icon (lazy)
// ->generated on first access (i.e. when shown in the UI)
-(NSImage*)icon
{
    //icon
    NSImage* icon = [super icon];
    if(nil == icon)
    {
        //generate
        icon = [[NSWorkspace sharedWorkspace] iconForFile:self.path];

        //save
        [super setIcon:icon];
    }

    return icon;
}

//attributes (lazy)
// ->via lstat() (not NSFileManager, which also reads xattrs, and can block for a long time on some volumes)
-(NSDictionary*)attributes
{
    //attributes
    NSMutableDictionary* attributes = nil;

    //file info
    struct stat fileInfo = {0};

    //owner
    struct passwd* owner = NULL;

    //generated?
    if(nil != [super attributes])
    {
        //bail
        goto bail;
    }

    //protected?
    if(YES == [self isProtected])
    {
        //bail
        goto bail;
    }

    //stat
    if(0 != lstat(self.path.fileSystemRepresentation, &fileInfo))
    {
        //bail
        goto bail;
    }

    //init
    attributes = [NSMutableDictionary dictionary];

    //size
    attributes[NSFileSize] = @(fileInfo.st_size);

    //modification date
    attributes[NSFileModificationDate] = [NSDate dateWithTimeIntervalSince1970:fileInfo.st_mtimespec.tv_sec];

    //creation date
    attributes[NSFileCreationDate] = [NSDate dateWithTimeIntervalSince1970:fileInfo.st_birthtimespec.tv_sec];

    //owner (id)
    attributes[NSFileOwnerAccountID] = @(fileInfo.st_uid);

    //owner (name)
    owner = getpwuid(fileInfo.st_uid);
    if(NULL != owner)
    {
        //set
        attributes[NSFileOwnerAccountName] = [NSString stringWithUTF8String:owner->pw_name];
    }

    //permissions
    attributes[NSFilePosixPermissions] = @(fileInfo.st_mode & 07777);

    //type
    switch(fileInfo.st_mode & S_IFMT)
    {
        case S_IFREG: attributes[NSFileType] = NSFileTypeRegular; break;
        case S_IFDIR: attributes[NSFileType] = NSFileTypeDirectory; break;
        case S_IFLNK: attributes[NSFileType] = NSFileTypeSymbolicLink; break;
        case S_IFSOCK: attributes[NSFileType] = NSFileTypeSocket; break;
        case S_IFCHR: attributes[NSFileType] = NSFileTypeCharacterSpecial; break;
        case S_IFBLK: attributes[NSFileType] = NSFileTypeBlockSpecial; break;
        default: attributes[NSFileType] = NSFileTypeUnknown; break;
    }

    //save
    [super setAttributes:attributes];

bail:

    return [super attributes];
}




//override method
// hash the file
-(NSUInteger)hash
{
    return [self.path hash];
}

//override method
// file equality check (path)
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
    
bail:
    
    return objEqual;
}

//check if file is protected
// on mojave+, need to avoid prompts
-(BOOL)isProtected
{
    //flag
    BOOL protected = NO;
    
    //skip any files in (privacy) protected directories
    // as otherwise we will generate a privacy prompt (on Mojave)
    for(NSString* directory in protectedDirectories)
    {
        //check
        if(YES == [self.path hasPrefix:directory])
        {
            //set flag
            protected = YES;
            
            //done
            break;
        }
    }
    
    return protected;
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
    // init default string, 'unknown'
    if(nil == self.attributes)
    {
        //init
        [attributesJSON appendString:@"\"unknown\""];
    }
    
    //file has attributes
    // add each one to json
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
            [attributesJSON appendFormat:@"\"%@\":\"%@\",", jsonEscape([attribute description]), jsonEscape([self.attributes[attribute] description])];
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
    json = [NSString stringWithFormat:@"\"name\": \"%@\", \"path\": \"%@\", \"type\": \"%@\", \"attributes\": %@", jsonEscape(self.name), jsonEscape(self.path), jsonEscape(self.type), attributesJSON];
    
    return json;
}

@end
