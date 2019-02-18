// Copyright (c) 2015 The Chromium Embedded Framework Authors. All rights
// reserved. Use of this source code is governed by a BSD-style license that
// can be found in the LICENSE file.

#ifndef CEF_TESTS_CEFCLIENT_BROWSER_ROOT_WINDOW_MAC_H_
#define CEF_TESTS_CEFCLIENT_BROWSER_ROOT_WINDOW_MAC_H_
#pragma once

#include <set>
#include <string>

#include "include/base/cef_scoped_ptr.h"
#include "include/base/cef_ref_counted.h"
#include "include/base/cef_callback_forward.h"


#include "include/cef_browser.h"
#include "include/views/cef_window.h"
#include "browser/image_cache.h"
#include "browser/main_message_loop.h"

#include "browser/browser_window.h"
#include "browser/utils.h"

#ifdef __OBJC__
@class NSWindow;
@class NSButton;
@class NSTextField;
#else
class NSWindow;
class NSButton;
class NSTextField;
#endif

namespace client {
  // Used to configure how a RootWindow is created.
  struct RootWindowConfig {
    RootWindowConfig();
    
    // If true the window will always display above other windows.
    bool always_on_top;
    
    // If true the window will show controls.
    bool with_controls;
    
    // If true the window is hosting an extension app.
    bool with_extension;
    
    // If true the window will be created initially hidden.
    bool initially_hidden;
    
    // Requested window position. If |bounds| and |source_bounds| are empty the
    // default window size and location will be used.
    CefRect bounds;
    
    // Position of the UI element that triggered the window creation. If |bounds|
    // is empty and |source_bounds| is non-empty the new window will be positioned
    // relative to |source_bounds|. This is currently only implemented for Views-
    // based windows when |initially_hidden| is also true.
    CefRect source_bounds;
    
    // Parent window. Only used for Views-based windows.
    CefRefPtr<CefWindow> parent_window;
    
    // Callback to be executed when the window is closed. Will be executed on the
    // main thread. This is currently only implemented for Views-based windows.
    base::Closure close_callback;
    
    // Initial URL to load.
    std::string url;
  };
  
  typedef std::set<CefRefPtr<CefExtension>> ExtensionSet;
  
  
  // OS X implementation of a top-level native window in the browser process.
  // The methods of this class must be called on the main thread unless otherwise
  // indicated.
  class RootWindow :
    public base::RefCountedThreadSafe<RootWindow, DeleteOnMainThread>,
    public BrowserWindow::Delegate {
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
        virtual CefRefPtr<CefRequestContext> GetRequestContext(
                                                               RootWindow* root_window) = 0;
        
        // Returns the ImageCache.
        virtual scoped_refptr<ImageCache> GetImageCache() = 0;
        
        // Called to exit the application.
        virtual void OnExit(RootWindow* root_window) = 0;
        
        // Called when the RootWindow has been destroyed.
        virtual void OnRootWindowDestroyed(RootWindow* root_window) = 0;
        
        // Called when the RootWindow is activated (becomes the foreground window).
        virtual void OnRootWindowActivated(RootWindow* root_window) = 0;
        
        // Called when the browser is created for the RootWindow.
        virtual void OnBrowserCreated(RootWindow* root_window,
                                      CefRefPtr<CefBrowser> browser) = 0;
        
        // Create a window for |extension|. |source_bounds| are the bounds of the
        // UI element, like a button, that triggered the extension.
        virtual void CreateExtensionWindow(CefRefPtr<CefExtension> extension,
                                           const CefRect& source_bounds,
                                           CefRefPtr<CefWindow> parent_window,
                                           const base::Closure& close_callback) = 0;
        
      protected:
        virtual ~Delegate() {}
      };
      
      // Create a new RootWindow object. This method may be called on any thread.
      // Use RootWindowManager::CreateRootWindow() or CreateRootWindowAsPopup()
      // instead of calling this method directly. |use_views| will be true if the
      // Views framework should be used.
      static scoped_refptr<RootWindow> Create();
      
      // Returns the RootWindow associated with the specified |browser_id|. Must be
      // called on the main thread.
      static scoped_refptr<RootWindow> GetForBrowser(int browser_id);
      
      // Returns the RootWindow associated with the specified |window|. Must be
      // called on the main thread.
      static scoped_refptr<RootWindow> GetForNSWindow(NSWindow* window);
      
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
                        const RootWindowConfig& config,
                        const CefBrowserSettings& settings);
      
      // Initialize as a popup window. This is used to attach a new native window to
      // a single browser instance that will be created later. The native window
      // will be created and shown once the browser is available. This method may be
      // called on any thread. |delegate| must be non-NULL and outlive this object.
      // Use RootWindowManager::CreateRootWindowAsPopup() instead of calling this
      // method directly. Called on the UI thread.
      void InitAsPopup(RootWindow::Delegate* delegate,
                               bool with_controls,
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
      
      // Set the device scale factor. Only used in combination with off-screen
      // rendering.
      void SetDeviceScaleFactor(float device_scale_factor);
      
      // Returns the device scale factor. Only used in combination with off-screen
      // rendering.
      float GetDeviceScaleFactor() const;
      
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
      // Allow deletion via scoped_refptr only.
      friend struct DeleteOnMainThread;
      friend class base::RefCountedThreadSafe<RootWindow, DeleteOnMainThread>;
      
      
      Delegate* delegate_;
      
    void CreateBrowserWindow(const std::string& startup_url);
    void CreateRootWindow(const CefBrowserSettings& settings,
                          bool initially_hidden);
    
    // BrowserWindow::Delegate methods.
    void OnBrowserCreated(CefRefPtr<CefBrowser> browser) OVERRIDE;
    void OnBrowserWindowDestroyed() OVERRIDE;
    void OnSetAddress(const std::string& url) OVERRIDE;
    void OnSetTitle(const std::string& title) OVERRIDE;
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
    bool with_controls_;
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
    
    DISALLOW_COPY_AND_ASSIGN(RootWindow);
  };
  
}  // namespace client

#endif  // CEF_TESTS_CEFCLIENT_BROWSER_ROOT_WINDOW_MAC_H_

