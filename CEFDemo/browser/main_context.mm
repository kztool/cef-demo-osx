// Copyright (c) 2015 The Chromium Embedded Framework Authors. All rights
// reserved. Use of this source code is governed by a BSD-style license that
// can be found in the LICENSE file.

#include "browser/main_context.h"

namespace client {
  
  namespace {
    MainContext* g_main_context = NULL;
    
    // The default URL to load in a browser window.
    const char kDefaultUrl[] = "http://www.google.com";
    
    // Returns the ARGB value for |color|.
    cef_color_t ParseColor(const std::string& color) {
      std::string colorToLower;
      colorToLower.resize(color.size());
      std::transform(color.begin(), color.end(), colorToLower.begin(), ::tolower);
      
      if (colorToLower == "black")
        return CefColorSetARGB(255, 0, 0, 0);
      else if (colorToLower == "blue")
        return CefColorSetARGB(255, 0, 0, 255);
      else if (colorToLower == "green")
        return CefColorSetARGB(255, 0, 255, 0);
      else if (colorToLower == "red")
        return CefColorSetARGB(255, 255, 0, 0);
      else if (colorToLower == "white")
        return CefColorSetARGB(255, 255, 255, 255);
      
      // Use the default color.
      return 0;
    }
  }  // namespace
  
  // static
  MainContext* MainContext::Get() {
    DCHECK(g_main_context);
    return g_main_context;
  }
  
  MainContext::MainContext(CefRefPtr<CefCommandLine> command_line,
                                   bool terminate_when_all_windows_closed)
  : command_line_(command_line),
  terminate_when_all_windows_closed_(terminate_when_all_windows_closed),
  initialized_(false),
  shutdown_(false),
  background_color_(0),
  browser_background_color_(0),
  windowless_frame_rate_(0),
  use_views_(false) {
    DCHECK(!g_main_context);
    DCHECK(command_line_.get());
    
    g_main_context = this;

    // Set the main URL.
    if (command_line_->HasSwitch(switches::kUrl))
      main_url_ = command_line_->GetSwitchValue(switches::kUrl);
    if (main_url_.empty())
      main_url_ = kDefaultUrl;
    
    // Whether windowless (off-screen) rendering will be used.
    use_windowless_rendering_ =
    command_line_->HasSwitch(switches::kOffScreenRenderingEnabled);
    
    if (use_windowless_rendering_ &&
        command_line_->HasSwitch(switches::kOffScreenFrameRate)) {
      windowless_frame_rate_ =
      atoi(command_line_->GetSwitchValue(switches::kOffScreenFrameRate)
           .ToString()
           .c_str());
    }
    
    // Whether transparent painting is used with windowless rendering.
    const bool use_transparent_painting =
    use_windowless_rendering_ &&
    command_line_->HasSwitch(switches::kTransparentPaintingEnabled);
    
    
    external_begin_frame_enabled_ =
    use_windowless_rendering_ &&
    command_line_->HasSwitch(switches::kExternalBeginFrameEnabled);
    
    if (windowless_frame_rate_ <= 0) {
      windowless_frame_rate_ = 30;
    }
    
    if (command_line_->HasSwitch(switches::kBackgroundColor)) {
      // Parse the background color value.
      background_color_ =
      ParseColor(command_line_->GetSwitchValue(switches::kBackgroundColor));
    }
    
    if (background_color_ == 0 && !use_views_) {
      // Set an explicit background color.
      background_color_ = CefColorSetARGB(255, 255, 255, 255);
    }
    
    // |browser_background_color_| should remain 0 to enable transparent painting.
    if (!use_transparent_painting) {
      browser_background_color_ = background_color_;
    }
    
    const std::string& cdm_path =
    command_line_->GetSwitchValue(switches::kWidevineCdmPath);
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
  
  cef_color_t MainContext::GetBackgroundColor() {
    return background_color_;
  }
  
  bool MainContext::UseViews() {
    return use_views_;
  }
  
  bool MainContext::UseWindowlessRendering() {
    return use_windowless_rendering_;
  }
  
  void MainContext::PopulateSettings(CefSettings* settings) {
    if (!settings->multi_threaded_message_loop) {
      settings->external_message_pump =
      command_line_->HasSwitch(switches::kExternalMessagePump);
    }
    
    CefString(&settings->cache_path) =
    command_line_->GetSwitchValue(switches::kCachePath);
    
    if (use_windowless_rendering_)
      settings->windowless_rendering_enabled = true;
    
    if (browser_background_color_ != 0)
      settings->background_color = browser_background_color_;
  }
  
  void MainContext::PopulateBrowserSettings(CefBrowserSettings* settings) {
    settings->windowless_frame_rate = windowless_frame_rate_;
    
    if (browser_background_color_ != 0)
      settings->background_color = browser_background_color_;
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
    
    if (!CefInitialize(args, settings, application, windows_sandbox_info))
      return false;
    
    // Need to create the RootWindowManager after calling CefInitialize because
    // TempWindowX11 uses cef_get_xdisplay().
    root_window_manager_.reset(
                               new RootWindowManager(terminate_when_all_windows_closed_));
    
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
