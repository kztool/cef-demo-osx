// Copyright (c) 2016 The Chromium Embedded Framework Authors. All rights
// reserved. Use of this source code is governed by a BSD-style license that
// can be found in the LICENSE file.

#include "browser/root_window.h"
#include "browser/root_window_mac.h"

namespace client {
  // static
  scoped_refptr<RootWindow> RootWindow::Create(bool use_views) {
    if (use_views) {
      LOG(FATAL) << "Views framework is not supported on this platform.";
    }
    
    return new RootWindowMac();
  }
}  // namespace client
