#include "browser_manager.h"

namespace client {
  namespace {
    // The default URL to load in a browser window.
    BrowserManager* g_browser_manager = NULL;
    
    class ClientRequestContextHandler : public CefRequestContextHandler,
    public CefExtensionHandler {
    public:
      ClientRequestContextHandler() {
        CefRefPtr<CefCommandLine> command_line = CefCommandLine::GetGlobalCommandLine();
        if (command_line->HasSwitch(switches::kRequestContextBlockCookies)) {
          // Use a cookie manager that neither stores nor retrieves cookies.
          cookie_manager_ = CefCookieManager::GetBlockingManager();
        }
      }
      
      // CefRequestContextHandler methods:
      bool OnBeforePluginLoad(const CefString& mime_type,
                              const CefString& plugin_url,
                              bool is_main_frame,
                              const CefString& top_origin_url,
                              CefRefPtr<CefWebPluginInfo> plugin_info,
                              PluginPolicy* plugin_policy) OVERRIDE {
        // Always allow the PDF plugin to load.
        if (*plugin_policy != PLUGIN_POLICY_ALLOW && mime_type == "application/pdf") {
          *plugin_policy = PLUGIN_POLICY_ALLOW;
          return true;
        }
        
        return false;
      }
      
      void OnRequestContextInitialized(CefRefPtr<CefRequestContext> request_context) OVERRIDE {
        CEF_REQUIRE_UI_THREAD();
        
        CefRefPtr<CefCommandLine> command_line = CefCommandLine::GetGlobalCommandLine();
        if (command_line->HasSwitch(switches::kLoadExtension)) {
          // Load one or more extension paths specified on the command-line and
          // delimited with semicolon.
          const std::string& extension_path = command_line->GetSwitchValue(switches::kLoadExtension);
          if (!extension_path.empty()) {
            std::string part;
            std::istringstream f(extension_path);
            while (getline(f, part, ';')) {
              if (!part.empty()) {
                utils::LoadExtension(request_context, part, this);
              }
            }
          }
        }
      }
      
      CefRefPtr<CefCookieManager> GetCookieManager() OVERRIDE {
        return cookie_manager_;
      }
      
      // CefExtensionHandler methods:
      void OnExtensionLoaded(CefRefPtr<CefExtension> extension) OVERRIDE {
        CEF_REQUIRE_UI_THREAD();
        BrowserManager::Get()->AddExtension(extension);
      }
      
      CefRefPtr<CefBrowser> GetActiveBrowser(CefRefPtr<CefExtension> extension,
                                             CefRefPtr<CefBrowser> browser,
                                             bool include_incognito) OVERRIDE {
        CEF_REQUIRE_UI_THREAD();
        
        // Return the browser for the active/foreground window.
        CefRefPtr<CefBrowser> active_browser = BrowserManager::Get()->GetActiveBrowser();
        if (!active_browser) {
          LOG(WARNING) << "No active browser available for extension " << browser->GetHost()->GetExtension()->GetIdentifier().ToString();
        } else {
          // The active browser should not be hosting an extension.
          DCHECK(!active_browser->GetHost()->GetExtension());
        }
        return active_browser;
      }
    private:
      CefRefPtr<CefCookieManager> cookie_manager_;
      
      IMPLEMENT_REFCOUNTING(ClientRequestContextHandler);
      DISALLOW_COPY_AND_ASSIGN(ClientRequestContextHandler);
    };
  }  // namespace
  
  // static
  BrowserManager* BrowserManager::Get() {
    DCHECK(g_browser_manager);
    return g_browser_manager;
  }
  
  BrowserManager::BrowserManager(CefRefPtr<CefCommandLine> command_line,
                                 const CefMainArgs& args,
                                 const CefSettings& settings,
                                 CefRefPtr<CefApp> application,
                                 void* windows_sandbox_info)
  : command_line_(command_line),
  image_cache_(new ImageCache),
  shutdown_(false) {
    DCHECK(!g_browser_manager);
    DCHECK(command_line_.get());
    DCHECK(thread_checker_.CalledOnValidThread());
    DCHECK(!shutdown_);
    
    g_browser_manager = this;
    initialized_ = CefInitialize(args, settings, application, windows_sandbox_info);
    
    const std::string& cdm_path = command_line_->GetSwitchValue(switches::kWidevineCdmPath);
    if (!cdm_path.empty()) {
      // Register the Widevine CDM at the specified path. See comments in
      // cef_web_plugin.h for details. It's safe to call this method before
      // CefInitialize(), and calling it before CefInitialize() is required on
      // Linux.
      CefRegisterWidevineCdm(cdm_path, NULL);
    }
  }
  
  BrowserManager::~BrowserManager() {
    // All root windows should already have been destroyed.
    DCHECK(root_windows_.empty());
    
    // The context must either not have been initialized, or it must have also
    // been shut down.
    DCHECK(!initialized_ || shutdown_);
    g_browser_manager = NULL;
  }
  
  std::string BrowserManager::GetConsoleLogPath() {
    return GetAppWorkingDirectory() + "console.log";
  }
  
  void BrowserManager::Shutdown() {
    DCHECK(thread_checker_.CalledOnValidThread());
    DCHECK(initialized_);
    DCHECK(!shutdown_);
    
    CefShutdown();
    shutdown_ = true;
  }
  
  std::string BrowserManager::GetDownloadPath(const std::string& file_name) {
    return std::string();
  }
  
  std::string BrowserManager::GetAppWorkingDirectory() {
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
  
  

  CefRefPtr<RootWindow> BrowserManager::CreateRootWindow(const WindowType window_type,
                                                            const bool with_extension,
                                                            const std::string url) {
    CefBrowserSettings settings;
    
    CefRefPtr<RootWindow> root_window = new RootWindow();
    root_window->Init(this, window_type, with_extension,  url, settings);
    
    // Store a reference to the root window on the main thread.
    OnRootWindowCreated(root_window);
    
    return root_window;
  }
  
  CefRefPtr<RootWindow> BrowserManager::CreateRootWindowAsPopup(WindowType window_type,
                                                                   const CefPopupFeatures& popupFeatures,
                                                                   CefWindowInfo& windowInfo,
                                                                   CefRefPtr<CefClient>& client,
                                                                   CefBrowserSettings& settings) {
    CEF_REQUIRE_UI_THREAD();
    
    if (!temp_window_) {
      // TempWindow must be created on the UI thread.
      temp_window_.reset(new TempWindow());
    }
    
    CefRefPtr<RootWindow> root_window = new RootWindow();
    root_window->InitAsPopup(this, window_type, popupFeatures, windowInfo, client, settings);
    
    // Store a reference to the root window on the main thread.
    OnRootWindowCreated(root_window);
    
    return root_window;
  }
  
  CefRefPtr<RootWindow> BrowserManager::CreateRootWindowAsExtension(CefRefPtr<CefExtension> extension, WindowType window_type) {
    const std::string& extension_url = utils::GetExtensionURL(extension);
    if (extension_url.empty()) {
      NOTREACHED() << "Extension cannot be loaded directly.";
      return NULL;
    }
    
    // Create an initially hidden browser window that loads the extension URL.
    // We'll show the window when the desired size becomes available via
    // ClientHandler::OnAutoResize.
    return CreateRootWindow(window_type, true, extension_url);
  }
  
  bool BrowserManager::HasRootWindowAsExtension(CefRefPtr<CefExtension> extension) {
    REQUIRE_MAIN_THREAD();
    
    RootWindowSet::const_iterator it = root_windows_.begin();
    for (; it != root_windows_.end(); ++it) {
      const RootWindow* root_window = (*it);
      if (!root_window->WithExtension()) {
        continue;
      }
      
      CefRefPtr<CefBrowser> browser = root_window->GetBrowser();
      if (!browser) {
        continue;
      }
      
      CefRefPtr<CefExtension> browser_extension = browser->GetHost()->GetExtension();
      DCHECK(browser_extension);
      if (browser_extension->GetIdentifier() == extension->GetIdentifier()) {
        return true;
      }
    }
    
    return false;
  }
  
  CefRefPtr<RootWindow> BrowserManager::GetActiveRootWindow() const {
    REQUIRE_MAIN_THREAD();
    return active_root_window_;
  }
  
  CefRefPtr<CefBrowser> BrowserManager::GetActiveBrowser() const {
    base::AutoLock lock_scope(active_browser_lock_);
    return active_browser_;
  }
  
  void BrowserManager::CloseAllWindows(bool force) {
    if (!CURRENTLY_ON_MAIN_THREAD()) {
      // Execute this method on the main thread.
      MAIN_POST_CLOSURE(base::Bind(&BrowserManager::CloseAllWindows, base::Unretained(this), force));
      return;
    }
    
    if (root_windows_.empty()) {
      return;
    }
    
    // Use a copy of |root_windows_| because the original set may be modified
    // in OnRootWindowDestroyed while iterating.
    RootWindowSet root_windows = root_windows_;
    
    RootWindowSet::const_iterator it = root_windows.begin();
    for (; it != root_windows.end(); ++it) {
      (*it)->Close(force);
    }
  }
  
  void BrowserManager::AddExtension(CefRefPtr<CefExtension> extension) {
    if (!CURRENTLY_ON_MAIN_THREAD()) {
      // Execute this method on the main thread.
      MAIN_POST_CLOSURE(base::Bind(&BrowserManager::AddExtension,  base::Unretained(this), extension));
      return;
    }
    
    // Don't track extensions that can't be loaded directly.
    if (utils::GetExtensionURL(extension).empty()) {
      return;
    }
    
    // Don't add the same extension multiple times.
    ExtensionSet::const_iterator it = extensions_.begin();
    for (; it != extensions_.end(); ++it) {
      if ((*it)->GetIdentifier() == extension->GetIdentifier()) {
        return;
      }
    }
    
    extensions_.insert(extension);
    NotifyExtensionsChanged();
  }
  
  void BrowserManager::OnRootWindowCreated(CefRefPtr<RootWindow> root_window) {
    if (!CURRENTLY_ON_MAIN_THREAD()) {
      // Execute this method on the main thread.
      MAIN_POST_CLOSURE(base::Bind(&BrowserManager::OnRootWindowCreated, base::Unretained(this), root_window));
      return;
    }
    
    root_windows_.insert(root_window);
    if (!root_window->WithExtension()) {
      root_window->OnExtensionsChanged(extensions_);
      
      if (root_windows_.size() == 1U) {
        // The first non-extension root window should be considered the active
        // window.
        OnRootWindowActivated(root_window);
      }
    }
  }
  
  void BrowserManager::NotifyExtensionsChanged() {
    REQUIRE_MAIN_THREAD();
    
    RootWindowSet::const_iterator it = root_windows_.begin();
    for (; it != root_windows_.end(); ++it) {
      RootWindow* root_window = *it;
      if (!root_window->WithExtension()) {
        root_window->OnExtensionsChanged(extensions_);
      }
    }
  }
  
  CefRefPtr<CefRequestContext> BrowserManager::GetRequestContext(RootWindow* root_window) {
    REQUIRE_MAIN_THREAD();
    
    // All browsers will share the global request context.
    if (!shared_request_context_.get()) {
      shared_request_context_ = CefRequestContext::CreateContext(CefRequestContext::GetGlobalContext(), new ClientRequestContextHandler);
    }
    return shared_request_context_;
  }
  
  CefRefPtr<ImageCache> BrowserManager::GetImageCache() {
    REQUIRE_MAIN_THREAD();
    return image_cache_;
  }
  
  void BrowserManager::OnExit(RootWindow* root_window) {
    REQUIRE_MAIN_THREAD();
    CloseAllWindows(false);
  }
  
  void BrowserManager::OnRootWindowDestroyed(RootWindow* root_window) {
    REQUIRE_MAIN_THREAD();
    
    RootWindowSet::iterator it = root_windows_.find(root_window);
    DCHECK(it != root_windows_.end());
    if (it != root_windows_.end()) {
      root_windows_.erase(it);
    }
    
    if (root_window == active_root_window_) {
      active_root_window_ = NULL;
      
      base::AutoLock lock_scope(active_browser_lock_);
      active_browser_ = NULL;
    }
    
    if (root_windows_.empty()) {
      // All windows have closed. Clean up on the UI thread.
      CefPostTask(TID_UI, base::Bind(&BrowserManager::CleanupOnUIThread, base::Unretained(this)));
    }
  }
  
  void BrowserManager::OnRootWindowActivated(RootWindow* root_window) {
    REQUIRE_MAIN_THREAD();
    
    if (root_window->WithExtension()) {
      // We don't want extension apps to become the active RootWindow.
      return;
    }
    
    if (root_window == active_root_window_) {
      return;
    }
    
    active_root_window_ = root_window;
    
    base::AutoLock lock_scope(active_browser_lock_);
    // May be NULL at this point, in which case we'll make the association in
    // OnBrowserCreated.
    active_browser_ = active_root_window_->GetBrowser();
  }
  
  void BrowserManager::OnBrowserCreated(RootWindow* root_window,
                                           CefRefPtr<CefBrowser> browser) {
    REQUIRE_MAIN_THREAD();
    
    if (root_window == active_root_window_) {
      base::AutoLock lock_scope(active_browser_lock_);
      active_browser_ = browser;
    }
  }
  
  void BrowserManager::CreateExtensionWindow(CefRefPtr<CefExtension> extension) {
    REQUIRE_MAIN_THREAD();
    
    if (!HasRootWindowAsExtension(extension)) {
      CreateRootWindowAsExtension(extension, WindowType_Extension);
    }
  }
  
  void BrowserManager::CleanupOnUIThread() {
    CEF_REQUIRE_UI_THREAD();
    
    if (temp_window_) {
      // TempWindow must be destroyed on the UI thread.
      temp_window_.reset(nullptr);
    }
    
    // Quit the main message loop.
    MainMessageLoop::Get()->Quit();
  }
}  // namespace client
