#ifndef CEF_CLIENT_HANDLER_H_
#define CEF_CLIENT_HANDLER_H_
#pragma once
#import "utils.h"

namespace client {
  class ClientDownloadImageCallback;
  
  // Client handler abstract base class. Provides common functionality shared by
  // all concrete client handler implementations.
  class ClientHandler : public CefClient,
  public CefContextMenuHandler,
  public CefDisplayHandler,
  public CefDownloadHandler,
  public CefDragHandler,
  public CefFocusHandler,
  public CefKeyboardHandler,
  public CefLifeSpanHandler,
  public CefLoadHandler,
  public CefRequestHandler {
  public:
    // Implement this interface to receive notification of ClientHandler
    // events. The methods of this class will be called on the main thread unless
    // otherwise indicated.
    class Delegate {
    public:
      // Called when the browser is created.
      virtual void OnBrowserCreated(CefRefPtr<CefBrowser> browser) = 0;
      
      // Called when the browser is closing.
      virtual void OnBrowserClosing(CefRefPtr<CefBrowser> browser) = 0;
      
      // Called when the browser has been closed.
      virtual void OnBrowserClosed(CefRefPtr<CefBrowser> browser) = 0;
      
      // Set the window URL address.
      virtual void OnSetAddress(const std::string& url) = 0;
      
      // Set the window title.
      virtual void OnSetTitle(const std::string& title) = 0;
      
      // Set the Favicon image.
      virtual void OnSetFavicon(CefRefPtr<CefImage> image) = 0;
      
      // Set fullscreen mode.
      virtual void OnSetFullscreen(bool fullscreen) = 0;
      
      // Auto-resize contents.
      virtual void OnAutoResize(const CefSize& new_size) = 0;
      
      // Set the loading state.
      virtual void OnSetLoadingState(bool isLoading,
                                     bool canGoBack,
                                     bool canGoForward) = 0;
      
      // Set the draggable regions.
      virtual void OnSetDraggableRegions(const std::vector<CefDraggableRegion>& regions) = 0;
      
      // Set focus to the next/previous control.
      virtual void OnTakeFocus(bool next) {}
      
      // Called on the UI thread before a context menu is displayed.
      virtual void OnBeforeContextMenu(CefRefPtr<CefMenuModel> model) {}
    protected:
      virtual ~Delegate() {}
    };

    // Constructor may be called on any thread.
    // |delegate| must outlive this object or DetachDelegate() must be called.
    ClientHandler(Delegate* delegate, const std::string& startup_url);
    
    // This object may outlive the Delegate object so it's necessary for the
    // Delegate to detach itself before destruction.
    void DetachDelegate();
    
    // CefClient methods
    CefRefPtr<CefContextMenuHandler> GetContextMenuHandler() OVERRIDE {return this;}
    CefRefPtr<CefDisplayHandler> GetDisplayHandler() OVERRIDE { return this; }
    CefRefPtr<CefDownloadHandler> GetDownloadHandler() OVERRIDE { return this; }
    CefRefPtr<CefDragHandler> GetDragHandler() OVERRIDE { return this; }
    CefRefPtr<CefFocusHandler> GetFocusHandler() OVERRIDE { return this; }
    CefRefPtr<CefKeyboardHandler> GetKeyboardHandler() OVERRIDE { return this; }
    CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() OVERRIDE { return this; }
    CefRefPtr<CefLoadHandler> GetLoadHandler() OVERRIDE { return this; }
    CefRefPtr<CefRequestHandler> GetRequestHandler() OVERRIDE { return this; }
    bool OnProcessMessageReceived(CefRefPtr<CefBrowser> browser,
                                  CefProcessId source_process,
                                  CefRefPtr<CefProcessMessage> message) OVERRIDE;
    
    // CefContextMenuHandler methods
    void OnBeforeContextMenu(CefRefPtr<CefBrowser> browser,
                             CefRefPtr<CefFrame> frame,
                             CefRefPtr<CefContextMenuParams> params,
                             CefRefPtr<CefMenuModel> model) OVERRIDE;
    bool OnContextMenuCommand(CefRefPtr<CefBrowser> browser,
                              CefRefPtr<CefFrame> frame,
                              CefRefPtr<CefContextMenuParams> params,
                              int command_id,
                              EventFlags event_flags) OVERRIDE;
    
    // CefDisplayHandler methods
    void OnAddressChange(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, const CefString& url) OVERRIDE;
    void OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString& title) OVERRIDE;
    void OnFaviconURLChange(CefRefPtr<CefBrowser> browser, const std::vector<CefString>& icon_urls) OVERRIDE;
    void OnFullscreenModeChange(CefRefPtr<CefBrowser> browser, bool fullscreen) OVERRIDE;
    bool OnConsoleMessage(CefRefPtr<CefBrowser> browser,
                          cef_log_severity_t level,
                          const CefString& message,
                          const CefString& source,
                          int line) OVERRIDE;
    bool OnAutoResize(CefRefPtr<CefBrowser> browser, const CefSize& new_size) OVERRIDE;
    
    // CefDownloadHandler methods
    void OnBeforeDownload(CefRefPtr<CefBrowser> browser,
                          CefRefPtr<CefDownloadItem> download_item,
                          const CefString& suggested_name,
                          CefRefPtr<CefBeforeDownloadCallback> callback) OVERRIDE;
    void OnDownloadUpdated(CefRefPtr<CefBrowser> browser,
                           CefRefPtr<CefDownloadItem> download_item,
                           CefRefPtr<CefDownloadItemCallback> callback) OVERRIDE;
    
    // CefDragHandler methods
    bool OnDragEnter(CefRefPtr<CefBrowser> browser,
                     CefRefPtr<CefDragData> dragData,
                     CefDragHandler::DragOperationsMask mask) OVERRIDE;
    void OnDraggableRegionsChanged(CefRefPtr<CefBrowser> browser, const std::vector<CefDraggableRegion>& regions) OVERRIDE;
    
    // CefFocusHandler methods
    void OnTakeFocus(CefRefPtr<CefBrowser> browser, bool next) OVERRIDE;
    bool OnSetFocus(CefRefPtr<CefBrowser> browser, FocusSource source) OVERRIDE;
    
    // CefKeyboardHandler methods
    bool OnPreKeyEvent(CefRefPtr<CefBrowser> browser,
                       const CefKeyEvent& event,
                       CefEventHandle os_event,
                       bool* is_keyboard_shortcut) OVERRIDE;
    
    // CefLifeSpanHandler methods
    bool OnBeforePopup(CefRefPtr<CefBrowser> browser,
                       CefRefPtr<CefFrame> frame,
                       const CefString& target_url,
                       const CefString& target_frame_name,
                       CefLifeSpanHandler::WindowOpenDisposition target_disposition,
                       bool user_gesture,
                       const CefPopupFeatures& popupFeatures,
                       CefWindowInfo& windowInfo,
                       CefRefPtr<CefClient>& client,
                       CefBrowserSettings& settings,
                       bool* no_javascript_access) OVERRIDE;
    void OnAfterCreated(CefRefPtr<CefBrowser> browser) OVERRIDE;
    bool DoClose(CefRefPtr<CefBrowser> browser) OVERRIDE;
    void OnBeforeClose(CefRefPtr<CefBrowser> browser) OVERRIDE;
    
    // CefLoadHandler methods
    void OnLoadingStateChange(CefRefPtr<CefBrowser> browser,
                              bool isLoading,
                              bool canGoBack,
                              bool canGoForward) OVERRIDE;
    void OnLoadError(CefRefPtr<CefBrowser> browser,
                     CefRefPtr<CefFrame> frame,
                     ErrorCode errorCode,
                     const CefString& errorText,
                     const CefString& failedUrl) OVERRIDE;
    
    // CefRequestHandler methods
    bool OnBeforeBrowse(CefRefPtr<CefBrowser> browser,
                        CefRefPtr<CefFrame> frame,
                        CefRefPtr<CefRequest> request,
                        bool user_gesture,
                        bool is_redirect) OVERRIDE;
    bool OnOpenURLFromTab(CefRefPtr<CefBrowser> browser,
                          CefRefPtr<CefFrame> frame,
                          const CefString& target_url,
                          CefRequestHandler::WindowOpenDisposition target_disposition,
                          bool user_gesture) OVERRIDE;
    cef_return_value_t OnBeforeResourceLoad(CefRefPtr<CefBrowser> browser,
                                            CefRefPtr<CefFrame> frame,
                                            CefRefPtr<CefRequest> request,
                                            CefRefPtr<CefRequestCallback> callback) OVERRIDE;
    CefRefPtr<CefResourceHandler> GetResourceHandler(CefRefPtr<CefBrowser> browser,
                                                     CefRefPtr<CefFrame> frame,
                                                     CefRefPtr<CefRequest> request) OVERRIDE;
    bool OnQuotaRequest(CefRefPtr<CefBrowser> browser,
                        const CefString& origin_url,
                        int64 new_size,
                        CefRefPtr<CefRequestCallback> callback) OVERRIDE;
    void OnProtocolExecution(CefRefPtr<CefBrowser> browser,
                             const CefString& url,
                             bool& allow_os_execution) OVERRIDE;
    bool OnCertificateError(CefRefPtr<CefBrowser> browser,
                            ErrorCode cert_error,
                            const CefString& request_url,
                            CefRefPtr<CefSSLInfo> ssl_info,
                            CefRefPtr<CefRequestCallback> callback) OVERRIDE;
    bool OnSelectClientCertificate(CefRefPtr<CefBrowser> browser,
                                   bool isProxy,
                                   const CefString& host,
                                   int port,
                                   const X509CertificateList& certificates,
                                   CefRefPtr<CefSelectClientCertificateCallback> callback) OVERRIDE;
    
    // Returns the number of browsers currently using this handler. Can only be
    // called on the CEF UI thread.
    int GetBrowserCount() const;
    
    // Show a new DevTools popup window.
    void ShowDevTools(CefRefPtr<CefBrowser> browser, const CefPoint& inspect_element_at);
    
    // Close the existing DevTools popup window, if any.
    void CloseDevTools(CefRefPtr<CefBrowser> browser);
    
    // Test if the current site has SSL information available.
    bool HasSSLInformation(CefRefPtr<CefBrowser> browser);
    
    // Returns the Delegate.
    Delegate* delegate() const { return delegate_; }
    
    // Returns the startup URL.
    std::string startup_url() const { return startup_url_; }
  private:
    friend class ClientDownloadImageCallback;
    
    // Show SSL information for the current site.
    void ShowSSLInformation(CefRefPtr<CefBrowser> browser);
    
    // Execute Delegate notifications on the main thread.
    void NotifyBrowserCreated(CefRefPtr<CefBrowser> browser);
    void NotifyBrowserClosing(CefRefPtr<CefBrowser> browser);
    void NotifyBrowserClosed(CefRefPtr<CefBrowser> browser);
    void NotifyAddress(const CefString& url);
    void NotifyTitle(const CefString& title);
    void NotifyFavicon(CefRefPtr<CefImage> image);
    void NotifyFullscreen(bool fullscreen);
    void NotifyAutoResize(const CefSize& new_size);
    void NotifyLoadingState(bool isLoading, bool canGoBack, bool canGoForward);
    void NotifyDraggableRegions(const std::vector<CefDraggableRegion>& regions);
    void NotifyTakeFocus(bool next);
    
    // THREAD SAFE MEMBERS
    // The following members may be accessed from any thread.
    
    // The startup URL.
    const std::string startup_url_;
    
    // True if mouse cursor change is disabled.
    bool mouse_cursor_change_disabled_;
    
    // Manages the registration and delivery of resources.
    CefRefPtr<CefResourceManager> resource_manager_;
    
    // MAIN THREAD MEMBERS
    // The following members will only be accessed on the main thread. This will
    // be the same as the CEF UI thread except when using multi-threaded message
    // loop mode on Windows.
    Delegate* delegate_;
    
    // UI THREAD MEMBERS
    // The following members will only be accessed on the CEF UI thread.
    
    // The current number of browsers using this handler.
    int browser_count_;
    
    // Console logging state.
    const std::string console_log_file_;
    bool first_console_message_;
    
    // True if an editable field currently has focus.
    bool focus_on_editable_field_;
    
    // True for the initial navigation after browser creation.
    bool initial_navigation_;
    
    IMPLEMENT_REFCOUNTING(ClientHandler);
    DISALLOW_COPY_AND_ASSIGN(ClientHandler);
  };
}  // namespace client

#endif  // CEF_CLIENT_HANDLER_H_
