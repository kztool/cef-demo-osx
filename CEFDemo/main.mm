// Copyright (c) 2013 The Chromium Embedded Framework Authors.
// Portions copyright (c) 2010 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "browser/utils.h"

#import "browser/browser_manager.h"

// Receives notifications from the application. Will delete itself when done.
@interface ClientAppDelegate : NSObject<NSApplicationDelegate>
- (void)createApplication:(id)object;
- (void)tryToTerminateApplication:(NSApplication*)app;
@end
@implementation ClientAppDelegate
// Create the application on the UI thread.
- (void)createApplication:(id)object {
  // Set the delegate for application events.
  [[NSApplication sharedApplication] setDelegate:self];
  // Create the first window.
  client::BrowserManager::Get()->CreateRootWindow(client::WindowType_Web, false,  client::kDefaultUrl);
}

- (void)tryToTerminateApplication:(NSApplication*)app {
  client::BrowserManager::Get()->CloseAllWindows(false);
}

- (void)orderFrontStandardAboutPanel:(id)sender {
  [[NSApplication sharedApplication] orderFrontStandardAboutPanel:nil];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*)sender {
  return NSTerminateNow;
}
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

- (void)terminate:(id)sender {
  ClientAppDelegate* delegate = static_cast<ClientAppDelegate*>([[NSApplication sharedApplication] delegate]);
  [delegate tryToTerminateApplication:self];
  // Return, don't exit. The application is responsible for exiting on its own.
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
        if (!command_line->HasSwitch("load-extension")) {
          command_line->AppendSwitchWithValue("load-extension", "set_page_color");
        }
        
        if (!command_line->HasSwitch(switches::kCachePath) &&
            !command_line->HasSwitch("disable-gpu-shader-disk-cache")) {
          // Don't create a "GPUCache" directory when cache-path is unspecified.
          command_line->AppendSwitch("disable-gpu-shader-disk-cache");
        }
      }
    }
    
    void OnContextInitialized() OVERRIDE {
      // Register cookieable schemes with the global cookie manager.
      CefRefPtr<CefCookieManager> manager = CefCookieManager::GetGlobalManager(NULL);
      DCHECK(manager.get());
      manager->SetSupportedSchemes(cookieable_schemes_, NULL);
    }
  private:
    // Schemes that will be registered with the global cookie manager.
    std::vector<CefString> cookieable_schemes_;
    
    DISALLOW_COPY_AND_ASSIGN(ClientApp);
    IMPLEMENT_REFCOUNTING(ClientApp);
  };
  
  namespace {
    int RunMain(int argc, char* argv[]) {
      // Load the CEF framework library at runtime instead of linking directly
      // as required by the macOS sandbox implementation.
      CefScopedLibraryLoader library_loader;
      if (!library_loader.LoadInMain()) {
        return 1;
      }
      
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
      
      CefSettings settings;
      
      // Populate the settings based on command line arguments.
      CefString(&settings.cache_path) = command_line->GetSwitchValue(switches::kCachePath);
      
      // Create the main message loop object.
      scoped_ptr<MainMessageLoop> message_loop(new MainMessageLoop);
      
      // Initialize CEF.
      // Create the main context object.
      scoped_ptr<BrowserManager> browser_manager(new BrowserManager(command_line, main_args, settings, app, NULL));
      
      // Create the application delegate and window.
      ClientAppDelegate* delegate = [[ClientAppDelegate alloc] init];
      [delegate performSelectorOnMainThread:@selector(createApplication:) withObject:nil waitUntilDone:NO];
      
      // Run the message loop. This will block until Quit() is called.
      int result = message_loop->Run();
      
      // Shut down CEF.
      browser_manager->Shutdown();
      
      // Release objects in reverse order of creation.
      [delegate release];
      message_loop.reset();
      browser_manager.reset();
      [autopool release];
      
      return result;
    }
  }  // namespace
}  // namespace client

// Entry point function for the browser process.
int main(int argc, char* argv[]) {
  return client::RunMain(argc, argv);
}
