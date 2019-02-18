// Copyright (c) 2013 The Chromium Embedded Framework Authors. All rights
// reserved. Use of this source code is governed by a BSD-style license that
// can be found in the LICENSE file.

#ifndef CEF_TESTS_SHARED_COMMON_CLIENT_APP_H_
#define CEF_TESTS_SHARED_COMMON_CLIENT_APP_H_
#pragma once

#include <vector>

#include "include/cef_app.h"

namespace client {
  
  // Base class for customizing process-type-based behavior.
  class ClientApp : public CefApp, public CefBrowserProcessHandler  {
  public:
    ClientApp();
    
    // CefApp methods.
    void OnBeforeCommandLineProcessing(const CefString& process_type,
                                       CefRefPtr<CefCommandLine> command_line) OVERRIDE;
    CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() OVERRIDE {
      return this;
    }
    
    // CefBrowserProcessHandler methods.
    void OnContextInitialized() OVERRIDE;
    void OnBeforeChildProcessLaunch(CefRefPtr<CefCommandLine> command_line) OVERRIDE;
    
    
  protected:
    // Schemes that will be registered with the global cookie manager.
    std::vector<CefString> cookieable_schemes_;
    
  private:
    DISALLOW_COPY_AND_ASSIGN(ClientApp);
    IMPLEMENT_REFCOUNTING(ClientApp);
  };
  
}  // namespace client

#endif  // CEF_TESTS_SHARED_COMMON_CLIENT_APP_H_

