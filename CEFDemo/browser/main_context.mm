// Copyright (c) 2015 The Chromium Embedded Framework Authors. All rights
// reserved. Use of this source code is governed by a BSD-style license that
// can be found in the LICENSE file.

#import "main_context.h"

namespace client {
  namespace {
    // The default URL to load in a browser window.
    const char kDefaultUrl[] = "http://www.google.com";
    
    MainContext* g_main_context = NULL;
  }  // namespace
  
  // static
  MainContext* MainContext::Get() {
    DCHECK(g_main_context);
    return g_main_context;
  }
  
  MainContext::MainContext(CefRefPtr<CefCommandLine> command_line, bool terminate_when_all_windows_closed)
  : command_line_(command_line),
  terminate_when_all_windows_closed_(terminate_when_all_windows_closed),
  initialized_(false),
  shutdown_(false) {
    DCHECK(!g_main_context);
    DCHECK(command_line_.get());
    
    g_main_context = this;
    
    // Set the main URL.
    if (command_line_->HasSwitch(switches::kUrl)) {
      main_url_ = command_line_->GetSwitchValue(switches::kUrl);
    }
    
    if (main_url_.empty()) {
      main_url_ = kDefaultUrl;
    }
    
    const std::string& cdm_path = command_line_->GetSwitchValue(switches::kWidevineCdmPath);
    if (!cdm_path.empty()) {
      // Register the Widevine CDM at the specified path. See comments in
      // cef_web_plugin.h for details. It's safe to call this method before
      // CefInitialize(), and calling it before CefInitialize() is required on
      // Linux.
      CefRegisterWidevineCdm(cdm_path, NULL);
    }
  }
  
  MainContext::~MainContext() {
    // The context must either not have been initialized, or it must have also
    // been shut down.
    DCHECK(!initialized_ || shutdown_);
    g_main_context = NULL;
  }
  
  std::string MainContext::GetConsoleLogPath() {
    return GetAppWorkingDirectory() + "console.log";
  }
  
  std::string MainContext::GetMainURL() {
    return main_url_;
  }
  
  void MainContext::PopulateSettings(CefSettings* settings) {
    CefString(&settings->cache_path) = command_line_->GetSwitchValue(switches::kCachePath);
  }
  
  void MainContext::PopulateBrowserSettings(CefBrowserSettings* settings) {
    // empty
  }
  
  RootWindowManager* MainContext::GetRootWindowManager() {
    DCHECK(InValidState());
    return root_window_manager_.get();
  }
  
  bool MainContext::Initialize(const CefMainArgs& args,
                               const CefSettings& settings,
                               CefRefPtr<CefApp> application,
                               void* windows_sandbox_info) {
    DCHECK(thread_checker_.CalledOnValidThread());
    DCHECK(!initialized_);
    DCHECK(!shutdown_);
    
    if (!CefInitialize(args, settings, application, windows_sandbox_info)) {
      return false;
    }
    
    // Need to create the RootWindowManager after calling CefInitialize because
    // TempWindowX11 uses cef_get_xdisplay().
    root_window_manager_.reset(new RootWindowManager(terminate_when_all_windows_closed_));
    initialized_ = true;
    return true;
  }
  
  void MainContext::Shutdown() {
    DCHECK(thread_checker_.CalledOnValidThread());
    DCHECK(initialized_);
    DCHECK(!shutdown_);
    
    root_window_manager_.reset();
    CefShutdown();
    shutdown_ = true;
  }
  
  std::string MainContext::GetDownloadPath(const std::string& file_name) {
    return std::string();
  }
  
  std::string MainContext::GetAppWorkingDirectory() {
    char szWorkingDir[256];
    if (getcwd(szWorkingDir, sizeof(szWorkingDir) - 1) == NULL) {
      szWorkingDir[0] = 0;
    } else {
      // Add trailing path separator.
      size_t len = strlen(szWorkingDir);
      szWorkingDir[len] = '/';
      szWorkingDir[len + 1] = 0;
    }
    return szWorkingDir;
  }
}  // namespace client

