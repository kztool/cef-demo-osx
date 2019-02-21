// Copyright (c) 2013 The Chromium Embedded Framework Authors.
// Portions copyright (c) 2010 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "browser/utils.h"

#import "browser/main_context.h"

// Receives notifications from the application. Will delete itself when done.
@interface ClientAppDelegate : NSObject<NSApplicationDelegate>
- (void)createApplication:(id)object;
- (void)tryToTerminateApplication:(NSApplication*)app;
@end

// Provide the CefAppProtocol implementation required by CEF.
@interface ClientApplication : NSApplication<CefAppProtocol> {
@private
  BOOL handlingSendEvent_;
}
@end

@implementation ClientApplication
- (BOOL)isHandlingSendEvent {
  return handlingSendEvent_;
}

- (void)setHandlingSendEvent:(BOOL)handlingSendEvent {
  handlingSendEvent_ = handlingSendEvent;
}

- (void)sendEvent:(NSEvent*)event {
  CefScopedSendingEvent sendingEventScoper;
  [super sendEvent:event];
}

// |-terminate:| is the entry point for orderly "quit" operations in Cocoa. This
// includes the application menu's quit menu item and keyboard equivalent, the
// application's dock icon menu's quit menu item, "quit" (not "force quit") in
// the Activity Monitor, and quits triggered by user logout and system restart
// and shutdown.
//
// The default |-terminate:| implementation ends the process by calling exit(),
// and thus never leaves the main run loop. This is unsuitable for Chromium
// since Chromium depends on leaving the main run loop to perform an orderly
// shutdown. We support the normal |-terminate:| interface by overriding the
// default implementation. Our implementation, which is very specific to the
// needs of Chromium, works by asking the application delegate to terminate
// using its |-tryToTerminateApplication:| method.
//
// |-tryToTerminateApplication:| differs from the standard
// |-applicationShouldTerminate:| in that no special event loop is run in the
// case that immediate termination is not possible (e.g., if dialog boxes
// allowing the user to cancel have to be shown). Instead, this method tries to
// close all browsers by calling CloseBrowser(false) via
// ClientHandler::CloseAllBrowsers. Calling CloseBrowser will result in a call
// to ClientHandler::DoClose and execution of |-performClose:| on the NSWindow.
// DoClose sets a flag that is used to differentiate between new close events
// (e.g., user clicked the window close button) and in-progress close events
// (e.g., user approved the close window dialog). The NSWindowDelegate
// |-windowShouldClose:| method checks this flag and either calls
// CloseBrowser(false) in the case of a new close event or destructs the
// NSWindow in the case of an in-progress close event.
// ClientHandler::OnBeforeClose will be called after the CEF NSView hosted in
// the NSWindow is dealloc'ed.
//
// After the final browser window has closed ClientHandler::OnBeforeClose will
// begin actual tear-down of the application by calling CefQuitMessageLoop.
// This ends the NSApplication event loop and execution then returns to the
// main() function for cleanup before application termination.
//
// The standard |-applicationShouldTerminate:| is not supported, and code paths
// leading to it must be redirected.
- (void)terminate:(id)sender {
  ClientAppDelegate* delegate = static_cast<ClientAppDelegate*>([[NSApplication sharedApplication] delegate]);
  [delegate tryToTerminateApplication:self];
  // Return, don't exit. The application is responsible for exiting on its own.
}
@end

@implementation ClientAppDelegate
// Create the application on the UI thread.
- (void)createApplication:(id)object {
  // Set the delegate for application events.
  [[NSApplication sharedApplication] setDelegate:self];
  
  // Create the first window.
  client::MainContext::Get()->GetRootWindowManager()->CreateRootWindow(client::WindowType_Web,
                                                                       false,
                                                                       client::MainContext::Get()->GetMainURL());
}

- (void)tryToTerminateApplication:(NSApplication*)app {
  client::MainContext::Get()->GetRootWindowManager()->CloseAllWindows(false);
}

- (void)orderFrontStandardAboutPanel:(id)sender {
  [[NSApplication sharedApplication] orderFrontStandardAboutPanel:nil];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*)sender {
  return NSTerminateNow;
}
@end

namespace client {
  // Base class for customizing process-type-based behavior.
  class ClientApp : public CefApp, public CefBrowserProcessHandler  {
  public:
    ClientApp() {}
    
    // CefApp methods.
    CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() OVERRIDE { return this; }
    
    void OnBeforeCommandLineProcessing(const CefString& process_type, CefRefPtr<CefCommandLine> command_line) OVERRIDE {
      // Pass additional command-line flags to the browser process.
      if (process_type.empty()) {
        if (!command_line->HasSwitch(switches::kCachePath) &&
            !command_line->HasSwitch("disable-gpu-shader-disk-cache")) {
          // Don't create a "GPUCache" directory when cache-path is unspecified.
          command_line->AppendSwitch("disable-gpu-shader-disk-cache");
        }
      }
    }

    void OnContextInitialized() OVERRIDE {
      // Register cookieable schemes with the global cookie manager.
      CefRefPtr<CefCookieManager> manager =CefCookieManager::GetGlobalManager(NULL);
      DCHECK(manager.get());
      manager->SetSupportedSchemes(cookieable_schemes_, NULL);
    }
  protected:
    // Schemes that will be registered with the global cookie manager.
    std::vector<CefString> cookieable_schemes_;
    
  private:
    DISALLOW_COPY_AND_ASSIGN(ClientApp);
    IMPLEMENT_REFCOUNTING(ClientApp);
  };
  
  namespace {
    int RunMain(int argc, char* argv[]) {
      // Load the CEF framework library at runtime instead of linking directly
      // as required by the macOS sandbox implementation.
      CefScopedLibraryLoader library_loader;
      if (!library_loader.LoadInMain())
        return 1;
      
      CefMainArgs main_args(argc, argv);
      
      // Initialize the AutoRelease pool.
      NSAutoreleasePool* autopool = [[NSAutoreleasePool alloc] init];
      
      // Initialize the ClientApplication instance.
      [ClientApplication sharedApplication];
      
      // Parse command-line arguments.
      CefRefPtr<CefCommandLine> command_line = CefCommandLine::CreateCommandLine();
      command_line->InitFromArgv(argc, argv);
      
      // Create a ClientApp of the correct type.
      CefRefPtr<CefApp> app(new ClientApp);
      
      // Create the main context object.
      scoped_ptr<MainContext> context(new MainContext(command_line, true));
      
      CefSettings settings;
      
      // Populate the settings based on command line arguments.
      context->PopulateSettings(&settings);
      
      // Create the main message loop object.
      scoped_ptr<MainMessageLoop> message_loop(new MainMessageLoop);
      
      // Initialize CEF.
      context->Initialize(main_args, settings, app, NULL);
      
      // Create the application delegate and window.
      ClientAppDelegate* delegate = [[ClientAppDelegate alloc] init];
      [delegate performSelectorOnMainThread:@selector(createApplication:)
                                 withObject:nil
                              waitUntilDone:NO];
      
      // Run the message loop. This will block until Quit() is called.
      int result = message_loop->Run();
      
      // Shut down CEF.
      context->Shutdown();
      
      // Release objects in reverse order of creation.
      [delegate release];
      message_loop.reset();
      context.reset();
      [autopool release];
      
      return result;
    }
  }  // namespace
}  // namespace client

// Entry point function for the browser process.
int main(int argc, char* argv[]) {
  return client::RunMain(argc, argv);
}
