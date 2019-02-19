// Copyright (c) 2013 The Chromium Embedded Framework Authors. All rights
// reserved. Use of this source code is governed by a BSD-style license that
// can be found in the LICENSE file.

#import "client_handler.h"
#import "main_context.h"
#import "root_window_manager.h"

namespace client {
  namespace {
    // Custom menu command Ids.
    enum client_menu_ids {
      CLIENT_ID_SHOW_DEVTOOLS = MENU_ID_USER_FIRST,
      CLIENT_ID_CLOSE_DEVTOOLS,
      CLIENT_ID_INSPECT_ELEMENT,
      CLIENT_ID_SHOW_SSL_INFO,
      CLIENT_ID_TESTMENU_SUBMENU,
      CLIENT_ID_TESTMENU_CHECKITEM,
      CLIENT_ID_TESTMENU_RADIOITEM1,
      CLIENT_ID_TESTMENU_RADIOITEM2,
      CLIENT_ID_TESTMENU_RADIOITEM3,
    };
    
    // Musr match the value in client_renderer.cc.
    const char kFocusedNodeChangedMessage[] = "ClientRenderer.FocusedNodeChanged";
    
    std::string GetTimeString(const CefTime& value) {
      if (value.GetTimeT() == 0)
        return "Unspecified";
      
      static const char* kMonths[] = {
        "January", "February", "March",     "April",   "May",      "June",
        "July",    "August",   "September", "October", "November", "December"};
      std::string month;
      if (value.month >= 1 && value.month <= 12)
        month = kMonths[value.month - 1];
      else
        month = "Invalid";
      
      std::stringstream ss;
      ss << month << " " << value.day_of_month << ", " << value.year << " "
      << std::setfill('0') << std::setw(2) << value.hour << ":"
      << std::setfill('0') << std::setw(2) << value.minute << ":"
      << std::setfill('0') << std::setw(2) << value.second;
      return ss.str();
    }
    
    std::string GetBinaryString(CefRefPtr<CefBinaryValue> value) {
      if (!value.get())
        return "&nbsp;";
      
      // Retrieve the value.
      const size_t size = value->GetSize();
      std::string src;
      src.resize(size);
      value->GetData(const_cast<char*>(src.data()), size, 0);
      
      // Encode the value.
      return CefBase64Encode(src.data(), src.size());
    }
    
#define FLAG(flag)                          \
if (status & flag) {                      \
result += std::string(#flag) + "<br/>"; \
}
    
#define VALUE(val, def)       \
if (val == def) {           \
return std::string(#def); \
}
    
    std::string GetCertStatusString(cef_cert_status_t status) {
      std::string result;
      
      FLAG(CERT_STATUS_COMMON_NAME_INVALID);
      FLAG(CERT_STATUS_DATE_INVALID);
      FLAG(CERT_STATUS_AUTHORITY_INVALID);
      FLAG(CERT_STATUS_NO_REVOCATION_MECHANISM);
      FLAG(CERT_STATUS_UNABLE_TO_CHECK_REVOCATION);
      FLAG(CERT_STATUS_REVOKED);
      FLAG(CERT_STATUS_INVALID);
      FLAG(CERT_STATUS_WEAK_SIGNATURE_ALGORITHM);
      FLAG(CERT_STATUS_NON_UNIQUE_NAME);
      FLAG(CERT_STATUS_WEAK_KEY);
      FLAG(CERT_STATUS_PINNED_KEY_MISSING);
      FLAG(CERT_STATUS_NAME_CONSTRAINT_VIOLATION);
      FLAG(CERT_STATUS_VALIDITY_TOO_LONG);
      FLAG(CERT_STATUS_IS_EV);
      FLAG(CERT_STATUS_REV_CHECKING_ENABLED);
      FLAG(CERT_STATUS_SHA1_SIGNATURE_PRESENT);
      FLAG(CERT_STATUS_CT_COMPLIANCE_FAILED);
      
      if (result.empty())
        return "&nbsp;";
      return result;
    }
    
    std::string GetSSLVersionString(cef_ssl_version_t version) {
      VALUE(version, SSL_CONNECTION_VERSION_UNKNOWN);
      VALUE(version, SSL_CONNECTION_VERSION_SSL2);
      VALUE(version, SSL_CONNECTION_VERSION_SSL3);
      VALUE(version, SSL_CONNECTION_VERSION_TLS1);
      VALUE(version, SSL_CONNECTION_VERSION_TLS1_1);
      VALUE(version, SSL_CONNECTION_VERSION_TLS1_2);
      VALUE(version, SSL_CONNECTION_VERSION_QUIC);
      return std::string();
    }
    
    std::string GetContentStatusString(cef_ssl_content_status_t status) {
      std::string result;
      
      VALUE(status, SSL_CONTENT_NORMAL_CONTENT);
      FLAG(SSL_CONTENT_DISPLAYED_INSECURE_CONTENT);
      FLAG(SSL_CONTENT_RAN_INSECURE_CONTENT);
      
      if (result.empty())
        return "&nbsp;";
      return result;
    }
    
    // Load a data: URI containing the error message.
    void LoadErrorPage(CefRefPtr<CefFrame> frame,
                       const std::string& failed_url,
                       cef_errorcode_t error_code,
                       const std::string& other_info) {
      std::stringstream ss;
      ss << "<html><head><title>Page failed to load</title></head>"
      "<body bgcolor=\"white\">"
      "<h3>Page failed to load.</h3>"
      "URL: <a href=\""
      << failed_url << "\">" << failed_url
      << "</a><br/>Error: " << utils::GetErrorString(error_code) << " ("
      << error_code << ")";
      
      if (!other_info.empty())
        ss << "<br/>" << other_info;
      
      ss << "</body></html>";
      frame->LoadURL(utils::GetDataURI(ss.str(), "text/html"));
    }
    
    // Return HTML string with information about a certificate.
    std::string GetCertificateInformation(CefRefPtr<CefX509Certificate> cert,
                                          cef_cert_status_t certstatus) {
      CefRefPtr<CefX509CertPrincipal> subject = cert->GetSubject();
      CefRefPtr<CefX509CertPrincipal> issuer = cert->GetIssuer();
      
      // Build a table showing certificate information. Various types of invalid
      // certificates can be tested using https://badssl.com/.
      std::stringstream ss;
      ss << "<h3>X.509 Certificate Information:</h3>"
      "<table border=1><tr><th>Field</th><th>Value</th></tr>";
      
      if (certstatus != CERT_STATUS_NONE) {
        ss << "<tr><td>Status</td><td>" << GetCertStatusString(certstatus)
        << "</td></tr>";
      }
      
      ss << "<tr><td>Subject</td><td>"
      << (subject.get() ? subject->GetDisplayName().ToString() : "&nbsp;")
      << "</td></tr>"
      "<tr><td>Issuer</td><td>"
      << (issuer.get() ? issuer->GetDisplayName().ToString() : "&nbsp;")
      << "</td></tr>"
      "<tr><td>Serial #*</td><td>"
      << GetBinaryString(cert->GetSerialNumber()) << "</td></tr>"
      << "<tr><td>Valid Start</td><td>" << GetTimeString(cert->GetValidStart())
      << "</td></tr>"
      "<tr><td>Valid Expiry</td><td>"
      << GetTimeString(cert->GetValidExpiry()) << "</td></tr>";
      
      CefX509Certificate::IssuerChainBinaryList der_chain_list;
      CefX509Certificate::IssuerChainBinaryList pem_chain_list;
      cert->GetDEREncodedIssuerChain(der_chain_list);
      cert->GetPEMEncodedIssuerChain(pem_chain_list);
      DCHECK_EQ(der_chain_list.size(), pem_chain_list.size());
      
      der_chain_list.insert(der_chain_list.begin(), cert->GetDEREncoded());
      pem_chain_list.insert(pem_chain_list.begin(), cert->GetPEMEncoded());
      
      for (size_t i = 0U; i < der_chain_list.size(); ++i) {
        ss << "<tr><td>DER Encoded*</td>"
        "<td style=\"max-width:800px;overflow:scroll;\">"
        << GetBinaryString(der_chain_list[i])
        << "</td></tr>"
        "<tr><td>PEM Encoded*</td>"
        "<td style=\"max-width:800px;overflow:scroll;\">"
        << GetBinaryString(pem_chain_list[i]) << "</td></tr>";
      }
      
      ss << "</table> * Displayed value is base64 encoded.";
      return ss.str();
    }
    
  }  // namespace
  
  class ClientDownloadImageCallback : public CefDownloadImageCallback {
  public:
    explicit ClientDownloadImageCallback(CefRefPtr<ClientHandler> client_handler)
    : client_handler_(client_handler) {}
    
    void OnDownloadImageFinished(const CefString& image_url,
                                 int http_status_code,
                                 CefRefPtr<CefImage> image) OVERRIDE {
      if (image)
        client_handler_->NotifyFavicon(image);
    }
    
  private:
    CefRefPtr<ClientHandler> client_handler_;
    
    IMPLEMENT_REFCOUNTING(ClientDownloadImageCallback);
    DISALLOW_COPY_AND_ASSIGN(ClientDownloadImageCallback);
  };
  
  ClientHandler::ClientHandler(Delegate* delegate, const std::string& startup_url)
  : startup_url_(startup_url),
  download_favicon_images_(false),
  delegate_(delegate),
  browser_count_(0),
  console_log_file_(MainContext::Get()->GetConsoleLogPath()),
  first_console_message_(true),
  focus_on_editable_field_(false),
  initial_navigation_(true) {
    DCHECK(!console_log_file_.empty());
    
    resource_manager_ = new CefResourceManager();
    utils::SetupResourceManager(resource_manager_);
    
    // Read command line settings.
    CefRefPtr<CefCommandLine> command_line =
    CefCommandLine::GetGlobalCommandLine();
    mouse_cursor_change_disabled_ =
    command_line->HasSwitch(switches::kMouseCursorChangeDisabled);
  }
  
  void ClientHandler::DetachDelegate() {
    if (!CURRENTLY_ON_MAIN_THREAD()) {
      // Execute this method on the main thread.
      MAIN_POST_CLOSURE(base::Bind(&ClientHandler::DetachDelegate, this));
      return;
    }
    
    DCHECK(delegate_);
    delegate_ = NULL;
  }
  
  bool ClientHandler::OnProcessMessageReceived(
                                               CefRefPtr<CefBrowser> browser,
                                               CefProcessId source_process,
                                               CefRefPtr<CefProcessMessage> message) {
    CEF_REQUIRE_UI_THREAD();
  
    // Check for messages from the client renderer.
    std::string message_name = message->GetName();
    if (message_name == kFocusedNodeChangedMessage) {
      // A message is sent from ClientRenderDelegate to tell us whether the
      // currently focused DOM node is editable. Use of |focus_on_editable_field_|
      // is redundant with CefKeyEvent.focus_on_editable_field in OnPreKeyEvent
      // but is useful for demonstration purposes.
      focus_on_editable_field_ = message->GetArgumentList()->GetBool(0);
      return true;
    }
    
    return false;
  }
  
  void ClientHandler::OnBeforeContextMenu(CefRefPtr<CefBrowser> browser,
                                          CefRefPtr<CefFrame> frame,
                                          CefRefPtr<CefContextMenuParams> params,
                                          CefRefPtr<CefMenuModel> model) {
    CEF_REQUIRE_UI_THREAD();
    
    if ((params->GetTypeFlags() & (CM_TYPEFLAG_PAGE | CM_TYPEFLAG_FRAME)) != 0) {
      // Add a separator if the menu already has items.
      if (model->GetCount() > 0)
        model->AddSeparator();
      
      // Add DevTools items to all context menus.
      model->AddItem(CLIENT_ID_SHOW_DEVTOOLS, "&Show DevTools");
      model->AddItem(CLIENT_ID_CLOSE_DEVTOOLS, "Close DevTools");
      model->AddSeparator();
      model->AddItem(CLIENT_ID_INSPECT_ELEMENT, "Inspect Element");
      
      if (HasSSLInformation(browser)) {
        model->AddSeparator();
        model->AddItem(CLIENT_ID_SHOW_SSL_INFO, "Show SSL information");
      }
      
      // Test context menu features.
      BuildTestMenu(model);
    }
    
    if (delegate_)
      delegate_->OnBeforeContextMenu(model);
  }
  
  bool ClientHandler::OnContextMenuCommand(CefRefPtr<CefBrowser> browser,
                                           CefRefPtr<CefFrame> frame,
                                           CefRefPtr<CefContextMenuParams> params,
                                           int command_id,
                                           EventFlags event_flags) {
    CEF_REQUIRE_UI_THREAD();
    
    switch (command_id) {
      case CLIENT_ID_SHOW_DEVTOOLS:
        ShowDevTools(browser, CefPoint());
        return true;
      case CLIENT_ID_CLOSE_DEVTOOLS:
        CloseDevTools(browser);
        return true;
      case CLIENT_ID_INSPECT_ELEMENT:
        ShowDevTools(browser, CefPoint(params->GetXCoord(), params->GetYCoord()));
        return true;
      case CLIENT_ID_SHOW_SSL_INFO:
        ShowSSLInformation(browser);
        return true;
      default:  // Allow default handling, if any.
        return ExecuteTestMenu(command_id);
    }
  }
  
  void ClientHandler::OnAddressChange(CefRefPtr<CefBrowser> browser,
                                      CefRefPtr<CefFrame> frame,
                                      const CefString& url) {
    CEF_REQUIRE_UI_THREAD();
    
    // Only update the address for the main (top-level) frame.
    if (frame->IsMain())
      NotifyAddress(url);
  }
  
  void ClientHandler::OnTitleChange(CefRefPtr<CefBrowser> browser,
                                    const CefString& title) {
    CEF_REQUIRE_UI_THREAD();
    
    NotifyTitle(title);
  }
  
  void ClientHandler::OnFaviconURLChange(
                                         CefRefPtr<CefBrowser> browser,
                                         const std::vector<CefString>& icon_urls) {
    CEF_REQUIRE_UI_THREAD();
    
    if (!icon_urls.empty() && download_favicon_images_) {
      browser->GetHost()->DownloadImage(icon_urls[0], true, 16, false,
                                        new ClientDownloadImageCallback(this));
    }
  }
  
  void ClientHandler::OnFullscreenModeChange(CefRefPtr<CefBrowser> browser,
                                             bool fullscreen) {
    CEF_REQUIRE_UI_THREAD();
    
    NotifyFullscreen(fullscreen);
  }
  
  bool ClientHandler::OnConsoleMessage(CefRefPtr<CefBrowser> browser,
                                       cef_log_severity_t level,
                                       const CefString& message,
                                       const CefString& source,
                                       int line) {
    CEF_REQUIRE_UI_THREAD();
    
    FILE* file = fopen(console_log_file_.c_str(), "a");
    if (file) {
      std::stringstream ss;
      ss << "Level: ";
      switch (level) {
        case LOGSEVERITY_DEBUG:
          ss << "Debug" << NEWLINE;
          break;
        case LOGSEVERITY_INFO:
          ss << "Info" << NEWLINE;
          break;
        case LOGSEVERITY_WARNING:
          ss << "Warn" << NEWLINE;
          break;
        case LOGSEVERITY_ERROR:
          ss << "Error" << NEWLINE;
          break;
        default:
          NOTREACHED();
          break;
      }
      ss << "Message: " << message.ToString() << NEWLINE
      << "Source: " << source.ToString() << NEWLINE << "Line: " << line
      << NEWLINE << "-----------------------" << NEWLINE;
      fputs(ss.str().c_str(), file);
      fclose(file);
      
      if (first_console_message_) {
        utils::Alert(browser, "Console messages written to \"" + console_log_file_ + "\"");
        first_console_message_ = false;
      }
    }
    
    return false;
  }
  
  bool ClientHandler::OnAutoResize(CefRefPtr<CefBrowser> browser,
                                   const CefSize& new_size) {
    CEF_REQUIRE_UI_THREAD();
    
    NotifyAutoResize(new_size);
    return true;
  }
  
  void ClientHandler::OnBeforeDownload(
                                       CefRefPtr<CefBrowser> browser,
                                       CefRefPtr<CefDownloadItem> download_item,
                                       const CefString& suggested_name,
                                       CefRefPtr<CefBeforeDownloadCallback> callback) {
    CEF_REQUIRE_UI_THREAD();
    
    // Continue the download and show the "Save As" dialog.
    callback->Continue(MainContext::Get()->GetDownloadPath(suggested_name), true);
  }
  
  void ClientHandler::OnDownloadUpdated(
                                        CefRefPtr<CefBrowser> browser,
                                        CefRefPtr<CefDownloadItem> download_item,
                                        CefRefPtr<CefDownloadItemCallback> callback) {
    CEF_REQUIRE_UI_THREAD();
    
    if (download_item->IsComplete()) {
      utils::Alert(browser, "File \"" +
                         download_item->GetFullPath().ToString() +
                         "\" downloaded successfully.");
    }
  }
  
  bool ClientHandler::OnDragEnter(CefRefPtr<CefBrowser> browser,
                                  CefRefPtr<CefDragData> dragData,
                                  CefDragHandler::DragOperationsMask mask) {
    CEF_REQUIRE_UI_THREAD();
    
    // Forbid dragging of URLs and files.
    if ((mask & DRAG_OPERATION_LINK) && !dragData->IsFragment()) {
      utils::Alert(browser, "cefclient blocks dragging of URLs and files");
      return true;
    }
    
    return false;
  }
  
  void ClientHandler::OnDraggableRegionsChanged(
                                                CefRefPtr<CefBrowser> browser,
                                                const std::vector<CefDraggableRegion>& regions) {
    CEF_REQUIRE_UI_THREAD();
    
    NotifyDraggableRegions(regions);
  }
  
  void ClientHandler::OnTakeFocus(CefRefPtr<CefBrowser> browser, bool next) {
    CEF_REQUIRE_UI_THREAD();
    
    NotifyTakeFocus(next);
  }
  
  bool ClientHandler::OnSetFocus(CefRefPtr<CefBrowser> browser,
                                 FocusSource source) {
    CEF_REQUIRE_UI_THREAD();
    
    if (initial_navigation_) {
      CefRefPtr<CefCommandLine> command_line =
      CefCommandLine::GetGlobalCommandLine();
      if (command_line->HasSwitch(switches::kNoActivate)) {
        // Don't give focus to the browser on creation.
        return true;
      }
    }
    
    return false;
  }
  
  bool ClientHandler::OnPreKeyEvent(CefRefPtr<CefBrowser> browser,
                                    const CefKeyEvent& event,
                                    CefEventHandle os_event,
                                    bool* is_keyboard_shortcut) {
    CEF_REQUIRE_UI_THREAD();
    
    if (!event.focus_on_editable_field && event.windows_key_code == 0x20) {
      // Special handling for the space character when an input element does not
      // have focus. Handling the event in OnPreKeyEvent() keeps the event from
      // being processed in the renderer. If we instead handled the event in the
      // OnKeyEvent() method the space key would cause the window to scroll in
      // addition to showing the alert box.
      if (event.type == KEYEVENT_RAWKEYDOWN)
        utils::Alert(browser, "You pressed the space bar!");
      return true;
    }
    
    return false;
  }
  
  bool ClientHandler::OnBeforePopup(
                                    CefRefPtr<CefBrowser> browser,
                                    CefRefPtr<CefFrame> frame,
                                    const CefString& target_url,
                                    const CefString& target_frame_name,
                                    CefLifeSpanHandler::WindowOpenDisposition target_disposition,
                                    bool user_gesture,
                                    const CefPopupFeatures& popupFeatures,
                                    CefWindowInfo& windowInfo,
                                    CefRefPtr<CefClient>& client,
                                    CefBrowserSettings& settings,
                                    bool* no_javascript_access) {
    CEF_REQUIRE_UI_THREAD();
    
    // Return true to cancel the popup window.
    return !CreatePopupWindow(browser, false, popupFeatures, windowInfo, client,
                              settings);
  }
  
  void ClientHandler::OnAfterCreated(CefRefPtr<CefBrowser> browser) {
    CEF_REQUIRE_UI_THREAD();
    
    browser_count_++;
    
    // Disable mouse cursor change if requested via the command-line flag.
    if (mouse_cursor_change_disabled_)
      browser->GetHost()->SetMouseCursorChangeDisabled(true);
    
    if (browser->GetHost()->GetExtension()) {
      // Browsers hosting extension apps should auto-resize.
      browser->GetHost()->SetAutoResizeEnabled(true, CefSize(20, 20),
                                               CefSize(1000, 1000));
      
      CefRefPtr<CefExtension> extension = browser->GetHost()->GetExtension();
      if (utils::IsInternalExtension(extension->GetPath())) {
        // Register the internal handler for extension resources.
        utils::AddInternalExtensionToResourceManager(extension, resource_manager_);
      }
    }
    
    NotifyBrowserCreated(browser);
  }
  
  bool ClientHandler::DoClose(CefRefPtr<CefBrowser> browser) {
    CEF_REQUIRE_UI_THREAD();
    
    NotifyBrowserClosing(browser);
    
    // Allow the close. For windowed browsers this will result in the OS close
    // event being sent.
    return false;
  }
  
  void ClientHandler::OnBeforeClose(CefRefPtr<CefBrowser> browser) {
    CEF_REQUIRE_UI_THREAD();
    
    NotifyBrowserClosed(browser);
  }
  
  void ClientHandler::OnLoadingStateChange(CefRefPtr<CefBrowser> browser,
                                           bool isLoading,
                                           bool canGoBack,
                                           bool canGoForward) {
    CEF_REQUIRE_UI_THREAD();
    
    if (!isLoading && initial_navigation_) {
      initial_navigation_ = false;
    }
    
    NotifyLoadingState(isLoading, canGoBack, canGoForward);
  }
  
  void ClientHandler::OnLoadError(CefRefPtr<CefBrowser> browser,
                                  CefRefPtr<CefFrame> frame,
                                  ErrorCode errorCode,
                                  const CefString& errorText,
                                  const CefString& failedUrl) {
    CEF_REQUIRE_UI_THREAD();
    
    // Don't display an error for downloaded files.
    if (errorCode == ERR_ABORTED)
      return;
    
    // Don't display an error for external protocols that we allow the OS to
    // handle. See OnProtocolExecution().
    if (errorCode == ERR_UNKNOWN_URL_SCHEME) {
      std::string urlStr = frame->GetURL();
      if (urlStr.find("spotify:") == 0)
        return;
    }
    
    // Load the error page.
    LoadErrorPage(frame, failedUrl, errorCode, errorText);
  }
  
  bool ClientHandler::OnBeforeBrowse(CefRefPtr<CefBrowser> browser,
                                     CefRefPtr<CefFrame> frame,
                                     CefRefPtr<CefRequest> request,
                                     bool user_gesture,
                                     bool is_redirect) {
    CEF_REQUIRE_UI_THREAD();
    
    return false;
  }
  
  bool ClientHandler::OnOpenURLFromTab(
                                       CefRefPtr<CefBrowser> browser,
                                       CefRefPtr<CefFrame> frame,
                                       const CefString& target_url,
                                       CefRequestHandler::WindowOpenDisposition target_disposition,
                                       bool user_gesture) {
    if (target_disposition == WOD_NEW_BACKGROUND_TAB ||
        target_disposition == WOD_NEW_FOREGROUND_TAB) {
      // Handle middle-click and ctrl + left-click by opening the URL in a new
      // browser window.
      RootWindowConfig config;
      config.with_controls = true;
      config.url = target_url;
      MainContext::Get()->GetRootWindowManager()->CreateRootWindow(config);
      return true;
    }
    
    // Open the URL in the current browser window.
    return false;
  }
  
  cef_return_value_t ClientHandler::OnBeforeResourceLoad(
                                                         CefRefPtr<CefBrowser> browser,
                                                         CefRefPtr<CefFrame> frame,
                                                         CefRefPtr<CefRequest> request,
                                                         CefRefPtr<CefRequestCallback> callback) {
    CEF_REQUIRE_IO_THREAD();
    
    return resource_manager_->OnBeforeResourceLoad(browser, frame, request,
                                                   callback);
  }
  
  CefRefPtr<CefResourceHandler> ClientHandler::GetResourceHandler(
                                                                  CefRefPtr<CefBrowser> browser,
                                                                  CefRefPtr<CefFrame> frame,
                                                                  CefRefPtr<CefRequest> request) {
    CEF_REQUIRE_IO_THREAD();
    
    return resource_manager_->GetResourceHandler(browser, frame, request);
  }
  
  
  bool ClientHandler::OnQuotaRequest(CefRefPtr<CefBrowser> browser,
                                     const CefString& origin_url,
                                     int64 new_size,
                                     CefRefPtr<CefRequestCallback> callback) {
    CEF_REQUIRE_IO_THREAD();
    
    static const int64 max_size = 1024 * 1024 * 20;  // 20mb.
    
    // Grant the quota request if the size is reasonable.
    callback->Continue(new_size <= max_size);
    return true;
  }
  
  void ClientHandler::OnProtocolExecution(CefRefPtr<CefBrowser> browser,
                                          const CefString& url,
                                          bool& allow_os_execution) {
    CEF_REQUIRE_UI_THREAD();
    
    std::string urlStr = url;
    
    // Allow OS execution of Spotify URIs.
    if (urlStr.find("spotify:") == 0)
      allow_os_execution = true;
  }
  
  bool ClientHandler::OnCertificateError(CefRefPtr<CefBrowser> browser,
                                         ErrorCode cert_error,
                                         const CefString& request_url,
                                         CefRefPtr<CefSSLInfo> ssl_info,
                                         CefRefPtr<CefRequestCallback> callback) {
    CEF_REQUIRE_UI_THREAD();
    
    if (cert_error == ERR_CERT_AUTHORITY_INVALID &&
        request_url.ToString().find("https://www.magpcss.org/") == 0U) {
      // Allow the CEF Forum to load. It has a self-signed certificate.
      callback->Continue(true);
      return true;
    }
    
    CefRefPtr<CefX509Certificate> cert = ssl_info->GetX509Certificate();
    if (cert.get()) {
      // Load the error page.
      LoadErrorPage(browser->GetMainFrame(), request_url, cert_error,
                    GetCertificateInformation(cert, ssl_info->GetCertStatus()));
    }
    
    return false;  // Cancel the request.
  }
  
  bool ClientHandler::OnSelectClientCertificate(
                                                CefRefPtr<CefBrowser> browser,
                                                bool isProxy,
                                                const CefString& host,
                                                int port,
                                                const X509CertificateList& certificates,
                                                CefRefPtr<CefSelectClientCertificateCallback> callback) {
    CEF_REQUIRE_UI_THREAD();
    
    CefRefPtr<CefCommandLine> command_line =
    CefCommandLine::GetGlobalCommandLine();
    if (!command_line->HasSwitch(switches::kSslClientCertificate)) {
      return false;
    }
    
    const std::string& cert_name =
    command_line->GetSwitchValue(switches::kSslClientCertificate);
    
    if (cert_name.empty()) {
      callback->Select(NULL);
      return true;
    }
    
    std::vector<CefRefPtr<CefX509Certificate>>::const_iterator it =
    certificates.begin();
    for (; it != certificates.end(); ++it) {
      CefString subject((*it)->GetSubject()->GetDisplayName());
      if (subject == cert_name) {
        callback->Select(*it);
        return true;
      }
    }
    
    return true;
  }
  
  int ClientHandler::GetBrowserCount() const {
    CEF_REQUIRE_UI_THREAD();
    return browser_count_;
  }
  
  void ClientHandler::ShowDevTools(CefRefPtr<CefBrowser> browser,
                                   const CefPoint& inspect_element_at) {
    if (!CefCurrentlyOn(TID_UI)) {
      // Execute this method on the UI thread.
      CefPostTask(TID_UI, base::Bind(&ClientHandler::ShowDevTools, this, browser,
                                     inspect_element_at));
      return;
    }
    
    CefWindowInfo windowInfo;
    CefRefPtr<CefClient> client;
    CefBrowserSettings settings;
    
    MainContext::Get()->PopulateBrowserSettings(&settings);
    
    CefRefPtr<CefBrowserHost> host = browser->GetHost();
    
    // Test if the DevTools browser already exists.
    bool has_devtools = host->HasDevTools();
    if (!has_devtools) {
      // Create a new RootWindow for the DevTools browser that will be created
      // by ShowDevTools().
      has_devtools = CreatePopupWindow(browser, true, CefPopupFeatures(),
                                       windowInfo, client, settings);
    }
    
    if (has_devtools) {
      // Create the DevTools browser if it doesn't already exist.
      // Otherwise, focus the existing DevTools browser and inspect the element
      // at |inspect_element_at| if non-empty.
      host->ShowDevTools(windowInfo, client, settings, inspect_element_at);
    }
  }
  
  void ClientHandler::CloseDevTools(CefRefPtr<CefBrowser> browser) {
    browser->GetHost()->CloseDevTools();
  }
  
  bool ClientHandler::HasSSLInformation(CefRefPtr<CefBrowser> browser) {
    CefRefPtr<CefNavigationEntry> nav =
    browser->GetHost()->GetVisibleNavigationEntry();
    
    return (nav && nav->GetSSLStatus() &&
            nav->GetSSLStatus()->IsSecureConnection());
  }
  
  void ClientHandler::ShowSSLInformation(CefRefPtr<CefBrowser> browser) {
    std::stringstream ss;
    CefRefPtr<CefNavigationEntry> nav =
    browser->GetHost()->GetVisibleNavigationEntry();
    if (!nav)
      return;
    
    CefRefPtr<CefSSLStatus> ssl = nav->GetSSLStatus();
    if (!ssl)
      return;
    
    ss << "<html><head><title>SSL Information</title></head>"
    "<body bgcolor=\"white\">"
    "<h3>SSL Connection</h3>"
    << "<table border=1><tr><th>Field</th><th>Value</th></tr>";
    
    CefURLParts urlparts;
    if (CefParseURL(nav->GetURL(), urlparts)) {
      CefString port(&urlparts.port);
      ss << "<tr><td>Server</td><td>" << CefString(&urlparts.host).ToString();
      if (!port.empty())
        ss << ":" << port.ToString();
      ss << "</td></tr>";
    }
    
    ss << "<tr><td>SSL Version</td><td>"
    << GetSSLVersionString(ssl->GetSSLVersion()) << "</td></tr>";
    ss << "<tr><td>Content Status</td><td>"
    << GetContentStatusString(ssl->GetContentStatus()) << "</td></tr>";
    
    ss << "</table>";
    
    CefRefPtr<CefX509Certificate> cert = ssl->GetX509Certificate();
    if (cert.get())
      ss << GetCertificateInformation(cert, ssl->GetCertStatus());
    
    ss << "</body></html>";
    
    RootWindowConfig config;
    config.with_controls = false;
    config.url = utils::GetDataURI(ss.str(), "text/html");
    MainContext::Get()->GetRootWindowManager()->CreateRootWindow(config);
  }
  
  bool ClientHandler::CreatePopupWindow(CefRefPtr<CefBrowser> browser,
                                        bool is_devtools,
                                        const CefPopupFeatures& popupFeatures,
                                        CefWindowInfo& windowInfo,
                                        CefRefPtr<CefClient>& client,
                                        CefBrowserSettings& settings) {
    CEF_REQUIRE_UI_THREAD();
    
    // The popup browser will be parented to a new native window.
    // Don't show URL bar and navigation buttons on DevTools windows.
    MainContext::Get()->GetRootWindowManager()->CreateRootWindowAsPopup(!is_devtools, popupFeatures, windowInfo, client, settings);
    
    return true;
  }
  
  void ClientHandler::NotifyBrowserCreated(CefRefPtr<CefBrowser> browser) {
    if (!CURRENTLY_ON_MAIN_THREAD()) {
      // Execute this method on the main thread.
      MAIN_POST_CLOSURE(
                        base::Bind(&ClientHandler::NotifyBrowserCreated, this, browser));
      return;
    }
    
    if (delegate_)
      delegate_->OnBrowserCreated(browser);
  }
  
  void ClientHandler::NotifyBrowserClosing(CefRefPtr<CefBrowser> browser) {
    if (!CURRENTLY_ON_MAIN_THREAD()) {
      // Execute this method on the main thread.
      MAIN_POST_CLOSURE(
                        base::Bind(&ClientHandler::NotifyBrowserClosing, this, browser));
      return;
    }
    
    if (delegate_)
      delegate_->OnBrowserClosing(browser);
  }
  
  void ClientHandler::NotifyBrowserClosed(CefRefPtr<CefBrowser> browser) {
    if (!CURRENTLY_ON_MAIN_THREAD()) {
      // Execute this method on the main thread.
      MAIN_POST_CLOSURE(
                        base::Bind(&ClientHandler::NotifyBrowserClosed, this, browser));
      return;
    }
    
    if (delegate_)
      delegate_->OnBrowserClosed(browser);
  }
  
  void ClientHandler::NotifyAddress(const CefString& url) {
    if (!CURRENTLY_ON_MAIN_THREAD()) {
      // Execute this method on the main thread.
      MAIN_POST_CLOSURE(base::Bind(&ClientHandler::NotifyAddress, this, url));
      return;
    }
    
    if (delegate_)
      delegate_->OnSetAddress(url);
  }
  
  void ClientHandler::NotifyTitle(const CefString& title) {
    if (!CURRENTLY_ON_MAIN_THREAD()) {
      // Execute this method on the main thread.
      MAIN_POST_CLOSURE(base::Bind(&ClientHandler::NotifyTitle, this, title));
      return;
    }
    
    if (delegate_)
      delegate_->OnSetTitle(title);
  }
  
  void ClientHandler::NotifyFavicon(CefRefPtr<CefImage> image) {
    if (!CURRENTLY_ON_MAIN_THREAD()) {
      // Execute this method on the main thread.
      MAIN_POST_CLOSURE(base::Bind(&ClientHandler::NotifyFavicon, this, image));
      return;
    }
    
    if (delegate_)
      delegate_->OnSetFavicon(image);
  }
  
  void ClientHandler::NotifyFullscreen(bool fullscreen) {
    if (!CURRENTLY_ON_MAIN_THREAD()) {
      // Execute this method on the main thread.
      MAIN_POST_CLOSURE(
                        base::Bind(&ClientHandler::NotifyFullscreen, this, fullscreen));
      return;
    }
    
    if (delegate_)
      delegate_->OnSetFullscreen(fullscreen);
  }
  
  void ClientHandler::NotifyAutoResize(const CefSize& new_size) {
    if (!CURRENTLY_ON_MAIN_THREAD()) {
      // Execute this method on the main thread.
      MAIN_POST_CLOSURE(
                        base::Bind(&ClientHandler::NotifyAutoResize, this, new_size));
      return;
    }
    
    if (delegate_)
      delegate_->OnAutoResize(new_size);
  }
  
  void ClientHandler::NotifyLoadingState(bool isLoading,
                                         bool canGoBack,
                                         bool canGoForward) {
    if (!CURRENTLY_ON_MAIN_THREAD()) {
      // Execute this method on the main thread.
      MAIN_POST_CLOSURE(base::Bind(&ClientHandler::NotifyLoadingState, this,
                                   isLoading, canGoBack, canGoForward));
      return;
    }
    
    if (delegate_)
      delegate_->OnSetLoadingState(isLoading, canGoBack, canGoForward);
  }
  
  void ClientHandler::NotifyDraggableRegions(const std::vector<CefDraggableRegion>& regions) {
    if (!CURRENTLY_ON_MAIN_THREAD()) {
      // Execute this method on the main thread.
      MAIN_POST_CLOSURE(base::Bind(&ClientHandler::NotifyDraggableRegions, this, regions));
      return;
    }
    
    if (delegate_) {
      delegate_->OnSetDraggableRegions(regions);
    }
  }
  
  void ClientHandler::NotifyTakeFocus(bool next) {
    if (!CURRENTLY_ON_MAIN_THREAD()) {
      // Execute this method on the main thread.
      MAIN_POST_CLOSURE(base::Bind(&ClientHandler::NotifyTakeFocus, this, next));
      return;
    }
    
    if (delegate_) {
      delegate_->OnTakeFocus(next);
    }
  }
  
  void ClientHandler::BuildTestMenu(CefRefPtr<CefMenuModel> model) {
    if (model->GetCount() > 0)
      model->AddSeparator();
    
    // Build the sub menu.
    CefRefPtr<CefMenuModel> submenu = model->AddSubMenu(CLIENT_ID_TESTMENU_SUBMENU, "Context Menu Test");
    submenu->AddCheckItem(CLIENT_ID_TESTMENU_CHECKITEM, "Check Item");
    submenu->AddRadioItem(CLIENT_ID_TESTMENU_RADIOITEM1, "Radio Item 1", 0);
    submenu->AddRadioItem(CLIENT_ID_TESTMENU_RADIOITEM2, "Radio Item 2", 0);
    submenu->AddRadioItem(CLIENT_ID_TESTMENU_RADIOITEM3, "Radio Item 3", 0);
    
    // Check the check item.
    if (test_menu_state_.check_item) {
       submenu->SetChecked(CLIENT_ID_TESTMENU_CHECKITEM, true);
    }
    
    // Check the selected radio item.
    submenu->SetChecked(CLIENT_ID_TESTMENU_RADIOITEM1 + test_menu_state_.radio_item, true);
  }
  
  bool ClientHandler::ExecuteTestMenu(int command_id) {
    if (command_id == CLIENT_ID_TESTMENU_CHECKITEM) {
      // Toggle the check item.
      test_menu_state_.check_item ^= 1;
      return true;
    } else if (command_id >= CLIENT_ID_TESTMENU_RADIOITEM1 &&
               command_id <= CLIENT_ID_TESTMENU_RADIOITEM3) {
      // Store the selected radio item.
      test_menu_state_.radio_item = (command_id - CLIENT_ID_TESTMENU_RADIOITEM1);
      return true;
    }
    
    // Allow default handling to proceed.
    return false;
  }
  
}  // namespace client

