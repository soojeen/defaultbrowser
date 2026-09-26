//
//  main.m
//  defaultbrowser
//

#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>
#import <AppKit/AppKit.h>

NSString* app_name_from_bundle_id(NSString *app_bundle_id) {
    return [[[app_bundle_id componentsSeparatedByString:@"."] lastObject] lowercaseString];
}

NSString* default_handler(NSString *url_scheme) {
    return CFBridgingRelease(LSCopyDefaultHandlerForURLScheme((__bridge CFStringRef) url_scheme));
}

NSMutableDictionary* get_http_handlers() {
    NSArray *handlers = CFBridgingRelease(LSCopyAllHandlersForURLScheme((__bridge CFStringRef) @"http"));

    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    for (int i = 0; i < [handlers count]; i++) {
        NSString *handler = [handlers objectAtIndex:i];
        dict[app_name_from_bundle_id(handler)] = handler;
    }

    return dict;
}

NSString* get_current_http_handler() {
    return app_name_from_bundle_id(default_handler(@"http"));
}

BOOL is_default_handler(NSString *url_scheme, NSString *handler) {
    NSString *current = default_handler(url_scheme);

    return current != nil && [current caseInsensitiveCompare:handler] == NSOrderedSame;
}

// Blocks until the user answers the consent dialog (if any).
BOOL set_default_handler(NSString *url_scheme, NSString *handler) {
    NSURL *app_url = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:handler];

    if (app_url == nil) {
        fprintf(stderr, "%s is not installed\n", [handler UTF8String]);
        return NO;
    }

    __block BOOL ok = NO;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    // Report the error inside the handler: without ARC, the NSError isn't
    // retained past the handler's return. The handler runs off the main
    // thread, so blocking on the semaphore can't deadlock.
    [[NSWorkspace sharedWorkspace] setDefaultApplicationAtURL:app_url
                                         toOpenURLsWithScheme:url_scheme
                                            completionHandler:^(NSError *error) {
        NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
        BOOL declined =
            ([error.domain isEqualToString:NSCocoaErrorDomain] && error.code == NSUserCancelledError) ||
            ([underlying.domain isEqualToString:NSOSStatusErrorDomain] && underlying.code == userCanceledErr);

        if (declined) {
            fprintf(stderr, "Change declined; default browser not changed\n");
        } else if (error != nil) {
            fprintf(stderr, "Could not set %s handler: %s\n", [url_scheme UTF8String], [[error localizedDescription] UTF8String]);
        }

        ok = (error == nil);
        dispatch_semaphore_signal(sem);
    }];

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    dispatch_release(sem);

    return ok;
}

int main(int argc, const char *argv[]) {
    const char *target = (argc == 1) ? '\0' : argv[1];

    @autoreleasepool {
        // Get all HTTP handlers
        NSMutableDictionary *handlers = get_http_handlers();

        // Get current HTTP handler
        NSString *current_handler_name = get_current_http_handler();

        if (target == '\0') {
            // List all HTTP handlers, marking the current one with a star
            for (NSString *key in handlers) {
                char *mark = [key caseInsensitiveCompare:current_handler_name] == NSOrderedSame ? "* " : "  ";
                printf("%s%s\n", mark, [key UTF8String]);
            }
        } else {
            NSString *target_handler_name = [NSString stringWithUTF8String:target];
            NSString *target_handler = handlers[target_handler_name];

            if (target_handler == nil) {
                printf("%s is not available as an HTTP handler\n", target);

                return 1;
            }

            // Set HTTP first and wait for consent. Approving the browser change
            // usually updates HTTPS too, so only ask again if it didn't.
            BOOL changed = NO;

            for (NSString *scheme in @[@"http", @"https"]) {
                if (is_default_handler(scheme, target_handler)) {
                    continue;
                }

                if (!set_default_handler(scheme, target_handler)) {
                    return 1;
                }

                changed = YES;
            }

            if (!changed) {
                printf("%s is already set as the default HTTP handler\n", target);
            }
        }
    }

    return 0;
}
