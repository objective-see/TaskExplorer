//
//  Consts.h
//  TaskExplorer
//
//  Created by Patrick Wardle on 2/4/15.
//  Copyright (c) 2015 Objective-See. All rights reserved.
//

#ifndef TE_Consts_h
#define TE_Consts_h

/* BUNDLE / SIGNING */

//app bundle id (c string, for os_log)
#define BUNDLE_ID "com.objective-see.taskexplorer"

//app bundle id
#define APP_ID @"com.objective-see.taskexplorer"

//system extension bundle id
#define EXT_BUNDLE_ID @"com.objective-see.taskexplorer.extension"

//xpc mach service (hosted by extension)
// note: for endpoint security extensions, sysextd/launchd registers "<team id>.<extension bundle id>.xpc"
#define EXT_MACH_SERVICE @"VBG97UB4TA.com.objective-see.taskexplorer.extension.xpc"

//team id
#define TEAM_ID @"VBG97UB4TA"

//signing auth
#define SIGNING_AUTH @"Developer ID Application: Objective-See, LLC (VBG97UB4TA)"

//code signing flags (cs_blobs.h)
#define CS_VALID 0x00000001
#define CS_ADHOC 0x00000002
#define CS_RUNTIME 0x00010000

//code signing flag (platform binary)
#define CS_PLATFORM_BINARY 0x04000000

/* EXTENSION */

//(de)activate extension
#define ACTION_DEACTIVATE 0
#define ACTION_ACTIVATE 1

//network (re)enumeration interval (seconds)
#define NETWORK_REFRESH_INTERVAL 5

//system settings: extensions
#define URL_SYSTEM_SETTINGS_EXTENSIONS @"x-apple.systempreferences:com.apple.LoginItems-Settings.extension"

//system settings: full disk access
#define URL_SYSTEM_SETTINGS_FDA @"x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

/* XPC KEYS: PROCESS */

//pid
#define KEY_PROCESS_ID @"pid"

//parent pid
#define KEY_PROCESS_PPID @"ppid"

//responsible pid
#define KEY_PROCESS_RPID @"rpid"

//uid
#define KEY_PROCESS_UID @"uid"

//path
#define KEY_PROCESS_PATH @"path"

//arguments
#define KEY_PROCESS_ARGS @"arguments"

//start time
#define KEY_PROCESS_START @"startTime"

//audit token (NSData)
#define KEY_PROCESS_AUDIT_TOKEN @"auditToken"

//code signing flags (from ES)
#define KEY_PROCESS_CS_FLAGS @"csFlags"

//signing id (from ES)
#define KEY_PROCESS_SIGNING_ID @"signingID"

//team id (from ES)
#define KEY_PROCESS_TEAM_ID @"teamID"

//platform binary (from ES)
#define KEY_PROCESS_PLATFORM_BINARY @"platformBinary"

//cd hash (from ES)
#define KEY_PROCESS_CDHASH @"cdHash"

//exit status (from ES)
#define KEY_PROCESS_EXIT_STATUS @"exitStatus"

/* XPC KEYS: DYLIB (MMAP) */

//dylib path
#define KEY_DYLIB_PATH @"dylib"

/* XPC KEYS: CONNECTION */

//connection uuid (nstat)
#define KEY_CONNECTION_UUID @"uuid"

//interface
#define KEY_INTERFACE @"interface"

//provider (TCP/UDP)
#define KEY_PROVIDER @"provider"

//bytes up
#define KEY_BYTES_UP @"bytesUp"

//bytes down
#define KEY_BYTES_DOWN @"bytesDown"


//not first run
#define NOT_FIRST_TIME @"notFirstTime"

//button text, start scan
#define START_SCAN @"Start Scan"

//button text, stop scan
#define STOP_SCAN @"Stop Scan"

//status msg
#define SCAN_MSG_STARTED @"scanning started"

//status msg
#define SCAN_MSG_STOPPED @"scan stopped"

//status msg
#define SCAN_MSG_COMPLETE @"scan complete"

//success
#define STATUS_SUCCESS 0

//user name
#define USER_NAME @"userName"

//user (home) directory
#define USER_DIRECTORY @"userDirectory"

//signers
enum Signer{None, Apple, AppStore, DevID, AdHoc};

//signature status
#define KEY_SIGNATURE_STATUS @"signatureStatus"

//signer
#define KEY_SIGNATURE_SIGNER @"signatureSigner"

//signing auths
#define KEY_SIGNATURE_AUTHORITIES @"signatureAuthorities"

//code signing id
#define KEY_SIGNATURE_IDENTIFIER @"signatureIdentifier"

//entitlements
#define KEY_SIGNATURE_ENTITLEMENTS @"signatureEntitlements"

//team id
#define KEY_SIGNATURE_TEAM_ID @"signatureTeamID"

//code directory hashes (hex strings)
#define KEY_SIGNATURE_CDHASH_SHA1 @"signatureCDHashSHA1"
#define KEY_SIGNATURE_CDHASH_SHA256 @"signatureCDHashSHA256"

//OS version x
#define OS_MAJOR_VERSION_X 10

//OS minor version lion
#define OS_MINOR_VERSION_LION 8

//OS minor version yosemite
#define OS_MINOR_VERSION_YOSEMITE 10

//OS minor version el capitan
#define OS_MINOR_VERSION_EL_CAPITAN 11

//OS minor version mojave
#define OS_MINOR_VERSION_MOJAVE 14

//executable path
#define EXECUTABLE_PATH @"@executable_path"

//loader path
#define LOADER_PATH @"@loader_path"

//rpath
#define RUN_SEARCH_PATH @"@rpath"

//path to file

//path to xattr
#define XATTR @"/usr/bin/xattr"

//path to open
#define OPEN @"/usr/bin/open"

//key for stdout output
#define STDOUT @"stdOutput"

//key for stderr output
#define STDERR @"stdError"

//key for exit code
#define EXIT_CODE @"exitCode"

//hash key, SHA1
#define KEY_HASH_SHA1 @"sha1"

//hash key, MD5
#define KEY_HASH_MD5 @"md5"

//hash (sha256)
#define KEY_HASH_SHA256 @"sha256"

//path to system profiler
#define SYSTEM_PROFILER @"/usr/sbin/system_profiler"

//dyld_ key for launch items
#define LAUNCH_ITEM_DYLD_KEY @"EnvironmentVariables"

//dyld_ key for applications
#define APPLICATION_DYLD_KEY @"LSEnvironment"

//path to window server
#define WINDOW_SERVER @"/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/Resources/WindowServer"

//menu

//tag for prefs menu item
#define PREF_MENU_ITEM_TAG 1

//main window

//space for File's button in time table (w/ VT info)
#define TABLE_BUTTONS_FILE 225

//space for Extension's button in time table
#define TABLE_BUTTONS_EXTENTION 135


//refresh button
#define REFRESH_BUTTON_TAG 10001

//pref button
#define SEARCH_BUTTON_TAG 10002

//logo button
#define SAVE_BUTTON_TAG 10003

//logo button
#define LOGO_BUTTON_TAG 10004

//flagged items button
#define FLAGGED_BUTTON_TAG 10005

//category table


//id (tag) for detailed text in category table
#define TABLE_ROW_NAME_TAG 100

//id (tag) for detailed text in category table
#define TABLE_ROW_SUB_TEXT_TAG 101

//id (tag) for total's msg
#define TABLE_ROW_TOTAL_TAG 102


//item table

//id (tag) for signed icon
#define TABLE_ROW_SIGNATURE_ICON 100

//id (tag) for path
#define TABLE_ROW_PATH_LABEL 101


//id (tag) for 'virus total' button
#define TABLE_ROW_VT_BUTTON 103

//id (tag) for 'info' button
#define TABLE_ROW_INFO_BUTTON 105

//id (tag) for 'show' button
#define TABLE_ROW_SHOW_BUTTON 107

//ellipis
// ->for long paths...
#define ELLIPIS @"..."

//known file hashes
#define WHITE_LISTED_FILES @"whitelistedFiles"

//known commands
#define WHITE_LISTED_COMMANDS @"whitelistedCommands"

//known extension hashes
#define WHITE_LISTED_EXTENSIONS @"whitelistedExtensions"

//scanner option key
// ->filter apple signed/known items
#define KEY_SCANNER_FILTER @"filterItems"

//kernel
#define KERNEL_PATH @"/System/Library/Kernels/kernel"

//

//top pane
#define PANE_TOP 0x0

//bottom pane
#define PANE_BOTTOM 0x1

//search pane
#define PANE_SEARCH 0x2

//for prefs
//#define PREF_FIRST_RUN @"isFirstRun"

//flat view
#define FLAT_VIEW 100

//tree view
#define TREE_VIEW 101


//any view
// ->not in UI
#define CURRENT_VIEW -1

//dylib view
#define DYLIBS_VIEW 0

//file view
#define FILES_VIEW 1

//networking view
#define NETWORKING_VIEW 2

//pid
#define KEY_RESULT_PID @"pid"

//name key
#define KEY_RESULT_NAME @"name"

//path key
#define KEY_RESULT_PATH @"path"

//plist key
#define KEY_RESULT_PLIST @"plist"

//extension id key
#define KEY_EXTENSION_ID @"id"

//extension description key
#define KEY_EXTENSION_DETAILS @"details"

//extension (host) browser key
#define KEY_EXTENSION_BROWSER @"browser"

/* VIRUS TOTAL */

//api (v3): file report
#define VT_QUERY_URL @"https://www.virustotal.com/api/v3/files/"

//api (v3): file upload
#define VT_SUBMIT_URL @"https://www.virustotal.com/api/v3/files"

//analysis (of a submitted file)
#define VT_ANALYSIS_URL @"https://www.virustotal.com/api/v3/analyses/"

//analysis id (key in submit result)
#define VT_ANALYSIS_ID @"analysisID"

//how often / how long to poll a submitted file's analysis (seconds)
#define VT_ANALYSIS_POLL_INTERVAL 30
#define VT_ANALYSIS_POLL_MAX (10 * 60)

//report (gui) url
#define VT_REPORT_URL @"https://www.virustotal.com/gui/file/"

//how to get an api key
#define VT_API_KEY_URL @"https://docs.virustotal.com/docs/please-give-me-an-api-key"

//keychain attribute (service) for api key
#define VT_API_KEYCHAIN_ATTR @"com.objective-see.taskexplorer.vtAPIKey"

//keychain attributes (services) for the assistant's api keys
#define ANTHROPIC_API_KEYCHAIN_ATTR @"com.objective-see.taskexplorer.anthropicAPIKey"
#define OPENAI_API_KEYCHAIN_ATTR @"com.objective-see.taskexplorer.openaiAPIKey"

//keychain account for api key
#define VT_API_KEYCHAIN_ACCOUNT @"api_key"

//results cache (per user): ~/Library/Caches/<bundle id>/VirusTotal.json
// ->so relaunches don't repeat every lookup (personal api keys: ~500 lookups/day)
#define VT_CACHE_FILE @"VirusTotal.json"

//cache ttl: known results (7 days), unknown/404 (1 day; a new file may get analyzed soon)
#define VT_CACHE_TTL_KNOWN (7 * 24 * 60 * 60)
#define VT_CACHE_TTL_UNKNOWN (24 * 60 * 60)

//cache cap (entries; oldest dropped)
#define VT_CACHE_MAX_ENTRIES 5000

//max file size for submission (32MB)
#define VT_MAX_SUBMIT_SIZE (32 * 1024 * 1024)

//backoff after a rate limit (HTTP 429), by consecutive hits (seconds)
// ->the last step (15 minutes) means the daily quota (free keys: 500/day; the per-minute limit clears within 60s)
#define VT_BACKOFF_STEPS 15, 30, 60, 15 * 60

//backoff after a network error (seconds)
#define VT_BACKOFF_NETWORK 60

//error
#define VT_ERROR @"error"

//result url
#define VT_RESULTS_URL @"permalink"

//results positives (malicious)
#define VT_RESULTS_POSITIVES @"positives"

//results total
#define VT_RESULTS_TOTAL @"total"

//results ratio
#define VT_RESULTS_RATIO @"ratio"

/* PREFERENCES */

//disable virus total queries
#define PREF_DISABLE_VT_QUERIES @"disableVTQueries"

//max file size (for hashing; read in chunks)
#define MAX_FILE_SIZE (1024ULL*1024ULL*1024ULL)

//max file size for mach-o parsing (read fully into memory, in the extension)
#define MAX_PARSE_FILE_SIZE (64ULL*1024ULL*1024ULL)

//binary info (from extension); keys
#define KEY_BINARY_SIGNING_INFO @"signingInfo"
#define KEY_BINARY_ENCRYPTED @"encrypted"
#define KEY_BINARY_PACKED @"packed"

//signing status: (XPC) request to extension failed
// ->all code signing checks are done by the extension; if that fails, the item is shown as an error
#define SIGNING_STATUS_XPC_FAILED -1

//mcp server enabled
//note: the MCP (test) server only exists in DEBUG builds (see MCPServer.swift)
#define PREF_MCP_ENABLED @"mcpEnabled"

//mcp server port
#define PREF_MCP_PORT @"mcpPort"

//mcp server (bearer) token
// ->in prefs (0600, per user), not the keychain: same protection against other users/sandboxed apps/web pages,
//   w/o keychain access prompts blocking launch (e.g. after the app is re-signed), and scriptable via `defaults read`
#define PREF_MCP_TOKEN @"mcpToken"

//index dyld shared cache dylibs for all processes (via vmmap; slower)
#define PREF_INDEX_CACHE_DYLIBS @"indexCacheDylibs"

//vmmap
//max time (seconds) a spawned helper (e.g. vmmap) may run
#define EXEC_TASK_TIMEOUT 30

#define VMMAP_PATH @"/usr/bin/vmmap"

//mcp server (default) port
#define MCP_DEFAULT_PORT 7373

//assistant provider (0: claude, 1: chatgpt)
#define PREF_ASSISTANT_PROVIDER @"assistantProvider"

//output file
#define OUTPUT_FILE @"kkFindings.txt"

//keys/types for XPC dictionaries

//descriptor type
#define KEY_DESCRIPTOR_TYPE @"descriptorType"

//file path
#define KEY_FILE_PATH @"filePath"

//file type (open files, from the extension)
#define KEY_FILE_TYPE @"fileType"
#define FILE_TYPE_FILE @"file"
#define FILE_TYPE_DIRECTORY @"directory"
#define FILE_TYPE_SOCKET @"socket"
#define FILE_TYPE_DEVICE @"device"
#define FILE_TYPE_FIFO @"fifo"
#define FILE_TYPE_LINK @"symlink"
#define FILE_TYPE_UNKNOWN @"unknown"

//socket local ip addr
#define KEY_LOCAL_ADDR @"localIPAddr"

//socket local port
#define KEY_LOCAL_PORT @"localPort"

//socket remote ip addr
#define KEY_REMOTE_ADDR @"remoteIPAddr"

//socket remote port
#define KEY_REMOTE_PORT @"remotePort"

//socket state
#define KEY_SOCKET_STATE @"socketState"

//socket type
#define KEY_SOCKET_TYPE @"socketType"

//socket family
#define KEY_SOCKET_FAMILY @"socketFamily"

//socket protocol
#define KEY_SOCKET_PROTO @"socketProto"

//sort by pid
#define SORT_BY_PID 0x0

//sort by name
#define SORT_BY_NAME 0x1

//delta for pid tag
#define PID_TAG_DELTA 1000

//search wait time (from app's launch)
#define SEARCH_WAIT_TIME 60

//pls wait (search) message
#define PLS_WAIT_MESSAGE @"completing (initial) task/dylib/file enumeration please wait"

//hotkey 's'
#define KEYCODE_S 0x1

//hotkey 'f'
#define KEYCODE_F 0x3

//hotkey 'w'
#define KEYCODE_W 0xD

//hotkey 'r'
#define KEYCODE_R 0xF

//hotkey 'i'
#define KEYCODE_I 0x22

//unknown task
#define TASK_PATH_UNKNOWN @"<unknown>"

//app kit version for OS X 10.11
#define APPKIT_VERSION_10_11 1404

//state of enumeration; tasks
#define ENUMERATION_STATE_TASKS 0x1

//state of enumeration; dylibs
#define ENUMERATION_STATE_DYLIBS 0x2

//state of enumeration; files
#define ENUMERATION_STATE_FILES 0x3

//state of enumeration; network
#define ENUMERATION_STATE_NETWORK 0x4

//state of enumeration; done
#define ENUMERATION_STATE_COMPLETE 0x5

//support us button tag
#define BUTTON_SUPPORT_US 100

//more info button tag
#define BUTTON_MORE_INFO 101


//patreon url
#define PATREON_URL @"https://www.patreon.com/objective_see"

//product url
#define PRODUCT_URL @"https://objective-see.com/products/taskexplorer.html"

//product name
// ...for version check
#define PRODUCT_NAME @"TaskExplorer"

//product version url
#define PRODUCT_VERSIONS_URL @"https://objective-see.com/products.json"

//update error
#define UPDATE_ERROR -1

//update no new version
#define UPDATE_NOTHING_NEW 0

//update new version
#define UPDATE_NEW_VERSION 1

#endif
