//
//  ItemBase.m
//  TaskExplorer

#import "Consts.h"
#import "ItemBase.h"

#define kErrFormat @"%@ not implemented in subclass %@"
#define kExceptName @"KK Item"



@implementation ItemBase

@synthesize name;
@synthesize path;
//@synthesize isTrusted;
@synthesize attributes;

//init method
-(id)initWithParams:(NSDictionary*)params
{
    //super
    self = [super init];
    if(nil != self)
    {
        //extract/save name
        self.name = params[KEY_RESULT_NAME];
        
        //extract/save path
        self.path = params[KEY_RESULT_PATH];
    }
    
    return self;
}

//return a path that can be opened in Finder.app
-(NSString*)pathForFinder
{
    return self.path;
}

//return


/* OPTIONAL METHODS */


/* REQUIRED METHODS */

//stubs for inherited methods
// throw exceptions as they should be implemented in sub-classes

//convert object to JSON string
-(NSString*)toJSON
{
    @throw [NSException exceptionWithName:kExceptName
                                   reason:[NSString stringWithFormat:kErrFormat, NSStringFromSelector(_cmd), [self class]]
                                 userInfo:nil];
    return nil;
}

@end
