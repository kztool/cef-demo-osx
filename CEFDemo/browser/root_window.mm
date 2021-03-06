#import "root_window.h"
#import "temp_window.h"

@interface NSBorderlessWindow: NSWindow
- (void)performClose:(id)sender;
- (BOOL)windowShouldClose:(id)sender;
@end

@implementation NSBorderlessWindow: NSWindow
- (BOOL)windowShouldClose:(id)sender { return YES; }
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return YES; }

- (void)performClose:(id)sender {
  if([[self delegate] respondsToSelector:@selector(windowShouldClose:)]) {
    if(![[self delegate] windowShouldClose:self]) return;
  }
  else if([self respondsToSelector:@selector(windowShouldClose:)]) {
    if(![self windowShouldClose:self]) return;
  }
  
  [self close];
}
@end

// Receives notifications from controls and the browser window. Will delete
// itself when done.
@interface RootWindowDelegate : NSObject<NSWindowDelegate> {
@private
  NSWindow* window_;
  client::RootWindow* root_window_;
  bool force_close_;
}

@property(nonatomic, readonly) client::RootWindow* root_window;
@property(nonatomic, readwrite) bool force_close;

- (id)initWithWindow:(NSWindow*)window andRootWindow:(client::RootWindow*)root_window;
- (IBAction)goBack:(id)sender;
- (IBAction)goForward:(id)sender;
- (IBAction)reload:(id)sender;
- (IBAction)stopLoading:(id)sender;
- (IBAction)takeURLStringValueFrom:(NSTextField*)sender;
@end

@implementation RootWindowDelegate

@synthesize root_window = root_window_;
@synthesize force_close = force_close_;

- (id)initWithWindow:(NSWindow*)window andRootWindow:(client::RootWindow*)root_window {
  if (self = [super init]) {
    window_ = window;
    [window_ setDelegate:self];
    root_window_ = root_window;
    force_close_ = false;
    
    // Register for application hide/unhide notifications.
    [[NSNotificationCenter defaultCenter]
     addObserver:self
     selector:@selector(applicationDidHide:)
     name:NSApplicationDidHideNotification
     object:nil];
    [[NSNotificationCenter defaultCenter]
     addObserver:self
     selector:@selector(applicationDidUnhide:)
     name:NSApplicationDidUnhideNotification
     object:nil];
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  
  [super dealloc];
}

- (IBAction)goBack:(id)sender {
  CefRefPtr<CefBrowser> browser = root_window_->GetBrowser();
  if (browser.get())
    browser->GoBack();
}

- (IBAction)goForward:(id)sender {
  CefRefPtr<CefBrowser> browser = root_window_->GetBrowser();
  if (browser.get())
    browser->GoForward();
}

- (IBAction)reload:(id)sender {
  CefRefPtr<CefBrowser> browser = root_window_->GetBrowser();
  if (browser.get())
    browser->Reload();
}

- (IBAction)stopLoading:(id)sender {
  CefRefPtr<CefBrowser> browser = root_window_->GetBrowser();
  if (browser.get())
    browser->StopLoad();
  
  
  root_window_->Close(false);
}

- (IBAction)takeURLStringValueFrom:(NSTextField*)sender {
  CefRefPtr<CefBrowser> browser = root_window_->GetBrowser();
  if (!browser.get())
    return;
  
  NSString* url = [sender stringValue];
  
  // if it doesn't already have a prefix, add http. If we can't parse it,
  // just don't bother rather than making things worse.
  NSURL* tempUrl = [NSURL URLWithString:url];
  if (tempUrl && ![tempUrl scheme])
    url = [@"http://" stringByAppendingString:url];
  
  std::string urlStr = [url UTF8String];
  browser->GetMainFrame()->LoadURL(urlStr);
}

// Called when we are activated (when we gain focus).
- (void)windowDidBecomeKey:(NSNotification*)notification {
  root_window_->delegate()->OnRootWindowActivated(root_window_);
}

// Called when we are deactivated (when we lose focus).
- (void)windowDidResignKey:(NSNotification*)notification {}

// Called when we have been minimized.
- (void)windowDidMiniaturize:(NSNotification*)notification {}

// Called when we have been unminimized.
- (void)windowDidDeminiaturize:(NSNotification*)notification {}

// Called when the application has been hidden.
- (void)applicationDidHide:(NSNotification*)notification {}

// Called when the application has been unhidden.
- (void)applicationDidUnhide:(NSNotification*)notification {}

// Called when the window is about to close. Perform the self-destruction
// sequence by getting rid of the window. By returning YES, we allow the window
// to be removed from the screen.
- (BOOL)windowShouldClose:(id)window {
  if (!force_close_) {
    if (root_window_ && !root_window_->IsClosing()) {
      CefRefPtr<CefBrowser> browser = root_window_->GetBrowser();
      if (browser.get()) {
        // Notify the browser window that we would like to close it. This
        // will result in a call to ClientHandler::DoClose() if the
        // JavaScript 'onbeforeunload' event handler allows it.
        browser->GetHost()->CloseBrowser(false);
        
        // Cancel the close.
        return NO;
      }
    }
  }
  // Try to make the window go away.
  [window autorelease];
  // Clean ourselves up after clearing the stack of anything that might have the
  // window on it.
  [self performSelectorOnMainThread:@selector(cleanup:) withObject:window waitUntilDone:NO];
  // Allow the close.
  return YES;
}

// Deletes itself.
- (void)cleanup:(id)window {
  root_window_->WindowDestroyed();
  // Don't want any more delegate callbacks after we destroy ourselves.
  [window setDelegate:nil];
  [self release];
}
@end

namespace client {  
  void RootWindow::OnExtensionsChanged(const ExtensionSet& extensions) {
    REQUIRE_MAIN_THREAD();
    DCHECK(delegate_);
    DCHECK(!WithExtension());
    
    if (extensions.empty()) {
      return;
    }
    
    ExtensionSet::const_iterator it = extensions.begin();
    for (; it != extensions.end(); ++it) {
      delegate_->CreateExtensionWindow(*it);
    }
  }
  
  namespace {
    // Sizes for URL bar layout.
#define BUTTON_HEIGHT 22
#define BUTTON_WIDTH 72
#define BUTTON_MARGIN 8
#define URLBAR_HEIGHT 32
    
    NSButton* MakeButton(NSRect* rect, NSString* title, NSView* parent) {
      NSButton* button = [[[NSButton alloc] initWithFrame:*rect] autorelease];
      [button setTitle:title];
      [button setBezelStyle:NSSmallSquareBezelStyle];
      [button setAutoresizingMask:(NSViewMaxXMargin | NSViewMinYMargin)];
      [parent addSubview:button];
      rect->origin.x += BUTTON_WIDTH;
      return button;
    }
    
    NSRect GetScreenRectForWindow(NSWindow* window) {
      NSScreen* screen = [window screen];
      if (screen == nil)
        screen = [NSScreen mainScreen];
      return [screen visibleFrame];
    }
  }  // namespace
  
  RootWindow::RootWindow()
  : window_type_(WindowType_None),
  is_popup_(false),
  initialized_(false),
  window_(nil),
  back_button_(nil),
  forward_button_(nil),
  reload_button_(nil),
  stop_button_(nil),
  url_textfield_(nil),
  window_destroyed_(false),
  browser_destroyed_(false),
  is_closing_(false),
  client_handler_(NULL),
  browser_(NULL),
  delegate_(NULL) {}
  
  RootWindow::~RootWindow() {
    REQUIRE_MAIN_THREAD();
    
    // The window and browser should already have been destroyed.
    DCHECK(window_destroyed_);
    DCHECK(browser_destroyed_);
  }
  
  void RootWindow::Init(RootWindow::Delegate* delegate,
                        const WindowType window_type,
                        const bool with_extension,
                        const std::string url,
                        const CefBrowserSettings& settings) {
    DCHECK(delegate);
    DCHECK(!initialized_);
    
    delegate_ = delegate;
    window_type_ = window_type;
    with_extension_ = with_extension;
    
    client_handler_ = new ClientHandler(this, url);
    initialized_ = true;
    
    // Create the native root window on the main thread.
    if (CURRENTLY_ON_MAIN_THREAD()) {
      CreateRootWindow(settings);
    } else {
      MAIN_POST_CLOSURE(base::Bind(&RootWindow::CreateRootWindow, this, settings));
    }
  }
  
  void RootWindow::InitAsPopup(RootWindow::Delegate* delegate,
                               WindowType window_type,
                               const CefPopupFeatures& popupFeatures,
                               CefWindowInfo& windowInfo,
                               CefRefPtr<CefClient>& client,
                               CefBrowserSettings& settings) {
    REQUIRE_MAIN_THREAD();
    DCHECK(delegate);
    DCHECK(!initialized_);
    
    delegate_ = delegate;
    window_type_ = window_type;
    is_popup_ = true;
    
    if (popupFeatures.xSet)
      start_rect_.x = popupFeatures.x;
    if (popupFeatures.ySet)
      start_rect_.y = popupFeatures.y;
    if (popupFeatures.widthSet)
      start_rect_.width = popupFeatures.width;
    if (popupFeatures.heightSet)
      start_rect_.height = popupFeatures.height;
    
    client_handler_ = new ClientHandler(this, std::string());

    initialized_ = true;
    
    // The new popup is initially parented to a temporary window. The native root
    // window will be created after the browser is created and the popup window
    // will be re-parented to it at that time.
    
    // The window will be properly sized after the browser is created.
    windowInfo.SetAsChild(TempWindow::GetWindowHandle(), 0, 0, 0, 0);
    client = client_handler_;
  }
  
  void RootWindow::Show() {
    REQUIRE_MAIN_THREAD();
    
    if (window_ && ![window_ isVisible]) {
      [window_ makeKeyAndOrderFront:nil];
    }
  }
  
  void RootWindow::Hide() {
    REQUIRE_MAIN_THREAD();
    
    if (!window_)
      return;
    
    // Undo miniaturization, if any, so the window will actually be hidden.
    if ([window_ isMiniaturized])
      [window_ deminiaturize:nil];
    
    // Hide the window.
    [window_ orderOut:nil];
  }
  
  void RootWindow::SetBounds(int x, int y, size_t width, size_t height) {
    REQUIRE_MAIN_THREAD();
    
    if (!window_)
      return;
    
    NSRect screen_rect = GetScreenRectForWindow(window_);
    
    // Desired content rectangle.
    NSRect content_rect;
    content_rect.size.width = static_cast<int>(width);
    
    content_rect.size.height = static_cast<int>(height) + (window_type_ == WindowType_Web ? URLBAR_HEIGHT : 0);
    
    // Convert to a frame rectangle.
    NSRect frame_rect = [window_ frameRectForContentRect:content_rect];
    frame_rect.origin.x = x;
    frame_rect.origin.y = screen_rect.size.height - y;
    
    [window_ setFrame:frame_rect display:YES];
  }
  
  void RootWindow::Close(bool force) {
    REQUIRE_MAIN_THREAD();
    
    if (window_) {
      static_cast<RootWindowDelegate*>([window_ delegate]).force_close = force;
      [window_ performClose:nil];
    }
  }
  
  CefRefPtr<CefBrowser> RootWindow::GetBrowser() const {
    REQUIRE_MAIN_THREAD();
    return browser_;
  }
  
  bool RootWindow::WithExtension() const {
    REQUIRE_MAIN_THREAD();
    return with_extension_;
  }
  
  void RootWindow::WindowDestroyed() {
    window_ = nil;
    window_destroyed_ = true;
    NotifyDestroyedIfDone();
  }

  bool RootWindow::IsClosing() const {
    REQUIRE_MAIN_THREAD();
    return is_closing_;
  }
  
  void RootWindow::CreateRootWindow(const CefBrowserSettings& settings) {
    REQUIRE_MAIN_THREAD();
    DCHECK(!window_);
    
    // TODO(port): If no x,y position is specified the window will always appear
    // in the upper-left corner. Maybe there's a better default place to put it?
    int x = start_rect_.x;
    int y = start_rect_.y;
    int width, height;
    if (start_rect_.IsEmpty()) {
      // TODO(port): Also, maybe there's a better way to choose the default size.
      width = 800;
      height = 600;
    } else {
      width = start_rect_.width;
      height = start_rect_.height;
    }
    
    // Create the main window.
    NSRect screen_rect = [[NSScreen mainScreen] visibleFrame];
    NSRect window_rect =
    NSMakeRect(x, screen_rect.size.height - y, width, height);
    
    // The CEF framework library is loaded at runtime so we need to use this
    // mechanism for retrieving the class.
    Class window_class = NSClassFromString(@"NSBorderlessWindow");
    CHECK(window_class);
    
    window_ = [[window_class alloc]
               initWithContentRect:window_rect
               styleMask:(NSClosableWindowMask |  NSResizableWindowMask | NSTitledWindowMask)
               backing:NSBackingStoreBuffered
               defer:NO];
    [window_ setTitle:@"cefclient"];
    
    // Create the delegate for control and browser window events.
    RootWindowDelegate* delegate =
    [[RootWindowDelegate alloc] initWithWindow:window_ andRootWindow:this];
    
    // Rely on the window delegate to clean us up rather than immediately
    // releasing when the window gets closed. We use the delegate to do
    // everything from the autorelease pool so the window isn't on the stack
    // during cleanup (ie, a window close from javascript).
    [window_ setReleasedWhenClosed:NO];
    
    NSView* contentView = [window_ contentView];
    NSRect contentBounds = [contentView bounds];
    
    // Make the content view for the window have a layer. This will make all
    // sub-views have layers. This is necessary to ensure correct layer
    // ordering of all child views and their layers.
    [contentView setWantsLayer:YES];
    
    if (window_type_ == WindowType_Web) {
      // Create the buttons.
      NSRect button_rect = contentBounds;
      button_rect.origin.y = window_rect.size.height - URLBAR_HEIGHT +
      (URLBAR_HEIGHT - BUTTON_HEIGHT) / 2;
      button_rect.size.height = BUTTON_HEIGHT;
      button_rect.origin.x += BUTTON_MARGIN;
      button_rect.size.width = BUTTON_WIDTH;
      
      contentBounds.size.height -= URLBAR_HEIGHT;
      
      back_button_ = MakeButton(&button_rect, @"Back", contentView);
      [back_button_ setTarget:delegate];
      [back_button_ setAction:@selector(goBack:)];
      [back_button_ setEnabled:NO];
      
      forward_button_ = MakeButton(&button_rect, @"Forward", contentView);
      [forward_button_ setTarget:delegate];
      [forward_button_ setAction:@selector(goForward:)];
      [forward_button_ setEnabled:NO];
      
      reload_button_ = MakeButton(&button_rect, @"Reload", contentView);
      [reload_button_ setTarget:delegate];
      [reload_button_ setAction:@selector(reload:)];
      [reload_button_ setEnabled:NO];
      
      stop_button_ = MakeButton(&button_rect, @"Stop", contentView);
      [stop_button_ setTarget:delegate];
      [stop_button_ setAction:@selector(stopLoading:)];
      [stop_button_ setEnabled:NO];
      
      // Create the URL text field.
      button_rect.origin.x += BUTTON_MARGIN;
      button_rect.size.width =
      [contentView bounds].size.width - button_rect.origin.x - BUTTON_MARGIN;
      url_textfield_ = [[NSTextField alloc] initWithFrame:button_rect];
      [contentView addSubview:url_textfield_];
      [url_textfield_
       setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
      [url_textfield_ setTarget:delegate];
      [url_textfield_ setAction:@selector(takeURLStringValueFrom:)];
      [url_textfield_ setEnabled:NO];
      [[url_textfield_ cell] setWraps:NO];
      [[url_textfield_ cell] setScrollable:YES];
    }
    
    if (!is_popup_) {
      // Create the browser window.
      CefWindowInfo window_info;
      window_info.SetAsChild(contentView, 0, 0, width, height);
      CefBrowserHost::CreateBrowser(window_info,
                                    client_handler_,
                                    client_handler_->startup_url(),
                                    settings,
                                    delegate_->GetRequestContext(this));
    } else {
      // With popups we already have a browser window. Parent the browser window
      // to the root window and show it in the correct location.
      NSView* browser_view = browser_->GetHost()->GetWindowHandle();
      // Re-parent |browser_view| to |parent_handle|.
      [browser_view removeFromSuperview];
      [contentView addSubview:browser_view];
      
      NSSize size = NSMakeSize(static_cast<int>(contentBounds.size.width), static_cast<int>(contentBounds.size.height));
      [browser_view setFrameSize:size];
    }
    
    // Show the window
    Show();
    
    // Size the window.
    SetBounds(x, y, width, height);
  }
    
  void RootWindow::OnBrowserCreated(CefRefPtr<CefBrowser> browser) {
    REQUIRE_MAIN_THREAD();
    DCHECK(!browser_);
    browser_ = browser;
    // For popup browsers create the root window once the browser has been
    // created.
    if (is_popup_) {
      CreateRootWindow(CefBrowserSettings());
    }
    
    delegate_->OnBrowserCreated(this, browser);
  }
  
  void RootWindow::OnBrowserClosing(CefRefPtr<CefBrowser> browser) {
    REQUIRE_MAIN_THREAD();
    DCHECK_EQ(browser->GetIdentifier(), browser_->GetIdentifier());
    is_closing_ = true;
  }
  
  void RootWindow::OnBrowserClosed(CefRefPtr<CefBrowser> browser) {
    REQUIRE_MAIN_THREAD();
    if (browser_.get()) {
      DCHECK_EQ(browser->GetIdentifier(), browser_->GetIdentifier());
      browser_ = NULL;
    }
    
    client_handler_->DetachDelegate();
    client_handler_ = NULL;
    
    // |this| may be deleted.
    OnBrowserWindowDestroyed();
  }
  
  void RootWindow::OnBrowserWindowDestroyed() {
    REQUIRE_MAIN_THREAD();
    
    if (!window_destroyed_) {
      // The browser was destroyed first. This could be due to the use of
      // off-screen rendering or execution of JavaScript window.close().
      // Close the RootWindow.
      Close(true);
    }
    
    browser_destroyed_ = true;
    NotifyDestroyedIfDone();
  }
  
  void RootWindow::OnSetAddress(const std::string& url) {
    REQUIRE_MAIN_THREAD();
    
    if (url_textfield_) {
      std::string urlStr(url);
      NSString* str = [NSString stringWithUTF8String:urlStr.c_str()];
      [url_textfield_ setStringValue:str];
    }
  }
  
  void RootWindow::OnSetDraggableRegions(const std::vector<CefDraggableRegion>& regions) {
    REQUIRE_MAIN_THREAD();
    // TODO(cef): Implement support for draggable regions on this platform.
  }
  
  void RootWindow::OnSetTitle(const std::string& title) {
    REQUIRE_MAIN_THREAD();
    
    if (window_) {
      std::string titleStr(title);
      NSString* str = [NSString stringWithUTF8String:titleStr.c_str()];
      [window_ setTitle:str];
    }
  }
  
  void RootWindow::OnSetFavicon(CefRefPtr<CefImage> image) {
    REQUIRE_MAIN_THREAD();
  }
  
  void RootWindow::OnSetFullscreen(bool fullscreen) {
    CEF_REQUIRE_UI_THREAD();
    REQUIRE_MAIN_THREAD();
    
    CefRefPtr<CefBrowser> browser = GetBrowser();
    NSWindow* window = [browser->GetHost()->GetWindowHandle() window];
    if (browser && window != nil) {
      if (fullscreen) {
        [window performZoom:nil];
      } else {
        if ([window isMiniaturized]) {
          [window deminiaturize:nil];
        } else if ([window isZoomed]) {
          [window performZoom:nil];
        } else {}
      }
    }
  }
  
  void RootWindow::OnAutoResize(const CefSize& new_size) {
    REQUIRE_MAIN_THREAD();
    
    if (!window_)
      return;
    
    // Desired content rectangle.
    NSRect content_rect;
    content_rect.size.width = static_cast<int>(new_size.width);
    content_rect.size.height = static_cast<int>(new_size.height) + (window_type_ == WindowType_Web ? URLBAR_HEIGHT : 0);
    
    // Convert to a frame rectangle.
    NSRect frame_rect = [window_ frameRectForContentRect:content_rect];
    // Don't change the origin.
    frame_rect.origin = window_.frame.origin;
    
    [window_ setFrame:frame_rect display:YES];
    
    // Make sure the window is visible.
    Show();
  }
  
  void RootWindow::OnSetLoadingState(bool isLoading,
                                     bool canGoBack,
                                     bool canGoForward) {
    REQUIRE_MAIN_THREAD();
    
    if (window_type_ == WindowType_Web) {
      [url_textfield_ setEnabled:YES];
      [reload_button_ setEnabled:!isLoading];
      [stop_button_ setEnabled:isLoading];
      [back_button_ setEnabled:canGoBack];
      [forward_button_ setEnabled:canGoForward];
    }
    
    // After Loading is done, check if voiceover is running and accessibility
    // should be enabled.
    if (!isLoading) {
      Boolean keyExists = false;
      // On OSX there is no API to query if VoiceOver is active or not. The value
      // however is stored in preferences that can be queried.
      if (CFPreferencesGetAppBooleanValue(CFSTR("voiceOverOnOffKey"),
                                          CFSTR("com.apple.universalaccess"),
                                          &keyExists)) {
        GetBrowser()->GetHost()->SetAccessibilityState(STATE_ENABLED);
      }
    }
  }
  
  void RootWindow::NotifyDestroyedIfDone() {
    // Notify once both the window and the browser have been destroyed.
    if (window_destroyed_ && browser_destroyed_)
      delegate_->OnRootWindowDestroyed(this);
  }
}  // namespace client
