#import "browser_window.h"

namespace client {
  BrowserWindow::BrowserWindow(Delegate* delegate, const std::string& startup_url)
  : delegate_(delegate), is_closing_(false) {
    DCHECK(delegate_);
    client_handler_ = new ClientHandler(this, startup_url);
  }
  
  CefRefPtr<CefBrowser> BrowserWindow::GetBrowser() const {
    REQUIRE_MAIN_THREAD();
    return browser_;
  }
  
  bool BrowserWindow::IsClosing() const {
    REQUIRE_MAIN_THREAD();
    return is_closing_;
  }
  
  void BrowserWindow::OnBrowserCreated(CefRefPtr<CefBrowser> browser) {
    REQUIRE_MAIN_THREAD();
    DCHECK(!browser_);
    browser_ = browser;
    delegate_->OnBrowserCreated(browser);
  }
  
  void BrowserWindow::OnBrowserClosing(CefRefPtr<CefBrowser> browser) {
    REQUIRE_MAIN_THREAD();
    DCHECK_EQ(browser->GetIdentifier(), browser_->GetIdentifier());
    is_closing_ = true;
    delegate_->OnBrowserWindowClosing();
  }
  
  void BrowserWindow::OnBrowserClosed(CefRefPtr<CefBrowser> browser) {
    REQUIRE_MAIN_THREAD();
    if (browser_.get()) {
      DCHECK_EQ(browser->GetIdentifier(), browser_->GetIdentifier());
      browser_ = NULL;
    }
    
    client_handler_->DetachDelegate();
    client_handler_ = NULL;
    
    // |this| may be deleted.
    delegate_->OnBrowserWindowDestroyed();
  }
  
  void BrowserWindow::OnSetAddress(const std::string& url) {
    REQUIRE_MAIN_THREAD();
    delegate_->OnSetAddress(url);
  }
  
  void BrowserWindow::OnSetTitle(const std::string& title) {
    REQUIRE_MAIN_THREAD();
    delegate_->OnSetTitle(title);
  }
  
  void BrowserWindow::OnSetFullscreen(bool fullscreen) {
    REQUIRE_MAIN_THREAD();
    delegate_->OnSetFullscreen(fullscreen);
  }
  
  void BrowserWindow::OnAutoResize(const CefSize& new_size) {
    REQUIRE_MAIN_THREAD();
    delegate_->OnAutoResize(new_size);
  }
  
  void BrowserWindow::OnSetLoadingState(bool isLoading,
                                        bool canGoBack,
                                        bool canGoForward) {
    REQUIRE_MAIN_THREAD();
    delegate_->OnSetLoadingState(isLoading, canGoBack, canGoForward);
  }
  
  void BrowserWindow::OnSetDraggableRegions(const std::vector<CefDraggableRegion>& regions) {
    REQUIRE_MAIN_THREAD();
    delegate_->OnSetDraggableRegions(regions);
  }
  
  void BrowserWindow::CreateBrowser(ClientWindowHandle parent_handle,
                                    const CefRect& rect,
                                    const CefBrowserSettings& settings,
                                    CefRefPtr<CefRequestContext> request_context) {
    REQUIRE_MAIN_THREAD();
    
    CefWindowInfo window_info;
    window_info.SetAsChild(parent_handle, rect.x, rect.y, rect.width, rect.height);
    CefBrowserHost::CreateBrowser(window_info,
                                  client_handler_,
                                  client_handler_->startup_url(),
                                  settings,
                                  request_context);
  }
  
  void BrowserWindow::GetPopupConfig(CefWindowHandle temp_handle,
                                     CefWindowInfo& windowInfo,
                                     CefRefPtr<CefClient>& client,
                                     CefBrowserSettings& settings) {
    CEF_REQUIRE_UI_THREAD();
    // The window will be properly sized after the browser is created.
    windowInfo.SetAsChild(temp_handle, 0, 0, 0, 0);
    client = client_handler_;
  }
  
  void BrowserWindow::ShowPopup(ClientWindowHandle parent_handle,
                                int x,
                                int y,
                                size_t width,
                                size_t height) {
    REQUIRE_MAIN_THREAD();
    
    NSView* browser_view = GetWindowHandle();
    
    // Re-parent |browser_view| to |parent_handle|.
    [browser_view removeFromSuperview];
    [parent_handle addSubview:browser_view];
    
    NSSize size = NSMakeSize(static_cast<int>(width), static_cast<int>(height));
    [browser_view setFrameSize:size];
  }
  
  void BrowserWindow::Show() {
    REQUIRE_MAIN_THREAD();
    // Nothing to do here. Chromium internally handles window show/hide.
  }
  
  void BrowserWindow::Hide() {
    REQUIRE_MAIN_THREAD();
    // Nothing to do here. Chromium internally handles window show/hide.
  }
  
  void BrowserWindow::SetBounds(int x, int y, size_t width, size_t height) {
    REQUIRE_MAIN_THREAD();
    // Nothing to do here. Cocoa will size the browser for us.
  }
  
  void BrowserWindow::SetFocus(bool focus) {
    REQUIRE_MAIN_THREAD();
    // Nothing to do here. Chromium internally handles window focus assignment.
  }
  
  ClientWindowHandle BrowserWindow::GetWindowHandle() const {
    REQUIRE_MAIN_THREAD();
    
    if (browser_)
      return browser_->GetHost()->GetWindowHandle();
    return NULL;
  }
}  // namespace client
