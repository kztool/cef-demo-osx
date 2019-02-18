// Copyright (c) 2015 The Chromium Embedded Framework Authors. All rights
// reserved. Use of this source code is governed by a BSD-style license that
// can be found in the LICENSE file.

#include "browser/test_runner.h"

#include <sstream>

#include "include/base/cef_bind.h"
#include "include/cef_parser.h"
#include "include/cef_task.h"
#include "include/cef_trace.h"
#include "include/cef_web_plugin.h"
#include "include/wrapper/cef_closure_task.h"
#include "include/wrapper/cef_stream_resource_handler.h"
#include "browser/main_context.h"
#include "browser/root_window_manager.h"

#include "browser/utils.h"

namespace client {
  namespace test_runner {
    namespace {
      const char kTestHost[] = "tests";
      const char kLocalHost[] = "localhost";
      const char kTestOrigin[] = "http://tests/";
      
      // Replace all instances of |from| with |to| in |str|.
      std::string StringReplace(const std::string& str,
                                const std::string& from,
                                const std::string& to) {
        std::string result = str;
        std::string::size_type pos = 0;
        std::string::size_type from_len = from.length();
        std::string::size_type to_len = to.length();
        do {
          pos = result.find(from, pos);
          if (pos != std::string::npos) {
            result.replace(pos, from_len, to);
            pos += to_len;
          }
        } while (pos != std::string::npos);
        return result;
      }
      
      // Provider that dumps the request contents.
      class RequestDumpResourceProvider : public CefResourceManager::Provider {
      public:
        explicit RequestDumpResourceProvider(const std::string& url) : url_(url) {
          DCHECK(!url.empty());
        }
        
        bool OnRequest(scoped_refptr<CefResourceManager::Request> request) OVERRIDE {
          CEF_REQUIRE_IO_THREAD();
          
          const std::string& url = request->url();
          if (url != url_) {
            // Not handled by this provider.
            return false;
          }
          
          CefResponse::HeaderMap response_headers;
          CefRefPtr<CefStreamReader> response =
          GetDumpResponse(request->request(), response_headers);
          
          request->Continue(new CefStreamResourceHandler(200, "OK", "text/html",
                                                         response_headers, response));
          return true;
        }
        
      private:
        std::string url_;
        
        DISALLOW_COPY_AND_ASSIGN(RequestDumpResourceProvider);
      };
      
      // Add a file extension to |url| if none is currently specified.
      std::string RequestUrlFilter(const std::string& url) {
        if (url.find(kTestOrigin) != 0U) {
          // Don't filter anything outside of the test origin.
          return url;
        }
        
        // Identify where the query or fragment component, if any, begins.
        size_t suffix_pos = url.find('?');
        if (suffix_pos == std::string::npos)
          suffix_pos = url.find('#');
        
        std::string url_base, url_suffix;
        if (suffix_pos == std::string::npos) {
          url_base = url;
        } else {
          url_base = url.substr(0, suffix_pos);
          url_suffix = url.substr(suffix_pos);
        }
        
        // Identify the last path component.
        size_t path_pos = url_base.rfind('/');
        if (path_pos == std::string::npos)
          return url;
        
        const std::string& path_component = url_base.substr(path_pos);
        
        // Identify if a file extension is currently specified.
        size_t ext_pos = path_component.rfind(".");
        if (ext_pos != std::string::npos)
          return url;
        
        // Rebuild the URL with a file extension.
        return url_base + ".html" + url_suffix;
      }
      
    }  // namespace
    
    std::string DumpRequestContents(CefRefPtr<CefRequest> request) {
      std::stringstream ss;
      
      ss << "URL: " << std::string(request->GetURL());
      ss << "\nMethod: " << std::string(request->GetMethod());
      
      CefRequest::HeaderMap headerMap;
      request->GetHeaderMap(headerMap);
      if (headerMap.size() > 0) {
        ss << "\nHeaders:";
        CefRequest::HeaderMap::const_iterator it = headerMap.begin();
        for (; it != headerMap.end(); ++it) {
          ss << "\n\t" << std::string((*it).first) << ": "
          << std::string((*it).second);
        }
      }
      
      CefRefPtr<CefPostData> postData = request->GetPostData();
      if (postData.get()) {
        CefPostData::ElementVector elements;
        postData->GetElements(elements);
        if (elements.size() > 0) {
          ss << "\nPost Data:";
          CefRefPtr<CefPostDataElement> element;
          CefPostData::ElementVector::const_iterator it = elements.begin();
          for (; it != elements.end(); ++it) {
            element = (*it);
            if (element->GetType() == PDE_TYPE_BYTES) {
              // the element is composed of bytes
              ss << "\n\tBytes: ";
              if (element->GetBytesCount() == 0) {
                ss << "(empty)";
              } else {
                // retrieve the data.
                size_t size = element->GetBytesCount();
                char* bytes = new char[size];
                element->GetBytes(size, bytes);
                ss << std::string(bytes, size);
                delete[] bytes;
              }
            } else if (element->GetType() == PDE_TYPE_FILE) {
              ss << "\n\tFile: " << std::string(element->GetFile());
            }
          }
        }
      }
      
      return ss.str();
    }
    
    CefRefPtr<CefStreamReader> GetDumpResponse(CefRefPtr<CefRequest> request, CefResponse::HeaderMap& response_headers) {
      std::string origin;
      
      // Extract the origin request header, if any. It will be specified for
      // cross-origin requests.
      {
        CefRequest::HeaderMap requestMap;
        request->GetHeaderMap(requestMap);
        
        CefRequest::HeaderMap::const_iterator it = requestMap.begin();
        for (; it != requestMap.end(); ++it) {
          std::string key = it->first;
          std::transform(key.begin(), key.end(), key.begin(), ::tolower);
          if (key == "origin") {
            origin = it->second;
            break;
          }
        }
      }
      
      if (!origin.empty() &&
          (origin.find("http://" + std::string(kTestHost)) == 0 ||
           origin.find("http://" + std::string(kLocalHost)) == 0)) {
            // Allow cross-origin XMLHttpRequests from test origins.
            response_headers.insert(std::make_pair("Access-Control-Allow-Origin", origin));
            
            // Allow the custom header from the xmlhttprequest.html example.
            response_headers.insert(std::make_pair("Access-Control-Allow-Headers", "My-Custom-Header"));
          }
      
      const std::string& dump = DumpRequestContents(request);
      std::string str =
      "<html><body bgcolor=\"white\"><pre>" + dump + "</pre></body></html>";
      CefRefPtr<CefStreamReader> stream = CefStreamReader::CreateForData(
                                                                         static_cast<void*>(const_cast<char*>(str.c_str())), str.size());
      DCHECK(stream);
      return stream;
    }
    
    std::string GetDataURI(const std::string& data, const std::string& mime_type) {
      return "data:" + mime_type + ";base64," +
      CefURIEncode(CefBase64Encode(data.data(), data.size()), false)
      .ToString();
    }
    
    std::string GetErrorString(cef_errorcode_t code) {
      // Case condition that returns |code| as a string.
#define CASE(code) \
case code:       \
return #code
      
      switch (code) {
          CASE(ERR_NONE);
          CASE(ERR_FAILED);
          CASE(ERR_ABORTED);
          CASE(ERR_INVALID_ARGUMENT);
          CASE(ERR_INVALID_HANDLE);
          CASE(ERR_FILE_NOT_FOUND);
          CASE(ERR_TIMED_OUT);
          CASE(ERR_FILE_TOO_BIG);
          CASE(ERR_UNEXPECTED);
          CASE(ERR_ACCESS_DENIED);
          CASE(ERR_NOT_IMPLEMENTED);
          CASE(ERR_CONNECTION_CLOSED);
          CASE(ERR_CONNECTION_RESET);
          CASE(ERR_CONNECTION_REFUSED);
          CASE(ERR_CONNECTION_ABORTED);
          CASE(ERR_CONNECTION_FAILED);
          CASE(ERR_NAME_NOT_RESOLVED);
          CASE(ERR_INTERNET_DISCONNECTED);
          CASE(ERR_SSL_PROTOCOL_ERROR);
          CASE(ERR_ADDRESS_INVALID);
          CASE(ERR_ADDRESS_UNREACHABLE);
          CASE(ERR_SSL_CLIENT_AUTH_CERT_NEEDED);
          CASE(ERR_TUNNEL_CONNECTION_FAILED);
          CASE(ERR_NO_SSL_VERSIONS_ENABLED);
          CASE(ERR_SSL_VERSION_OR_CIPHER_MISMATCH);
          CASE(ERR_SSL_RENEGOTIATION_REQUESTED);
          CASE(ERR_CERT_COMMON_NAME_INVALID);
          CASE(ERR_CERT_DATE_INVALID);
          CASE(ERR_CERT_AUTHORITY_INVALID);
          CASE(ERR_CERT_CONTAINS_ERRORS);
          CASE(ERR_CERT_NO_REVOCATION_MECHANISM);
          CASE(ERR_CERT_UNABLE_TO_CHECK_REVOCATION);
          CASE(ERR_CERT_REVOKED);
          CASE(ERR_CERT_INVALID);
          CASE(ERR_CERT_END);
          CASE(ERR_INVALID_URL);
          CASE(ERR_DISALLOWED_URL_SCHEME);
          CASE(ERR_UNKNOWN_URL_SCHEME);
          CASE(ERR_TOO_MANY_REDIRECTS);
          CASE(ERR_UNSAFE_REDIRECT);
          CASE(ERR_UNSAFE_PORT);
          CASE(ERR_INVALID_RESPONSE);
          CASE(ERR_INVALID_CHUNKED_ENCODING);
          CASE(ERR_METHOD_NOT_SUPPORTED);
          CASE(ERR_UNEXPECTED_PROXY_AUTH);
          CASE(ERR_EMPTY_RESPONSE);
          CASE(ERR_RESPONSE_HEADERS_TOO_BIG);
          CASE(ERR_CACHE_MISS);
          CASE(ERR_INSECURE_RESPONSE);
        default:
          return "UNKNOWN";
      }
    }
    
    void SetupResourceManager(CefRefPtr<CefResourceManager> resource_manager) {
      if (!CefCurrentlyOn(TID_IO)) {
        // Execute on the browser IO thread.
        CefPostTask(TID_IO, base::Bind(SetupResourceManager, resource_manager));
        return;
      }
      
      const std::string& test_origin = kTestOrigin;
      
      // Add the URL filter.
      resource_manager->SetUrlFilter(base::Bind(RequestUrlFilter));
      
      // Add provider for resource dumps.
      resource_manager->AddProvider(new RequestDumpResourceProvider(test_origin + "request.html"), 0, std::string());
      
      // Read resources from a directory on disk.
      std::string resource_dir;
      if (GetResourceDir(resource_dir)) {
        resource_manager->AddDirectoryProvider(test_origin, resource_dir, 100,
                                               std::string());
      }
    }
    
    void Alert(CefRefPtr<CefBrowser> browser, const std::string& message) {
      if (browser->GetHost()->GetExtension()) {
        // Alerts originating from extension hosts should instead be displayed in
        // the active browser.
        browser = MainContext::Get()->GetRootWindowManager()->GetActiveBrowser();
        if (!browser)
          return;
      }
      
      // Escape special characters in the message.
      std::string msg = StringReplace(message, "\\", "\\\\");
      msg = StringReplace(msg, "'", "\\'");
      
      // Execute a JavaScript alert().
      CefRefPtr<CefFrame> frame = browser->GetMainFrame();
      frame->ExecuteJavaScript("alert('" + msg + "');", frame->GetURL(), 0);
    }
  }  // namespace test_runner
}  // namespace client

