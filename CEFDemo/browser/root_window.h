#ifndef CEF_ROOT_WINDOW_MAC_H_
#define CEF_ROOT_WINDOW_MAC_H_
#pragma once
#import "utils.h"
#import "browser_window.h"

namespace client {
  typedef std::set<CefRefPtr<CefExtension>> ExtensionSet;
  
  // OS X implementation of a top-level native window in the browser process.
  // The methods of this class must be called on the main thread unless otherwise
  // indicated.
  class RootWindow: public base::RefCountedThreadSafe<RootWindow, DeleteOnMainThread>, public BrowserWindow::Delegate {
  public:
    enum ShowMode {
      ShowNormal,
      ShowMinimized,
      ShowMaximized,
      ShowNoActivate,
    };
        
    // This interface is implemented by the owner of the RootWindow. The methods
    // of this class will be called on the main thread.
    class Delegate {
    public:
      // Called to retrieve the CefRequestContext for browser. Only called for
      // non-popup browsers. May return NULL.
      virtual CefRefPtr<CefRequestContext> GetRequestContext(RootWindow* root_window) = 0;
      
      // Returns the ImageCache.
      virtual CefRefPtr<ImageCache> GetImageCache() = 0;
      
      // Called to exit the application.
      virtual void OnExit(RootWindow* root_window) = 0;
      
      // Called when the RootWindow has been destroyed.
      virtual void OnRootWindowDestroyed(RootWindow* root_window) = 0;
      
      // Called when the RootWindow is activated (becomes the foreground window).
      virtual void OnRootWindowActivated(RootWindow* root_window) = 0;
      
      // Called when the browser is created for the RootWindow.
      virtual void OnBrowserCreated(RootWindow* root_window,
                                    CefRefPtr<CefBrowser> browser) = 0;
      
      // Create a window for |extension|.
      virtual void CreateExtensionWindow(CefRefPtr<CefExtension> extension) = 0;
    protected:
      virtual ~Delegate() {}
    };
    
    // Create a new RootWindow object. This method may be called on any thread.
    // Use RootWindowManager::CreateRootWindow() or CreateRootWindowAsPopup()
    // instead of calling this method directly. |use_views| will be true if the
    // Views framework should be used.
    static CefRefPtr<RootWindow> Create();
    
    // Returns the RootWindow associated with the specified |browser_id|. Must be
    // called on the main thread.
    static CefRefPtr<RootWindow> GetForBrowser(int browser_id);
    
    // Returns the RootWindow associated with the specified |window|. Must be
    // called on the main thread.
    static CefRefPtr<RootWindow> GetForNSWindow(NSWindow* window);
    
    // Constructor may be called on any thread.
    RootWindow();
    ~RootWindow();
    
    // RootWindow methods.
    // Initialize as a normal window. This will create and show a native window
    // hosting a single browser instance. This method may be called on any thread.
    // |delegate| must be non-NULL and outlive this object.
    // Use RootWindowManager::CreateRootWindow() instead of calling this method
    // directly.
    void Init(RootWindow::Delegate* delegate,
              const WindowType window_type,
              const bool with_extension,
              const std::string url,
              const CefBrowserSettings& settings);
    
    // Initialize as a popup window. This is used to attach a new native window to
    // a single browser instance that will be created later. The native window
    // will be created and shown once the browser is available. This method may be
    // called on any thread. |delegate| must be non-NULL and outlive this object.
    // Use RootWindowManager::CreateRootWindowAsPopup() instead of calling this
    // method directly. Called on the UI thread.
    void InitAsPopup(RootWindow::Delegate* delegate,
                     WindowType window_type,
                     const CefPopupFeatures& popupFeatures,
                     CefWindowInfo& windowInfo,
                     CefRefPtr<CefClient>& client,
                     CefBrowserSettings& settings);
    
    
    
    // Show the window.
    void Show(ShowMode mode);
    
    // Hide the window.
    void Hide();
    
    // Set the window bounds in screen coordinates.
    void SetBounds(int x, int y, size_t width, size_t height);
    
    // Close the window. If |force| is true onunload handlers will not be
    // executed.
    void Close(bool force);
    
    // Returns the browser that this window contains, if any.
    CefRefPtr<CefBrowser> GetBrowser() const;
    
    // Returns the native handle for this window, if any.
    ClientWindowHandle GetWindowHandle() const;
    
    // Returns true if this window is hosting an extension app.
    bool WithExtension() const;
    
    // Called when the set of loaded extensions changes. The default
    // implementation will create a single window instance for each extension.
    virtual void OnExtensionsChanged(const ExtensionSet& extensions);
    
    // Called by RootWindowDelegate after the associated NSWindow has been
    // destroyed.
    void WindowDestroyed();
    
    BrowserWindow* browser_window() const { return browser_window_.get(); }
    RootWindow::Delegate* delegate() const { return delegate_; }
  private:
    void CreateBrowserWindow(const std::string& startup_url);
    void CreateRootWindow(const CefBrowserSettings& settings);
    
    // BrowserWindow::Delegate methods.
    void OnBrowserCreated(CefRefPtr<CefBrowser> browser) OVERRIDE;
    void OnBrowserWindowDestroyed() OVERRIDE;
    void OnSetAddress(const std::string& url) OVERRIDE;
    void OnSetTitle(const std::string& title) OVERRIDE;
    void OnSetFavicon(CefRefPtr<CefImage> image) OVERRIDE;
    void OnSetFullscreen(bool fullscreen) OVERRIDE;
    void OnAutoResize(const CefSize& new_size) OVERRIDE;
    void OnSetLoadingState(bool isLoading,
                           bool canGoBack,
                           bool canGoForward) OVERRIDE;
    void OnSetDraggableRegions(
                               const std::vector<CefDraggableRegion>& regions) OVERRIDE;
    
    void NotifyDestroyedIfDone();
    
    // After initialization all members are only accessed on the main thread.
    // Members set during initialization.
    WindowType window_type_;
    bool with_extension_;
    bool is_popup_;
    CefRect start_rect_;
    scoped_ptr<BrowserWindow> browser_window_;
    bool initialized_;
    
    // Main window.
    NSWindow* window_;
    
    // Buttons.
    NSButton* back_button_;
    NSButton* forward_button_;
    NSButton* reload_button_;
    NSButton* stop_button_;
    
    // URL text field.
    NSTextField* url_textfield_;
    
    bool window_destroyed_;
    bool browser_destroyed_;
    
    Delegate* delegate_;
    
    DISALLOW_COPY_AND_ASSIGN(RootWindow);
  };
  
}  // namespace client

#endif  // CEF_ROOT_WINDOW_MAC_H_


