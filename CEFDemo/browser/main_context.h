// Copyright (c) 2015 The Chromium Embedded Framework Authors. All rights
// reserved. Use of this source code is governed by a BSD-style license that
// can be found in the LICENSE file.

#ifndef CEF_TESTS_CEFCLIENT_BROWSER_MAIN_CONTEXT_H_
#define CEF_TESTS_CEFCLIENT_BROWSER_MAIN_CONTEXT_H_
#pragma once

#import "utils.h"
#import "root_window_manager.h"

namespace client {  
  // Used to store global context in the browser process. The methods of this
  // class are thread-safe unless otherwise indicated.
  class MainContext {
  public:
    // Returns the singleton instance of this object.
    static MainContext* Get();
    
    MainContext(CefRefPtr<CefCommandLine> command_line,
                    bool terminate_when_all_windows_closed);
    
    // MainContext members.
    std::string GetConsoleLogPath();
    std::string GetDownloadPath(const std::string& file_name);
    std::string GetAppWorkingDirectory();
    std::string GetMainURL();
    cef_color_t GetBackgroundColor();
    void PopulateSettings(CefSettings* settings);
    void PopulateBrowserSettings(CefBrowserSettings* settings);
    RootWindowManager* GetRootWindowManager();
    
    // Initialize CEF and associated main context state. This method must be
    // called on the same thread that created this object.
    bool Initialize(const CefMainArgs& args,
                    const CefSettings& settings,
                    CefRefPtr<CefApp> application,
                    void* windows_sandbox_info);
    
    // Shut down CEF and associated context state. This method must be called on
    // the same thread that created this object.
    void Shutdown();
    
  private:
    // Allow deletion via scoped_ptr only.
    friend struct base::DefaultDeleter<MainContext>;
    
    // Returns true if the context is in a valid state (initialized and not yet
    // shut down).
    bool InValidState() const { return initialized_ && !shutdown_; }
    
    CefRefPtr<CefCommandLine> command_line_;
    const bool terminate_when_all_windows_closed_;
    
    // Track context state. Accessing these variables from multiple threads is
    // safe because only a single thread will exist at the time that they're set
    // (during context initialization and shutdown).
    bool initialized_;
    bool shutdown_;
    
    std::string main_url_;
    cef_color_t background_color_;
    cef_color_t browser_background_color_;
    
    scoped_ptr<RootWindowManager> root_window_manager_;

    // Used to verify that methods are called on the correct thread.
    base::ThreadChecker thread_checker_;
    
    DISALLOW_COPY_AND_ASSIGN(MainContext);
    
  protected:
    MainContext();
    virtual ~MainContext();
  };
}  // namespace client

#endif  // CEF_TESTS_CEFCLIENT_BROWSER_MAIN_CONTEXT_H_

