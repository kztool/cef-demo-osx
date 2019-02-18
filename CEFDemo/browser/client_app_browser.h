// Copyright (c) 2013 The Chromium Embedded Framework Authors. All rights
// reserved. Use of this source code is governed by a BSD-style license that
// can be found in the LICENSE file.

#ifndef CEF_TESTS_SHARED_BROWSER_CLIENT_APP_BROWSER_H_
#define CEF_TESTS_SHARED_BROWSER_CLIENT_APP_BROWSER_H_
#pragma once

#include <set>

#include "browser/client_app.h"

namespace client {
  // Client app implementation for the browser process.
  class ClientAppBrowser : public ClientApp, public CefBrowserProcessHandler {
  public:
    ClientAppBrowser();
  private:    
    // Create the Linux print handler. Implemented by cefclient in
    // client_app_delegates_browser.cc
    static CefRefPtr<CefPrintHandler> CreatePrintHandler();
    
    // CefApp methods.
    void OnBeforeCommandLineProcessing(const CefString& process_type,
                                       CefRefPtr<CefCommandLine> command_line) OVERRIDE;
    CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() OVERRIDE {
      return this;
    }
    
    // CefBrowserProcessHandler methods.
    void OnContextInitialized() OVERRIDE;
    void OnBeforeChildProcessLaunch(CefRefPtr<CefCommandLine> command_line) OVERRIDE;

    CefRefPtr<CefPrintHandler> GetPrintHandler() OVERRIDE {
      return print_handler_;
    }
    
    CefRefPtr<CefPrintHandler> print_handler_;
    
    IMPLEMENT_REFCOUNTING(ClientAppBrowser);
    DISALLOW_COPY_AND_ASSIGN(ClientAppBrowser);
  };
}  // namespace client

#endif  // CEF_TESTS_SHARED_BROWSER_CLIENT_APP_BROWSER_H_

