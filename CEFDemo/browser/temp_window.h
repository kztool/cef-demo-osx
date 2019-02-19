// Copyright (c) 2015 The Chromium Embedded Framework Authors. All rights
// reserved. Use of this source code is governed by a BSD-style license that
// can be found in the LICENSE file.

#ifndef CEF_TESTS_CEFCLIENT_BROWSER_TEMP_WINDOW_H_
#define CEF_TESTS_CEFCLIENT_BROWSER_TEMP_WINDOW_H_
#pragma once

#import "utils.h"

namespace client {
  // Represents a singleton hidden window that acts as a temporary parent for
  // popup browsers. Only accessed on the UI thread.
  class TempWindow {
  public:
    // Returns the singleton window handle.
    static CefWindowHandle GetWindowHandle();
    
  private:
    // A single instance will be created/owned by RootWindowManager.
    friend class RootWindowManager;
    // Allow deletion via scoped_ptr only.
    friend struct base::DefaultDeleter<TempWindow>;
    
    TempWindow();
    ~TempWindow();
    
    NSWindow* window_;
    
    DISALLOW_COPY_AND_ASSIGN(TempWindow);
  };
}  // namespace client

#endif  // CEF_TESTS_CEFCLIENT_BROWSER_TEMP_WINDOW_H_

