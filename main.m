//
//  main.m
//  TaskExplorer
//
//  Created by Patrick Wardle
//  Copyright (c) 2015 Objective-See. All rights reserved.
//

#import "Consts.h"
#import "Utilities.h"

#import <Cocoa/Cocoa.h>


//main interface
// ->contains extra logic to handle app translocation
int main(int argc, char *argv[])
{
    //return
    int status = -1;
    
    //untranslocated URL
    NSURL* untranslocatedURL = nil;
    
    //get original url
    untranslocatedURL = getUnTranslocatedURL();
    if(nil != untranslocatedURL)
    {
        //remove quarantine attributes of original
        execTask(XATTR, @[@"-cr", untranslocatedURL.path]);
        
        //relaunch
        // ->use 'open' since allows two instances of app to be run
        execTask(OPEN, @[@"-n", @"-a", untranslocatedURL.path]);
    
        //happy
        status = 0;
            
        //bail
        goto bail;
    }
    
    //app isn't translocated
    // ->can just run app as is
    else
    {
        //invoke app's main
        status =  NSApplicationMain(argc, (const char **)argv);
    }
    
//bail
bail:
    
    return status;
}

