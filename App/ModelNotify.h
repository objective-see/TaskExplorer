//
//  ModelNotify.h
//  TaskExplorer (app)
//
//  Created by Patrick Wardle on 9/12/26.
//  Copyright (c) 2026 Objective-See. All rights reserved.
//
//  note: the (objective-c) model notifies the (swift) UI of changes via these notifications
//        ...all are posted on the main queue

#ifndef ModelNotify_h
#define ModelNotify_h

#import <Foundation/Foundation.h>

@class Task;
@class Binary;

/* NOTIFICATIONS */

//set of tasks changed (added/removed)
extern NSNotificationName const TETasksChangedNotification;

//a task changed (signing info, etc); object: Task
extern NSNotificationName const TETaskChangedNotification;

//a task's items (dylibs/files/connections) changed; object: Task, userInfo[@"view"]: DYLIBS_VIEW, etc
extern NSNotificationName const TEItemsChangedNotification;

//a binary changed (e.g. VT results); object: Binary
extern NSNotificationName const TEBinaryChangedNotification;

//status (e.g. "starting extension...") changed; object: NSString (or nil to clear)
extern NSNotificationName const TEStatusChangedNotification;

//enumeration state changed
extern NSNotificationName const TEEnumerationStateChangedNotification;

/* FUNCTIONS */

//tasks changed
void notifyTasksChanged(void);

//task changed
void notifyTaskChanged(Task* task);

//task's items changed
void notifyItemsChanged(Task* task, NSUInteger view);

//binary changed
void notifyBinaryChanged(Binary* binary);

//status changed
void notifyStatus(NSString* status);

//enumeration state changed
void notifyEnumerationState(void);

#endif /* ModelNotify_h */
