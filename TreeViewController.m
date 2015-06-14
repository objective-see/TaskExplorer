    /*-
 * Copyright 2009, Mac OS X Internals. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification, are
 * permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice, this list of
 * conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice, this list
 * of conditions and the following disclaimer in the documentation and/or other materials
 * provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY Mac OS X Internals ``AS IS'' AND ANY EXPRESS OR IMPLIED
 * WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
 * FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL Mac OS X Internals OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
 * ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 * ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 * The views and conclusions contained in the software and documentation are those of the
 * authors and should not be interpreted as representing official policies, either expressed
 * or implied, of Mac OS X Internals.
 */

#import "Task.h"
#import "AppDelegate.h"
#import "TreeViewController.h"
#import "ItemView.h"
#import "KKRow.h"


@implementation TreeViewController


@synthesize itemView;

-(void)awakeFromNib
{
    //auto-expand everything
	//
    [itemView expandItem:nil expandChildren:YES];

    //TODO: do this in IB?
	[itemView setTarget:self];
	//[outlineView setDoubleAction:@selector(onDoubleAction:)];
}

//reload + row selection intact
-(void)refresh
{
    //TODO: add logic to ensure selected row stays selected
    [self.itemView reloadData];
    
    return;
}

/*
-(void)showProcessInfo
{
	NSArray *processes = [arrayController selectedObjects];
	if ([processes count] > 0) {
		ProcessInfo *pInfo = [processes objectAtIndex:0];
		if (pInfo.processState != -1 ) {
			TaskInfoController *taskInfoController = [TaskInfoController taskInfoController:pInfo];
			[taskInfoController showInfo];
		}
	}
}
*/

/*
-(void)onDoubleAction:(NSEvent*)theEvent;
{
	[self showProcessInfo];
}

-(NSArray*)sortDescriptors
{
	return [NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]];
}

-(IBAction)menuItemAction:(id)sender
{
	NSInteger clickedRow = [sender tag];
}

-(TasksInfoManager*)tasksInfoManager
{
	return [TasksInfoManager instance];
}

-(NSString*)selectedAppName
{
	NSString *result;
	NSArray *processes = [arrayController selectedObjects];

	if ([processes count] > 0) {
		ProcessInfo *pInfo = [processes objectAtIndex:0];
		result = pInfo.name;
	}

	return result;
}
*/

/*
-(void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(NSCell *)cell forTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
    //Task* *task = [item representedObject];
    Task* task = (Task*)item;
    
    //item cell
    NSTableCellView *itemCell = nil;
    
    
    itemCell = (NSTableCellView*)cell;
    
    //set main text
    // ->name
    [itemCell.textField setStringValue:task.path];


    
    
    //[imageAndTextCell setImage:pInfo.icon_small];

    
    /*
	if ([[Settings instance] highlightProcesses] == YES) {
		if (pInfo.processState == 0) { // process
			[(NSTextFieldCell*)cell setTextColor:[NSColor blackColor]];
		}
		else if (pInfo.processState == 1) { // new process
			[(NSTextFieldCell*)cell setTextColor:[NSColor greenColor]];
		}
		else if (pInfo.processState == -1) { // ended process
			[(NSTextFieldCell*)cell setTextColor:[NSColor redColor]];
		}
	}

    
    return;
}
*/

-(NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
    //tasks
    OrderedDictionary* tasks = nil;
    
    //grab tasks
    tasks = ((AppDelegate*)[[NSApplication sharedApplication] delegate]).taskEnumerator.tasks;
    
    //NSLog(@"task: %@", ((Task*)item).path);
    
    //count
    NSUInteger children = 0;
    
    //when item is nil
    // ->count is all children
    if(nil == item)
    {
        //all
        children = ((Task*)[tasks objectForKey:@0]).children.count;
    }
    //otherwise
    // ->give number of item's kids
    else
    {
        //NSLog(@"task: %@", ((Task*)item).path);
        
        //
        children = [((Task*)item).children count];
        
        //NSLog(@"..has %lu kids", (unsigned long)children);
    }
    
    
    
    
    return children;
}

-(BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
    //only no for leafs
    // ->items w/o kids
    if( (nil != item) &&
       (0 == [[item children] count]) )
    {
        return NO;
    }
    else
    {
        return YES;
    }
    //return !item ? YES : [[item children] count] != 0;
}

//return child
-(id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
    //tasks
    OrderedDictionary* tasks = nil;
    
    //task
    Task* task = nil;
    
    //grab tasks
    tasks = ((AppDelegate*)[[NSApplication sharedApplication] delegate]).taskEnumerator.tasks;
    
    
    //get task object
    // ->by index to get key, then by key
    //task = self.tasks[[self.tasks keyAtIndex:index]];
    
    task = [tasks objectForKey:@0];
    
    //NSLog(@"root item: %@", self.tasks[[self.tasks objectForKey:@1]]);
    
    //root item
    // ->child at index
    if(nil == item)
    {
        return task;//[self.tasks objectForKey:@1];
    }
    
    //other items
    // ->return *their* child!
    else
    {
        return [tasks objectForKey:[(Task*)item children][index]];
    }
    
}

//table delegate method
// ->return cell for row
-(NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
    return createItemView(outlineView, self, (Task*)item);
}

//automatically invoked
// ->create custom (sub-classed) NSTableRowView
-(NSTableRowView *)outlineView:(NSOutlineView *)outlineView rowViewForItem:(id)item
{
    //row view
    KKRow* rowView = nil;
    
    //row ID
    static NSString* const kRowIdentifier = @"RowView";
    
    //try grab existing row view
    rowView = [outlineView makeViewWithIdentifier:kRowIdentifier owner:self];
    
    //make new if needed
    if(nil == rowView)
    {
        //create new
        // ->size doesn't matter
        rowView = [[KKRow alloc] initWithFrame:NSZeroRect];
        
        //set row ID
        rowView.identifier = kRowIdentifier;
    }
    
    return rowView;
}


/*
//person object
- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
    //NSLog(@"column name: %@", [tableColumn identifier]);
    
    //    if ([[tableColumn identifier] isEqualToString:@"name"])
    return [item path];
    
    //    return @"Nobody's Here!";
}
*/



/*
- (NSString *)outlineView:(NSOutlineView *)outlineView toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect tableColumn:(NSTableColumn *)tc item:(id)item mouseLocation:(NSPoint)mouseLocation
{
    ProcessInfo *pInfo = [item representedObject];
	NSNumber *id_table;
	NSString *id_column;
	id       *cell_data;
    
    NSString *descr = pInfo.description;
    
	return (descr);
}
*/

@end
