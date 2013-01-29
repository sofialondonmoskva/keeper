#import "AppDelegate.h"

static volatile int should_run = 0;

@implementation AppDelegate
@synthesize status_item,scripts,GIANT,queue,uid;

#pragma mark SCRIPT
- (NSAppleScript * ) scriptify:(NSString *)s {
    return [[NSAppleScript alloc] initWithSource:s];
}

#pragma mark IO send data, receive input
- (void) send_queue {
    [GIANT lock];
    for (NSString *stamp in queue) {
        NSData *body = [NSJSONSerialization dataWithJSONObject:[queue valueForKey:stamp] options:0 error:NULL];
        if (!body)
            body = [NSData data];
        NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/%@/input/%@",URL_REMOTE,uid,stamp]];
        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url cachePolicy:NSURLCacheStorageNotAllowed timeoutInterval:10.0];
        [request setHTTPMethod:@"POST"];
        [request setValue:[NSString stringWithFormat:@"%ld", body.length] forHTTPHeaderField:@"Content-Length"];
        [request setHTTPBody:body];
        [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *response, NSData *result, NSError *err) {
            [GIANT lock];
            if (!err)
                [self.queue removeObjectForKey:stamp];
            [GIANT unlock];
        }];
    }
    [GIANT unlock];
}
- (void) sender {
    for (;;) {
        sleep(AGGREGATE);
        if (!should_run)
            continue;
        [self send_queue];
    }
}

- (void) collecter {
    for (;;) {
        sleep(SAMPLE_INTERVAL);
        if (!should_run)
            continue;

        [GIANT lock];
        NSString *stamp = [NSString stringWithFormat:@"%ld",(time(NULL) / AGGREGATE) * AGGREGATE];
        NSMutableDictionary *d = [queue objectForKey:stamp];
        if (!d) {
            d = [NSMutableDictionary dictionary];
            [queue setValue:d forKey:stamp];
        }
        
        NSString *app = [[[[NSWorkspace sharedWorkspace] activeApplication] objectForKey:@"NSApplicationName"] lowercaseString];
        NSAppleScript *script = [scripts objectForKey:app];
        if (script)
            app = [[NSURL URLWithString:[[script executeAndReturnError:NULL] stringValue]] host];
        if (app) {
            NSNumber *seconds = [d objectForKey:app];
            if (!seconds)
                seconds = [[NSNumber alloc] initWithUnsignedLongLong:0];

            [d setValue:[[NSNumber alloc] initWithInteger:[seconds unsignedLongLongValue] + SAMPLE_INTERVAL] forKey:app];
        }
        [GIANT unlock];
    }
}


#pragma mark UID
- (void) save_value:(id) u for_key: (id) k{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setValue:u forKey:k];
    [defaults synchronize];
}


- (void) generate_new_uid {
    NSURL *url = [NSURL URLWithString:URL_REMOTE_GENERATE_UID];

    // strip all non alphanumeric stuff
    NSString *r = [[[NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil] componentsSeparatedByCharactersInSet:[[ NSCharacterSet alphanumericCharacterSet ] invertedSet ]] componentsJoinedByString:@""];
    if (r && [r length] == UID_LEN) {
        self.uid = r;
    } else {
        self.uid = @"";
    }
    [self save_value:uid for_key:@"uid"];
}

#pragma mark MENU
- (void) report:(id) sender {
    [self send_queue];
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/%@/report/",URL_REMOTE,uid]]];
}
- (void) reset:(id) sender {
    NSAlert *alert = [NSAlert alertWithMessageText:@"Are you sure?"
                                     defaultButton:@"NO!"
                                   alternateButton:nil
                                       otherButton:@"yep.. i dont care about my data"
                         informativeTextWithFormat:@"this will erase your UID, which will remove all your data."];
    if ([alert runModal] == -1)
        [self generate_new_uid];
}
- (void) pause:(NSMenuItem *) sender {
    if (should_run) {
        should_run = 0;
        [sender setTitle:START_TEXT];
        [status_item setImage:[NSImage imageNamed:@"keeper_stopped"]];
    } else {
        should_run = 1;
        [sender setTitle:PAUSE_TEXT];
        [status_item setImage:[NSImage imageNamed:@"keeper_running"]];
    }
}
- (void) quit:(id) sender {
    [NSApp terminate:nil];
}
- (void) toggle_autostart:(NSMenuItem *) sender {
    if (![self does_start_at_login]) {
        [sender setTitle:DO_NOT_START_AT_LOGIN_TEXT];
        [self start_at_login];
    } else {
        [sender setTitle:START_AT_LOGIN_TEXT];
        [self do_not_start_at_login];
    }
}
# pragma mark LOGIN_LIST
-(void) start_at_login {
	NSString * appPath = [[NSBundle mainBundle] bundlePath];
	CFURLRef url = (__bridge CFURLRef)[NSURL fileURLWithPath:appPath];
	LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL,kLSSharedFileListSessionLoginItems, NULL);
	if (loginItems) {
		LSSharedFileListItemRef item = LSSharedFileListInsertItemURL(loginItems,
                                                                     kLSSharedFileListItemLast, NULL, NULL,
                                                                     url, NULL, NULL);
		if (item)
			CFRelease(item);
        CFRelease(loginItems);
	}
}

-(void) walk_login_list:(BOOL (^) (LSSharedFileListItemRef,CFURLRef)) should_remove {
	LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL,kLSSharedFileListSessionLoginItems, NULL);
	if (loginItems) {
		UInt32 seedValue;
		CFArrayRef  items = LSSharedFileListCopySnapshot(loginItems, &seedValue);
        if (items) {
            for(int i = 0; i < CFArrayGetCount(items); ++i) {
                LSSharedFileListItemRef itemRef = (LSSharedFileListItemRef)CFArrayGetValueAtIndex(items, i);
                CFURLRef url = NULL;
                if (LSSharedFileListItemResolve(itemRef, 0, &url, NULL) == noErr) {
                    if (should_remove(itemRef,url)) {
                        LSSharedFileListItemRemove(loginItems,itemRef);
                    }
                }
                CFRelease(url);
            }
            CFRelease(items);
        }
        CFRelease(loginItems);
    }
}
- (void) do_not_start_at_login {
	NSString * appPath = [[NSBundle mainBundle] bundlePath];
    
    [self walk_login_list:^BOOL(LSSharedFileListItemRef r,CFURLRef url) {
        NSString * urlPath = [(__bridge NSURL*)url path];
        if ([urlPath compare:appPath] == NSOrderedSame){
            return TRUE;
        }
        return FALSE;
    }];
}

- (BOOL) does_start_at_login {
	NSString * appPath = [[NSBundle mainBundle] bundlePath];
    
    __block BOOL found = FALSE;
    [self walk_login_list:^BOOL(LSSharedFileListItemRef r,CFURLRef url) {
        NSString * urlPath = [(__bridge NSURL*)url path];
        if ([urlPath compare:appPath] == NSOrderedSame){
            found = TRUE;
        }
        return FALSE;
    }];
    return found;
}

#pragma mark APP
- (void) applicationWillTerminate:(NSNotification *)notification {
    [GIANT lock];
    if (queue)
        [self save_value:queue for_key:@"queue"];
    [GIANT unlock];
}
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    self.uid = [[NSUserDefaults standardUserDefaults] stringForKey:@"uid"];
    if (!uid || [uid length] != UID_LEN)
        [self generate_new_uid];

    // if we have left over queue, just load it and store empty dictionary at its place
    self.queue = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"queue"]];
    if (self.queue) {
        [self save_value:[NSDictionary dictionary] for_key:@"queue"];
    } else {
        self.queue = [NSMutableDictionary dictionary];
    }
    
    self.GIANT = [[NSLock alloc] init];
    self.status_item = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.scripts = @{
        @"safari" : [self scriptify:SAFARI_GET_CURRENT_TAB],
        @"google chrome" : [self scriptify:CHROME_GET_CURRENT_TAB],
    };
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL does_start_at_login = [self does_start_at_login];
    if (!does_start_at_login) {
        if (![defaults stringForKey:@"asked"]) {
            [self save_value:@"asked" for_key:@"asked"];
            NSAlert *alert = [NSAlert alertWithMessageText:@"Do you want to auto start 'keeper' after every login?"
                                             defaultButton:@"yep"
                                           alternateButton:nil
                                               otherButton:@"no"
                                 informativeTextWithFormat:@"Starting it at login makes it harder for you to lose productivity data. You can disable the autostart by clicking '" DO_NOT_START_AT_LOGIN_TEXT "' on the status menu."];
            if ([alert runModal] == 1) {
                [self start_at_login];
                does_start_at_login = TRUE;
            }
        }
    }
//    // need lawyer help for this text
//    if (![defaults stringForKey:@"agreed"]) {
//        NSAlert *alert = [NSAlert alertWithMessageText:@"Terms of agreement"
//                                         defaultButton:@"YES"
//                                       alternateButton:nil
//                                           otherButton:@"NO"
//                             informativeTextWithFormat:@"By clicking 'YES' you agree that this application will send data from your computer to " URL_REMOTE];
//        if ([alert runModal] != 1) {
//            [NSApp terminate:nil];
//        } else {
//            [self save_value:@"agreed" for_key:@"agreed"];
//        }
//    }
    
    self.status_item = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    NSMenu *menu = [[NSMenu alloc] init];
    
    [menu addItemWithTitle:@"Productivity report" action:@selector(report:) keyEquivalent:@""];
    [menu addItemWithTitle:PAUSE_TEXT action:@selector(pause:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Reset UID" action:@selector(reset:) keyEquivalent:@""];
    [menu addItemWithTitle:(does_start_at_login ? DO_NOT_START_AT_LOGIN_TEXT : START_AT_LOGIN_TEXT) action:@selector(toggle_autostart:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Quit" action:@selector(quit:) keyEquivalent:@""];

    [status_item setMenu:menu];
    
    [self performSelectorInBackground:@selector(sender) withObject:nil];
    [self performSelectorInBackground:@selector(collecter) withObject:nil];
    [self pause:nil]; // we are stopped at start, so kickstart everything :)
}
//
@end
