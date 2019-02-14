//
//  main.m
//  CEFDemo
//
//  Created by 田硕 on 2019/2/14.
//  Copyright © 2019 田硕. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#include "include/cef_app.h"
#include "include/wrapper/cef_library_loader.h"
#include "include/views/cef_browser_view.h"

class SZApp : public CefApp {
public:
    SZApp() {}
private:
    // Include the default reference counting implementation.
    IMPLEMENT_REFCOUNTING(SZApp);
};

class SZBrowserHandler : public CefClient {
public:
    SZBrowserHandler() {}
private:
    // Include the default reference counting implementation.
    IMPLEMENT_REFCOUNTING(SZBrowserHandler);
};


@interface RootView : NSView
@end
@implementation RootView
- (void)viewWillMoveToWindow:(NSWindow *)newWindow {
    CefRefPtr<SZBrowserHandler> handler(new SZBrowserHandler());
    CefBrowserSettings browser_settings;
    CefWindowInfo info;
    
    info.SetAsChild(self,
                    self.bounds.origin.x,
                    self.bounds.origin.y,
                    self.bounds.size.width,
                    self.bounds.size.height
                    );
    
    CefBrowserHost::CreateBrowserSync(info,
                                      handler,
                                      "chrome://version",
                                      browser_settings,
                                      nil);
}
@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@end
@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Create Window
    NSSize screenSize = [NSScreen mainScreen].frame.size;
    CGFloat winWidth = screenSize.width * 0.8;
    CGFloat winHeight = screenSize.height * 0.8;
    
    NSWindow *win = [[NSWindow alloc]
                     initWithContentRect: NSMakeRect((screenSize.width - winWidth)/2,
                                                     (screenSize.height - winHeight) /2,
                                                     winWidth,
                                                     winHeight)
                     styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                     backing: NSBackingStoreBuffered
                     defer: true];
    [win makeKeyAndOrderFront:nil];
    
    // Add RootView
    NSView* rootView = [[RootView alloc] initWithFrame:win.contentView.bounds];
    rootView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [[win contentView] addSubview:rootView];
}
@end

// Entry Point
int main(int argc, char* argv[]) {
    @autoreleasepool {
        // Load the CEF framework library at runtime
        CefScopedLibraryLoader library_loader;
        if (!library_loader.LoadInMain())
            return 1;
        
        // Provide CEF with command-line arguments.
        CefMainArgs main_args(argc, argv);
        
        // Initialize CEF for the browser process.
        CefSettings settings;
        CefRefPtr<SZApp> app(new SZApp);
        CefInitialize(main_args, settings, app.get(), NULL);
        
        // Create the application delegate.
        AppDelegate* appDelegate = [[AppDelegate alloc] init];
        NSApplication.sharedApplication.delegate = appDelegate;
        
        // Run the CEF message loop. This will block until CefQuitMessageLoop() is called.
        CefRunMessageLoop();
        CefShutdown();
    }
    return 0;
}
