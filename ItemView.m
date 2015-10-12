//
//  ItemView.m
//  TaskExplorer
//
//  Created by Patrick Wardle on 5/23/15.
//  Copyright (c) 2015 Objective-See, LLC. All rights reserved.
//

#import "Consts.h"
#import "ItemView.h"
#import "VTButton.h"
#import "kkRowCell.h"
#import "AppDelegate.h"
#import "SearchWindowController.h"
#import "3rdParty/OrderedDictionary.h"

//create customize item view
NSTableCellView* createItemView(NSTableView* tableView, id owner, id item)
{
    //item cell
    NSTableCellView *itemCell = nil;
    
    //sanity check
    if(nil == item)
    {
        //bail
        goto bail;
    }
    //handle logic for flagged items
    // ->but only dylibs, to get special global 'loaded in' views
    if( (YES == [owner isKindOfClass:[FlaggedItems class]]) &&
        (YES == [item isKindOfClass:[Binary class]]) )
    {
        //create & config view
        itemCell = createLoadedItemView(tableView, owner, item);
    }
    
    //handle logic for search results
    // ->dylibs/files/connections have the special global 'loaded in' views
    else if( (YES == [owner isKindOfClass:[SearchWindowController class]]) &&
             (YES != [item isKindOfClass:[Task class]]) )
    {
        //create & config view
        itemCell = createLoadedItemView(tableView, owner, item);
    }
    
    //logic to create task view
    else if(YES == [item isKindOfClass:[Task class]])
    {
        //create & config view
        itemCell = createTaskView(tableView, owner, item);
        
        //set tag
        // ->task pid (allows lookup later)
        ((kkRowCell*)itemCell).tag = [((Task*)item).pid integerValue] + PID_TAG_DELTA;
    }
    
    //logic to create dylib view
    else if(YES == [item isKindOfClass:[Binary class]])
    {
        //create & config view
        itemCell = createDylibView(tableView, owner, item);
    }

    //logic to create file view
    else if(YES == [item isKindOfClass:[File class]])
    {
        //create & config view
        itemCell = createFileView(tableView, owner, item);
    }
    
    //logic to create network view
    else if(YES == [item isKindOfClass:[Connection class]])
    {
        //create & config view
        itemCell = createNetworkView(tableView, owner, item);
    }
    
//bail
bail:
    
    return itemCell;
}

//add a tracking area to a view within the item view
void addTrackingArea(NSTableCellView* itemView, NSUInteger subviewTag, id owner)
{
    //tracking area
    NSTrackingArea* trackingArea = nil;
    
    //alloc/init tracking area
    trackingArea = [[NSTrackingArea alloc] initWithRect:[[itemView viewWithTag:subviewTag] bounds] options:(NSTrackingInVisibleRect | NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways) owner:owner userInfo:@{@"tag":[NSNumber numberWithUnsignedInteger:subviewTag]}];
    
    //add tracking area to subview
    [[itemView viewWithTag:subviewTag] addTrackingArea:trackingArea];

    return;
}

//set code signing image
// ->either signed, unsigned, or unknown
NSImage* getCodeSigningIcon(Binary* binary)
{
    //signature image
    NSImage* codeSignIcon = nil;
    
    //set signature status icon
    if(nil != binary.signingInfo)
    {
        //binary is signed by apple
        if(YES == [binary.signingInfo[KEY_SIGNING_IS_APPLE] boolValue])
        {
            //set
            codeSignIcon = [NSImage imageNamed:@"signedAppleIcon"];
        }
        
        //binary is signed
        else if(STATUS_SUCCESS == [binary.signingInfo[KEY_SIGNATURE_STATUS] integerValue])
        {
            //set
            codeSignIcon = [NSImage imageNamed:@"signed"];
        }
        
        //binary not signed
        else if(errSecCSUnsigned == [binary.signingInfo[KEY_SIGNATURE_STATUS] integerValue])
        {
            //set
            codeSignIcon = [NSImage imageNamed:@"unsigned"];
        }
        
        //unknown
        else
        {
            //set
            codeSignIcon = [NSImage imageNamed:@"unknown"];
        }
    }
    //signing info is nil
    // ->just to unknown
    else
    {
        //set
        codeSignIcon = [NSImage imageNamed:@"unknown"];
    }
    
    return codeSignIcon;
}

//create & customize global dylib/file view
// ->has 'loaded in...' string
NSTableCellView* createLoadedItemView(NSTableView* tableView, id owner, id item)
{
    //item cell
    NSTableCellView* loadedItemCell = nil;
    
    //matching or host tasks
    NSMutableArray* tasks = nil;
    
    //pid or 'loaded in' string
    NSMutableString* loadedIn = nil;
    
    //task's name frame
    CGRect nameFrame = {0};
  
    //get host tasks
    // ->works with dylibs or files
    tasks = [((AppDelegate*)[[NSApplication sharedApplication] delegate]).taskEnumerator loadedIn:item];
    
    //add dylib indicator
    //-> '(dylib, loaded in: ... '
    if(YES == [item isKindOfClass:[Binary class]])
    {
        //init
        loadedIn = [NSMutableString stringWithFormat:@"(dylib, loaded in:"];
    }
    //add file indicator
    //-> '(file, loaded in: ... '
    else if(YES == [item isKindOfClass:[File class]])
    {
        //init
        loadedIn = [NSMutableString stringWithFormat:@"(file, loaded in:"];
    }
    //add connection indicator
    //-> '(connection, in: ... '
    else if(YES == [item isKindOfClass:[Connection class]])
    {
        //init
        loadedIn = [NSMutableString stringWithFormat:@"(connection, in:"];
    }
    
    //add all tasks
    for(Task* task in tasks)
    {
        //append name
        [loadedIn appendFormat:@" %@,", task.binary.name];
    }
        
    //remove last ','
    if(YES == [loadedIn hasSuffix:@","])
    {
        //remove
        [loadedIn deleteCharactersInRange:NSMakeRange([loadedIn length]-1, 1)];
    }
    
    //terminate list/output
    [loadedIn appendString:@")"];
    
    //dylibs
    // ->create cell
    if(YES == [item isKindOfClass:[Binary class]])
    {
        //create
        loadedItemCell = [tableView makeViewWithIdentifier:@"TaskCell" owner:owner];
    }
    //files
    // ->create cell
    else if(YES == [item isKindOfClass:[File class]])
    {
        //create
        loadedItemCell = [tableView makeViewWithIdentifier:@"FileCell" owner:owner];
    }
    //connections
    // ->create cell
    else if(YES == [item isKindOfClass:[Connection class]])
    {
        //create
        loadedItemCell = [tableView makeViewWithIdentifier:@"ConnectionCell" owner:owner];
    }
    
    //sanity check
    if(nil == loadedItemCell)
    {
        //bail
        goto bail;
    }
    
    //brand new cells need tracking areas
    // ->determine if new, by checking default (.xib/IB) value
    if(YES == [loadedItemCell.textField.stringValue isEqualToString:@"Name"])
    {
        //only dylibs have VT button
        if(YES == [item isKindOfClass:[Binary class]])
        {
            //add tracking area
            // ->'vt' button
            addTrackingArea(loadedItemCell, TABLE_ROW_VT_BUTTON, owner);
        }
        
        //add tracking area
        // ->'info' button
        addTrackingArea(loadedItemCell, TABLE_ROW_INFO_BUTTON, owner);
        
        //add tracking area
        // ->'show' button
        addTrackingArea(loadedItemCell, TABLE_ROW_SHOW_BUTTON, owner);
    }
    
    //set icon
    loadedItemCell.imageView.image = [item icon];
    
    //only dylibs have code signing icons
    if(YES == [item isKindOfClass:[Binary class]])
    {
        //set code signing icon
        ((NSImageView*)[loadedItemCell viewWithTag:TABLE_ROW_SIGNATURE_ICON]).image = getCodeSigningIcon(item);
    }

    //default
    // ->(re)set main textfield's color to black
    loadedItemCell.textField.textColor = [NSColor blackColor];
    
    //dylibs/files
    // ->main text is name
    if( (YES == [item isKindOfClass:[Binary class]]) ||
        (YES == [item isKindOfClass:[File class]]) )
    {
        //set name
        [loadedItemCell.textField setStringValue:[item name]];
    }
    //connections
    // ->main text is endpoints string
    else
    {
        //set endpoints string
        [loadedItemCell.textField setStringValue:[item endpoints]];
    }
    
    //get name frame
    nameFrame = loadedItemCell.textField.frame;
    
    //adjust width to fit text
    nameFrame.size.width = [loadedItemCell.textField.stringValue sizeWithAttributes: @{NSFontAttributeName: loadedItemCell.textField.font}].width + 5;
    
    //disable autolayout for name
    loadedItemCell.textField.translatesAutoresizingMaskIntoConstraints = YES;
    
    //update name frame
    // ->should now be exact size of text
    loadedItemCell.textField.frame = nameFrame;
    
    //set host task(s) string
    // ->immediately follows name
    [((NSTextField*)[loadedItemCell viewWithTag:TABLE_ROW_PID_LABEL]) setStringValue:loadedIn];
    
    //dylibs/files
    // ->subtext is path
    if( (YES == [item isKindOfClass:[Binary class]]) ||
        (YES == [item isKindOfClass:[File class]]) )
    {
        //set path
        [[loadedItemCell viewWithTag:TABLE_ROW_SUB_TEXT_TAG] setStringValue:[item path]];
    }
    //connections
    // ->subtext is connection status
    else
    {
        //set details
        // ->TCP socket
        if(nil != ((Connection*)item).state)
        {
            //add state
            [[loadedItemCell viewWithTag:TABLE_ROW_SUB_TEXT_TAG] setStringValue:((Connection*)item).state];
        }
        //set details
        // ->UDP socket
        else if(YES == [((Connection*)item).type isEqualToString:@"SOCK_DGRAM"])
        {
            //bound
            // ->add state
            [[loadedItemCell viewWithTag:TABLE_ROW_SUB_TEXT_TAG] setStringValue:@"bound (UDP) socket"];
        
            //TODO: connected UDP socket?
        }
    }

    //only dylibs have VT button
    if(YES == [item isKindOfClass:[Binary class]])
    {
        //config VT button
        configVTButton(loadedItemCell, owner, item);
    }
    
//bail
bail:
    
    return loadedItemCell;
}

//create & customize Task view
NSTableCellView* createTaskView(NSTableView* tableView, id owner, Task* task)
{
    //item cell
    NSTableCellView* taskCell = nil;
    
    //task's name frame
    CGRect nameFrame = {0};
    
    //string for pid
    NSString* pidString = nil;
    
    //sanity check
    if(nil == task.binary)
    {
        //bail
        goto bail;
    }
    
    //create cell
    taskCell = [tableView makeViewWithIdentifier:@"TaskCell" owner:owner];
    if(nil == taskCell)
    {
        //bail
        goto bail;
    }
    
    //brand new cells need tracking areas
    // ->determine if new, by checking default (.xib/IB) value
    if( (YES == [taskCell.textField.stringValue isEqualToString:@"Task Name"]) ||
        (YES == [taskCell.textField.stringValue isEqualToString:@"Name"]) )
    {
        //add tracking area
        // ->'vt' button
        addTrackingArea(taskCell, TABLE_ROW_VT_BUTTON, owner);

        //add tracking area
        // ->'info' button
        addTrackingArea(taskCell, TABLE_ROW_INFO_BUTTON, owner);
        
        //add tracking area
        // ->'show' button
        addTrackingArea(taskCell, TABLE_ROW_SHOW_BUTTON, owner);
    }
    
    //set icon
    taskCell.imageView.image = [task.binary icon];
    
    //set code signing icon
    ((NSImageView*)[taskCell viewWithTag:TABLE_ROW_SIGNATURE_ICON]).image = getCodeSigningIcon(task.binary);
    
    //default
    // ->(re)set main textfield's color to black
    taskCell.textField.textColor = [NSColor blackColor];
    
    //set main text
    // ->name
    [taskCell.textField setStringValue:task.binary.name];
    
    //get name frame
    nameFrame = taskCell.textField.frame;
    
    //adjust width to fit text
    nameFrame.size.width = [taskCell.textField.stringValue sizeWithAttributes: @{NSFontAttributeName: taskCell.textField.font}].width + 5;
    
    //disable autolayout for name
    taskCell.textField.translatesAutoresizingMaskIntoConstraints = YES;
    
    //update name frame
    // ->should now be exact size of text
    taskCell.textField.frame = nameFrame;
    
    //init pid string
    // ->search mode, show 'task,' to differential between files, etc
    if(YES ==[owner isKindOfClass:[SearchWindowController class]])
    {
        //init
        pidString = [NSString stringWithFormat:@"(task: %@)", task.pid];
    }
    //otherwise
    // ->just set pid
    else
    {
        //init
        pidString = [NSString stringWithFormat:@"(%@)", task.pid];
    }
    
    //set pid
    // ->immediately follows name
    [((NSTextField*)[taskCell viewWithTag:TABLE_ROW_PID_LABEL]) setStringValue:pidString];
    
    //set path
    [[taskCell viewWithTag:TABLE_ROW_SUB_TEXT_TAG] setStringValue:task.binary.path];
    
    //config VT button
    configVTButton(taskCell, owner, task.binary);

//bail
bail:
    
    return taskCell;
}

//create & customize dylib view
NSTableCellView* createDylibView(NSTableView* tableView, id owner, Binary* dylib)
{
    //item cell
    NSTableCellView* dylibCell = nil;

    //create cell
    dylibCell = [tableView makeViewWithIdentifier:@"DylibCell" owner:owner];
    if(nil == dylibCell)
    {
        //bail
        goto bail;
    }
    
    //brand new cells need tracking areas
    // ->determine if new, by checking default (.xib/IB) value
    if(YES == [dylibCell.textField.stringValue isEqualToString:@"Dylib Name"])
    {
        //add tracking area
        // ->'vt' button
        addTrackingArea(dylibCell, TABLE_ROW_VT_BUTTON, owner);
        
        //add tracking area
        // ->'info' button
        addTrackingArea(dylibCell, TABLE_ROW_INFO_BUTTON, owner);
        
        //add tracking area
        // ->'show' button
        addTrackingArea(dylibCell, TABLE_ROW_SHOW_BUTTON, owner);
    }
    
    //set code signing icon
    ((NSImageView*)[dylibCell viewWithTag:TABLE_ROW_SIGNATURE_ICON]).image = getCodeSigningIcon(dylib);
    
    //default
    // ->(re)set main textfield's color to black
    dylibCell.textField.textColor = [NSColor blackColor];
    
    //set main text
    // ->name
    [dylibCell.textField setStringValue:dylib.name];
    
    //set path
    [[dylibCell viewWithTag:TABLE_ROW_SUB_TEXT_TAG] setStringValue:dylib.path];
    
    //config VT button
    configVTButton(dylibCell, owner, dylib);
    
//bail
bail:
    
    return dylibCell;
}


//create & customize file view
NSTableCellView* createFileView(NSTableView* tableView, id owner, File* file)
{
    //item cell
    NSTableCellView* fileCell = nil;
    
    //sanity check
    if(nil == file)
    {
        //bail
        goto bail;
    }
    
    //create cell
    fileCell = [tableView makeViewWithIdentifier:@"FileCell" owner:owner];
    if(nil == fileCell)
    {
        //bail
        goto bail;
    }
    
    //brand new cells need tracking areas
    // ->determine if new, by checking default (.xib/IB) value
    if(YES == [fileCell.textField.stringValue isEqualToString:@"Dylib Name"])
    {
        //add tracking area
        // ->'info' button
        addTrackingArea(fileCell, TABLE_ROW_INFO_BUTTON, owner);
        
        //add tracking area
        // ->'show' button
        addTrackingArea(fileCell, TABLE_ROW_SHOW_BUTTON, owner);
    }
    
    //default
    // ->(re)set main textfield's color to black
    fileCell.textField.textColor = [NSColor blackColor];
    
    //set main text
    // ->name
    [fileCell.textField setStringValue:file.name];
    
    //set path
    [[fileCell viewWithTag:TABLE_ROW_SUB_TEXT_TAG] setStringValue:file.path];
    
//bail
bail:
    
    return fileCell;
}

//create & customize networking view
NSTableCellView* createNetworkView(NSTableView* tableView, id owner, Connection* connection)
{
    //item cell
    NSTableCellView* connectionCell = nil;
    
    //connection details
    NSMutableString* details = nil;
    
    //alloc string for details
    details = [NSMutableString string];
    
    //create cell
    connectionCell = [tableView makeViewWithIdentifier:@"NetworkCell" owner:owner];
    if(nil == connectionCell)
    {
        //bail
        goto bail;
    }
    
    //set icon
    connectionCell.imageView.image = connection.icon;
    
    //default
    // ->(re)set main textfield's color to black
    connectionCell.textField.textColor = [NSColor blackColor];
    
    //set main text
    // ->connection endpoints
    [connectionCell.textField setStringValue:connection.endpoints];
    
    //set details
    // ->TCP socket
    if(nil != connection.state)
    {
        //add state
        [details appendString:connection.state];
    }
    //set details
    // ->UDP socket
    else if(YES == [connection.type isEqualToString:@"SOCK_DGRAM"])
    {
        //bound
        // ->add state
        [details appendString:@"bound (UDP) socket"];
        
        //TODO: connected UDP socket?
    }
    
    //set details
    [[connectionCell viewWithTag:TABLE_ROW_SUB_TEXT_TAG] setStringValue:details];
    
//bail
bail:
    
    return connectionCell;
}


//configure the VT button
// ->also set's binary name to red if known malware
void configVTButton(NSTableCellView *itemCell, id owner, Binary* binary)
{
    //virus total button
    // ->for File objects only...
    VTButton* vtButton;
    
    //paragraph style
    NSMutableParagraphStyle *paragraphStyle = nil;
    
    //attribute dictionary
    NSMutableDictionary *stringAttributes = nil;
    
    //VT detection ratio as string
    NSString* vtDetectionRatio = nil;

    //grab virus total button
    vtButton = [itemCell viewWithTag:TABLE_ROW_VT_BUTTON];
   
    //configure/show VT info
    // ->only if 'disable' preference not set
    //if(YES != ((AppDelegate*)[[NSApplication sharedApplication] delegate]).prefsWindowController.disableVTQueries)
    //{
        //set button delegate
        vtButton.delegate = owner;
        
        //save file obj
        vtButton.binary = binary;
    
        //check if have vt results
        if(nil != binary.vtInfo)
        {
            //set font
            [vtButton setFont:[NSFont fontWithName:@"Menlo-Bold" size:12]];
            
            //enable
            vtButton.enabled = YES;
            
            //got VT results
            // ->check 'permalink' to determine if file is known to VT
            //   then, show ratio and set to red if file is flagged
            if(nil != binary.vtInfo[VT_RESULTS_URL])
            {
                //alloc paragraph style
                paragraphStyle = [[NSMutableParagraphStyle alloc] init];
                
                //center the text
                [paragraphStyle setAlignment:NSCenterTextAlignment];
                
                //alloc attributes dictionary
                stringAttributes = [NSMutableDictionary dictionary];
                
                //set underlined attribute
                stringAttributes[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
                
                //set alignment (center)
                stringAttributes[NSParagraphStyleAttributeName] = paragraphStyle;
                
                //set font
                stringAttributes[NSFontAttributeName] = [NSFont fontWithName:@"Menlo-Bold" size:12];
                
                //compute detection ratio
                vtDetectionRatio = [NSString stringWithFormat:@"%lu/%lu", (unsigned long)[binary.vtInfo[VT_RESULTS_POSITIVES] unsignedIntegerValue], (unsigned long)[binary.vtInfo[VT_RESULTS_TOTAL] unsignedIntegerValue]];
                
                //known 'good' files (0 positivies)
                if(0 == [binary.vtInfo[VT_RESULTS_POSITIVES] unsignedIntegerValue])
                {
                    //(re)set title black
                    itemCell.textField.textColor = [NSColor blackColor];
                    
                    //set color (black)
                    stringAttributes[NSForegroundColorAttributeName] = [NSColor blackColor];
                    
                    //set string (vt ratio), with attributes
                    [vtButton setAttributedTitle:[[NSAttributedString alloc] initWithString:vtDetectionRatio attributes:stringAttributes]];
                    
                    //set color (gray)
                    stringAttributes[NSForegroundColorAttributeName] = [NSColor grayColor];
                    
                    //set selected text color
                    [vtButton setAttributedAlternateTitle:[[NSAttributedString alloc] initWithString:vtDetectionRatio attributes:stringAttributes]];
                }
                //files flagged by VT
                // ->set name and detection to red
                else
                {
                    //set title red
                    itemCell.textField.textColor = [NSColor redColor];
                    
                    //set color (red)
                    stringAttributes[NSForegroundColorAttributeName] = [NSColor redColor];
                    
                    //set string (vt ratio), with attributes
                    [vtButton setAttributedTitle:[[NSAttributedString alloc] initWithString:vtDetectionRatio attributes:stringAttributes]];
                    
                    //set selected text color
                    [vtButton setAttributedAlternateTitle:[[NSAttributedString alloc] initWithString:vtDetectionRatio attributes:stringAttributes]];
                    
                }
                
                //enable
                [vtButton setEnabled:YES];
            }
            
            //file is not known
            // ->reset title to '?'
            else
            {
                //set title
                [vtButton setTitle:@"?"];
            }
        }
        
        //no VT results (e.g. unknown file)
        else
        {
            //set font
            [vtButton setFont:[NSFont fontWithName:@"Menlo-Bold" size:8]];
            
            //set title
            [vtButton setTitle:@"▪ ▪ ▪"];
            
            //disable
            vtButton.enabled = NO;
        }
        
        //show virus total button
        vtButton.hidden = NO;
        
        //show virus total label
        //[[itemCell viewWithTag:TABLE_ROW_VT_BUTTON+1] setHidden:NO];
        
    //}//show VT info (pref not disabled)
    
    /*
    //hide VT info
    else
    {
        //hide virus total button
        vtButton.hidden = YES;
        
        //hide virus total button label
        [[itemCell viewWithTag:TABLE_ROW_VT_BUTTON+1] setHidden:YES];
    }
    */
    
    return;
}





