#ifndef CEF_BROWSER_MANAGER_H_
#define CEF_BROWSER_MANAGER_H_
#pragma once
#import "utils.h"
#import "root_window.h"
#import "temp_window.h"

namespace client {
  class BrowserManager: public RootWindow::Delegate{
  public:
    // Returns the singleton instance of this object.
    static BrowserManager* Get();
    
    BrowserManager(CefRefPtr<CefCommandLine> command_line,
                   const CefMainArgs& args,
                   const CefSettings& settings,
                   CefRefPtr<CefApp> application,
                   void* windows_sandbox_info);
    
    // BrowserManager members.
    std::string GetConsoleLogPath();
    std::string GetDownloadPath(const std::string& file_name);
    std::string GetAppWorkingDirectory();
    
    // Create a new top-level native window. This method can be called from anywhere.
    CefRefPtr<RootWindow> CreateRootWindow(const WindowType window_type,
                                           const bool with_extension,
                                           const std::string url);
    
    // Create a new native popup window.
    // This method is called from ClientHandler::CreatePopupWindow() to
    // create a new popup or DevTools window. Must be called on the UI thread.
    CefRefPtr<RootWindow> CreateRootWindowAsPopup(WindowType window_type,
                                                  const CefPopupFeatures& popupFeatures,
                                                  CefWindowInfo& windowInfo,
                                                  CefRefPtr<CefClient>& client,
                                                  CefBrowserSettings& settings);
    
    // Create a new top-level native window to host |extension|.
    // This method can be called from anywhere.
    CefRefPtr<RootWindow> CreateRootWindowAsExtension(CefRefPtr<CefExtension> extension, WindowType window_type);
    
    // Returns true if a window hosting |extension| currently exists. Must be
    // called on the main thread.
    bool HasRootWindowAsExtension(CefRefPtr<CefExtension> extension);
    
    // Returns the currently active/foreground RootWindow. May return NULL. Must
    // be called on the main thread.
    CefRefPtr<RootWindow> GetActiveRootWindow() const;
    
    // Returns the currently active/foreground browser. May return NULL. Safe to
    // call from any thread.
    CefRefPtr<CefBrowser> GetActiveBrowser() const;
    
    // Close all existing windows. If |force| is true onunload handlers will not
    // be executed.
    void CloseAllWindows(bool force);
    
    // Manage the set of loaded extensions. RootWindows will be notified via the
    // OnExtensionsChanged method.
    void AddExtension(CefRefPtr<CefExtension> extension);
    
    // Shut down CEF and associated context state. This method must be called on
    // the same thread that created this object.
    void Shutdown();
  private:
    // Allow deletion via scoped_ptr only.
    friend struct base::DefaultDeleter<BrowserManager>;
    
    BrowserManager();
    ~BrowserManager();
    
    // Returns true if the context is in a valid state (initialized and not yet shut down.
    bool InValidState() const { return initialized_ && !shutdown_; }
    
    void OnRootWindowCreated(CefRefPtr<RootWindow> root_window);
    void NotifyExtensionsChanged();
    
    // RootWindow::Delegate methods.
    CefRefPtr<CefRequestContext> GetRequestContext(RootWindow* root_window) OVERRIDE;
    CefRefPtr<ImageCache> GetImageCache() OVERRIDE;
    void OnExit(RootWindow* root_window) OVERRIDE;
    void OnRootWindowDestroyed(RootWindow* root_window) OVERRIDE;
    void OnRootWindowActivated(RootWindow* root_window) OVERRIDE;
    void OnBrowserCreated(RootWindow* root_window, CefRefPtr<CefBrowser> browser) OVERRIDE;
    void CreateExtensionWindow(CefRefPtr<CefExtension> extension) OVERRIDE;
    
    void CleanupOnUIThread();
    
    CefRefPtr<CefCommandLine> command_line_;
    
    // Used to verify that methods are called on the correct thread.
    base::ThreadChecker thread_checker_;
    
    // Track context state. Accessing these variables from multiple threads is
    // safe because only a single thread will exist at the time that they're set
    // (during context initialization and shutdown).
    bool initialized_;
    bool shutdown_;
    
    // Existing root windows. Only accessed on the main thread.
    typedef std::set<CefRefPtr<RootWindow>> RootWindowSet;
    RootWindowSet root_windows_;
    
    // The currently active/foreground RootWindow. Only accessed on the main
    // thread.
    CefRefPtr<RootWindow> active_root_window_;
    
    // The currently active/foreground browser. Access is protected by
    // |active_browser_lock_;
    mutable base::Lock active_browser_lock_;
    CefRefPtr<CefBrowser> active_browser_;
    
    // Singleton window used as the temporary parent for popup browsers.
    scoped_ptr<TempWindow> temp_window_;
    
    CefRefPtr<CefRequestContext> shared_request_context_;
    
    // Loaded extensions. Only accessed on the main thread.
    ExtensionSet extensions_;
    
    CefRefPtr<ImageCache> image_cache_;
    

    DISALLOW_COPY_AND_ASSIGN(BrowserManager);
  };
}

#endif /* CEF_BROWSER_MANAGER_H_ */
