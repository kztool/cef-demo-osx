// Copyright (c) 2013 The Chromium Embedded Framework Authors. All rights
// reserved. Use of this source code is governed by a BSD-style license that
// can be found in the LICENSE file.

#include "browser/client_app.h"

#include "include/cef_command_line.h"
#include "browser/utils.h"

namespace client {
  ClientApp::ClientApp() {}
  
  void ClientApp::OnBeforeCommandLineProcessing(const CefString& process_type,
                                                       CefRefPtr<CefCommandLine> command_line) {
    // Pass additional command-line flags to the browser process.
    if (process_type.empty()) {            
      if (!command_line->HasSwitch(switches::kCachePath) &&
          !command_line->HasSwitch("disable-gpu-shader-disk-cache")) {
        // Don't create a "GPUCache" directory when cache-path is unspecified.
        command_line->AppendSwitch("disable-gpu-shader-disk-cache");
      }
    }
  }
  
  void ClientApp::OnContextInitialized() {
    // Register cookieable schemes with the global cookie manager.
    CefRefPtr<CefCookieManager> manager =CefCookieManager::GetGlobalManager(NULL);
    DCHECK(manager.get());
    manager->SetSupportedSchemes(cookieable_schemes_, NULL);
  }
  
  void ClientApp::OnBeforeChildProcessLaunch(CefRefPtr<CefCommandLine> command_line) {
    
  }
  
}  // namespace client

