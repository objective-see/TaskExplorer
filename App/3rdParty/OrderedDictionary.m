//
//  OrderedDictionary.m
//  OrderedDictionary
//
//  Created by Matt Gallagher on 19/12/08.
//  Copyright 2008 Matt Gallagher. All rights reserved.
//
//  This software is provided 'as-is', without any express or implied
//  warranty. In no event will the authors be held liable for any damages
//  arising from the use of this software. Permission is granted to anyone to
//  use this software for any purpose, including commercial applications, and to
//  alter it and redistribute it freely, subject to the following restrictions:
//
//  1. The origin of this software must not be misrepresented; you must not
//     claim that you wrote the original software. If you use this software
//     in a product, an acknowledgment in the product documentation would be
//     appreciated but is not required.
//  2. Altered source versions must be plainly marked as such, and must not be
//     misrepresented as being the original software.
//  3. This notice may not be removed or altered from any source
//     distribution.
//

#import "Consts.h"
#import "OrderedDictionary.h"


NSString *DescriptionForObject(NSObject *object, id locale, NSUInteger indent)
{
	NSString *objectString;
	if ([object isKindOfClass:[NSString class]])
	{
		objectString = (NSString *)object;
	}
	else if ([object respondsToSelector:@selector(descriptionWithLocale:indent:)])
	{
		objectString = [(NSDictionary *)object descriptionWithLocale:locale indent:indent];
	}
	else if ([object respondsToSelector:@selector(descriptionWithLocale:)])
	{
		objectString = [(NSSet *)object descriptionWithLocale:locale];
	}
	else
	{
		objectString = [object description];
	}
	return objectString;
}

@implementation OrderedDictionary

-(id)init
{
    self = [super init];
    if (self != nil)
    {
        dictionary = [NSMutableDictionary dictionary];
        array = [NSMutableArray array];
    }
    return self;
    
}

-(id)copy
{
	return [self mutableCopy];
}

-(void)setObject:(id)anObject forKey:(id)aKey
{
	if(![dictionary objectForKey:aKey])
	{
        //
		[array addObject:aKey];
	}
	[dictionary setObject:anObject forKey:aKey];
}

-(void)removeObjectForKey:(id)aKey
{
	[dictionary removeObjectForKey:aKey];
	[array removeObject:aKey];
}

- (NSUInteger)count
{
	return [dictionary count];
}

-(id)objectForKey:(id)aKey
{
	return [dictionary objectForKey:aKey];
}

-(NSEnumerator *)keyEnumerator
{
	return [array objectEnumerator];
}


-(void)insertObject:(id)anObject forKey:(id)aKey atIndex:(NSUInteger)anIndex
{
	if([dictionary objectForKey:aKey])
	{
		[self removeObjectForKey:aKey];
	}
	[array insertObject:aKey atIndex:anIndex];
	[dictionary setObject:anObject forKey:aKey];
}

-(id)keyAtIndex:(NSUInteger)anIndex
{
    //object
    id item = nil;
    
    if((nil == array) ||
       (anIndex >= array.count))
    {
        //bail
        goto bail;
    }
    
    //extract item
    item = [array objectAtIndex:anIndex];
    
//bail
bail:
    
    return item;
}

//given a key
// ->return its index
-(NSUInteger)indexOfKey:(id)aKey
{
    return [array indexOfObject:aKey];
}

//sort
// ->by pid, name, etc
-(void)sort:(NSUInteger)sortBy
{
    //task sorted by name
    NSArray* sortedTasks = nil;
    
    //sort by pid
    if(SORT_BY_PID == sortBy)
    {
        [array sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
            return [obj1 compare:obj2];
        }];
    }
    //sort by name
    else if(SORT_BY_NAME == sortBy)
    {
        //get array of tasks, sorted by binary name
        // ->invokes Task class's compare method
        sortedTasks = [[dictionary allValues] sortedArrayUsingSelector:@selector(compare:)];
        
        //extract sorted pids into array
        array = [[sortedTasks valueForKey:@"pid"] mutableCopy];
    }
    
    return;
}

@end
