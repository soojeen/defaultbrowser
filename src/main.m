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

NSMutableDictionary* get_http_handlers() {
    NSArray *handlers =
      (__bridge NSArray *) LSCopyAllHandlersForURLScheme(
        (__bridge CFStringRef) @"http"
      );

    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    for (int i = 0; i < [handlers count]; i++) {
        NSString *handler = [handlers objectAtIndex:i];
        dict[app_name_from_bundle_id(handler)] = handler;
    }

    return dict;
}

NSString* get_current_http_handler() {
    NSString *handler =
        (__bridge NSString *) LSCopyDefaultHandlerForURLScheme(
            (__bridge CFStringRef) @"http"
        );

    return app_name_from_bundle_id(handler);
}

// Blocks until the user answers the consent dialog (if any).
BOOL set_default_handler(NSString *url_scheme, NSString *handler) {
    NSURL *app_url = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:handler];
    __block BOOL done = NO;
    __block BOOL ok = NO;

    // Report the error inside the handler: without ARC, the NSError isn't
    // retained past the handler's return.
    [[NSWorkspace sharedWorkspace] setDefaultApplicationAtURL:app_url
                                         toOpenURLsWithScheme:url_scheme
                                            completionHandler:^(NSError *error) {
        NSError *underlying = error.userInfo[NSUnderlyingErrorKey];

        if (underlying != nil &&
            [underlying.domain isEqualToString:NSOSStatusErrorDomain] &&
            underlying.code == userCanceledErr) {
            fprintf(stderr, "Change declined; default browser not changed\n");
        } else if (error != nil) {
            fprintf(stderr, "Could not set %s handler: %s\n", [url_scheme UTF8String], [[error localizedDescription] UTF8String]);
        }
        ok = (error == nil);
        done = YES;
    }];

    while (!done) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }

    return ok;
}

BOOL is_default_handler(NSString *url_scheme, NSString *handler) {
    NSString *current = CFBridgingRelease(LSCopyDefaultHandlerForURLScheme((__bridge CFStringRef) url_scheme));

    return current != nil && [current caseInsensitiveCompare:handler] == NSOrderedSame;
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

            if ([target_handler_name caseInsensitiveCompare:current_handler_name] == NSOrderedSame) {
              printf("%s is already set as the default HTTP handler\n", target);
            } else {
                NSString *target_handler = handlers[target_handler_name];

                if (target_handler != nil) {
                    // Set HTTP first and wait for consent. Approving the browser change
                    // usually updates HTTPS too, so only ask again if it didn't.
                    if (!set_default_handler(@"http", target_handler)) {
                        return 1;
                    }

                    if (!is_default_handler(@"https", target_handler) &&
                        !set_default_handler(@"https", target_handler)) {
                        return 1;
                    }
                } else {
                    printf("%s is not available as an HTTP handler\n", target);

                    return 1;
                }
            }
        }
    }

    return 0;
}
