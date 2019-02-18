// Copyright (c) 2016 The Chromium Embedded Framework Authors. All rights
// reserved. Use of this source code is governed by a BSD-style license that
// can be found in the LICENSE file.

#include "browser/window_test_runner.h"


#import <Cocoa/Cocoa.h>

#include "include/wrapper/cef_helpers.h"
#include "browser/main_message_loop.h"

namespace client {
  namespace window_test {
    WindowTestRunner::WindowTestRunner() {}

    void WindowTestRunner::Maximize(CefRefPtr<CefBrowser> browser) {
      CEF_REQUIRE_UI_THREAD();
      REQUIRE_MAIN_THREAD();
      
      NSWindow* window = [browser->GetHost()->GetWindowHandle() window];
      [window performZoom:nil];
    }
    
    void WindowTestRunner::Restore(CefRefPtr<CefBrowser> browser) {
      CEF_REQUIRE_UI_THREAD();
      REQUIRE_MAIN_THREAD();
      
      NSWindow* window = [browser->GetHost()->GetWindowHandle() window];
      if ([window isMiniaturized]) {
        [window deminiaturize:nil];
      } else if ([window isZoomed]) {
        [window performZoom:nil];
      }
    }
  }  // namespace window_test
}  // namespace client

