// Copyright (c) 2013 The Chromium Embedded Framework Authors. All rights
// reserved. Use of this source code is governed by a BSD-style license that
// can be found in the LICENSE file.

#include "browser/client_app_browser.h"

#include "include/cef_cookie.h"
#include "include/cef_crash_util.h"
#include "include/cef_file_util.h"

#include "browser/utils.h"

namespace client {
  namespace {
    class ClientBrowserDelegate : public ClientAppBrowser::Delegate {
    public:
      ClientBrowserDelegate() {}
      
      void OnContextInitialized(CefRefPtr<ClientAppBrowser> app) OVERRIDE {
        if (CefCrashReportingEnabled()) {
          // Set some crash keys for testing purposes. Keys must be defined in the
          // "crash_reporter.cfg" file. See cef_crash_util.h for details.
          CefSetCrashKeyValue("testkey_small1", "value1_small_browser");
          CefSetCrashKeyValue("testkey_small2", "value2_small_browser");
          CefSetCrashKeyValue("testkey_medium1", "value1_medium_browser");
          CefSetCrashKeyValue("testkey_medium2", "value2_medium_browser");
          CefSetCrashKeyValue("testkey_large1", "value1_large_browser");
          CefSetCrashKeyValue("testkey_large2", "value2_large_browser");
        }
        
        const std::string& crl_sets_path =
        CefCommandLine::GetGlobalCommandLine()->GetSwitchValue(
                                                               switches::kCRLSetsPath);
        if (!crl_sets_path.empty()) {
          // Load the CRLSets file from the specified path.
          CefLoadCRLSetsFile(crl_sets_path);
        }
      }
      
    private:
      DISALLOW_COPY_AND_ASSIGN(ClientBrowserDelegate);
      IMPLEMENT_REFCOUNTING(ClientBrowserDelegate);
    };
  }  // namespace
  
  ClientAppBrowser::ClientAppBrowser() {
    delegates_.insert(new ClientBrowserDelegate);
  }
  
  // static
  CefRefPtr<CefPrintHandler> ClientAppBrowser::CreatePrintHandler() {
    return NULL;
  }
  
  void ClientAppBrowser::OnBeforeCommandLineProcessing(
                                                       const CefString& process_type,
                                                       CefRefPtr<CefCommandLine> command_line) {
    // Pass additional command-line flags to the browser process.
    if (process_type.empty()) {
      // Pass additional command-line flags when off-screen rendering is enabled.
      if (command_line->HasSwitch(switches::kOffScreenRenderingEnabled) &&
          !command_line->HasSwitch(switches::kSharedTextureEnabled)) {
        // Use software rendering and compositing (disable GPU) for increased FPS
        // and decreased CPU usage. This will also disable WebGL so remove these
        // switches if you need that capability.
        // See https://bitbucket.org/chromiumembedded/cef/issues/1257 for details.
        if (!command_line->HasSwitch(switches::kEnableGPU)) {
          command_line->AppendSwitch("disable-gpu");
          command_line->AppendSwitch("disable-gpu-compositing");
        }
      }
      
      if (command_line->HasSwitch(switches::kUseViews) &&
          !command_line->HasSwitch("top-chrome-md")) {
        // Use non-material mode on all platforms by default. Among other things
        // this causes menu buttons to show hover state. See usage of
        // MaterialDesignController::IsModeMaterial() in Chromium code.
        command_line->AppendSwitchWithValue("top-chrome-md", "non-material");
      }
      
      if (!command_line->HasSwitch(switches::kCachePath) &&
          !command_line->HasSwitch("disable-gpu-shader-disk-cache")) {
        // Don't create a "GPUCache" directory when cache-path is unspecified.
        command_line->AppendSwitch("disable-gpu-shader-disk-cache");
      }
      
      DelegateSet::iterator it = delegates_.begin();
      for (; it != delegates_.end(); ++it)
        (*it)->OnBeforeCommandLineProcessing(this, command_line);
    }
  }
  
  void ClientAppBrowser::OnContextInitialized() {
    // Register cookieable schemes with the global cookie manager.
    CefRefPtr<CefCookieManager> manager =
    CefCookieManager::GetGlobalManager(NULL);
    DCHECK(manager.get());
    manager->SetSupportedSchemes(cookieable_schemes_, NULL);
    
    print_handler_ = CreatePrintHandler();
    
    DelegateSet::iterator it = delegates_.begin();
    for (; it != delegates_.end(); ++it)
      (*it)->OnContextInitialized(this);
  }
  
  void ClientAppBrowser::OnBeforeChildProcessLaunch(
                                                    CefRefPtr<CefCommandLine> command_line) {
    DelegateSet::iterator it = delegates_.begin();
    for (; it != delegates_.end(); ++it)
      (*it)->OnBeforeChildProcessLaunch(this, command_line);
  }
  
  void ClientAppBrowser::OnRenderProcessThreadCreated(
                                                      CefRefPtr<CefListValue> extra_info) {
    DelegateSet::iterator it = delegates_.begin();
    for (; it != delegates_.end(); ++it)
      (*it)->OnRenderProcessThreadCreated(this, extra_info);
  }
  
}  // namespace client

