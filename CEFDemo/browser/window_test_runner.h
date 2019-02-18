// Copyright (c) 2016 The Chromium Embedded Framework Authors. All rights
// reserved. Use of this source code is governed by a BSD-style license that
// can be found in the LICENSE file.

#ifndef CEF_TESTS_CEFCLIENT_BROWSER_WINDOW_TEST_RUNNER_H_
#define CEF_TESTS_CEFCLIENT_BROWSER_WINDOW_TEST_RUNNER_H_
#pragma once

#include "include/cef_browser.h"

namespace client {
  namespace window_test {
    
    // Implement this interface for different platforms. Methods will be called on
    // the browser process UI thread unless otherwise indicated.
    class WindowTestRunner {
    public:
      void Maximize(CefRefPtr<CefBrowser> browser);
      void Restore(CefRefPtr<CefBrowser> browser);
      
      WindowTestRunner();
      virtual ~WindowTestRunner() {}
    };
    
  }  // namespace window_test
}  // namespace client

#endif  // CEF_TESTS_CEFCLIENT_BROWSER_WINDOW_TEST_RUNNER_H_

