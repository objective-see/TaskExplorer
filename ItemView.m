//
//  ItemView.m
//  TaskExplorer
//
//  Created by Patrick Wardle on 5/23/15.
//  Copyright (c) 2015 Lucas Derraugh. All rights reserved.
//

#import "Consts.h"
#import "ItemView.h"
#import "VTButton.h"
#import "AppDelegate.h"
#import "kkRowCell.h"
#import "3rdParty/OrderedDictionary.h"

//create customize item view
NSTableCellView* createItemView(NSTableView* tableView, id owner, id item)
{
    //item cell
    NSTableCellView *itemCell = nil;
    
    //sanity chec
    if(nil == item)
    {
        //bail
        goto bail;
    }
    
    //logic to create task view
    if(YES == [item isKindOfClass:[Task class]])
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

//create & customize Task view
NSTableCellView* createTaskView(NSTableView* tableView, id owner, Task* task)
{
    //item cell
    NSTableCellView* taskCell = nil;
    
    //task's name frame
    CGRect nameFrame = {0};
    
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
    if(YES == [taskCell.textField.stringValue isEqualToString:@"Task Name"])
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
    
    //set pid
    // ->immediately follows name
    [((NSTextField*)[taskCell viewWithTag:TABLE_ROW_PID_LABEL]) setStringValue:[NSString stringWithFormat:@"(%@)", task.pid]];
    
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
    
    
    //[itemCell viewWithTag:TABLE_ROW_VT_BUTTON];
    
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





