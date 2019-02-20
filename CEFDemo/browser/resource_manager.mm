#include "resource_manager.h"

namespace client {
  namespace resource_manager {
    const char kTestHost[] = "tests";
    const char kLocalHost[] = "localhost";
    const char kTestOrigin[] = "http://tests/";
    
    namespace {      
      // Add a file extension to |url| if none is currently specified.
      std::string RequestUrlFilter(const std::string& url) {
        if (url.find(kTestOrigin) != 0U) {
          // Don't filter anything outside of the test origin.
          return url;
        }
        
        // Identify where the query or fragment component, if any, begins.
        size_t suffix_pos = url.find('?');
        if (suffix_pos == std::string::npos) {
          suffix_pos = url.find('#');
        }
        
        std::string url_base, url_suffix;
        if (suffix_pos == std::string::npos) {
          url_base = url;
        } else {
          url_base = url.substr(0, suffix_pos);
          url_suffix = url.substr(suffix_pos);
        }
        
        // Identify the last path component.
        size_t path_pos = url_base.rfind('/');
        if (path_pos == std::string::npos) {
          return url;
        }
        
        const std::string& path_component = url_base.substr(path_pos);
        
        // Identify if a file extension is currently specified.
        size_t ext_pos = path_component.rfind(".");
        if (ext_pos != std::string::npos) {
          return url;
        }
        
        // Rebuild the URL with a file extension.
        return url_base + ".html" + url_suffix;
      }
    
      // Returns the contents of the CefRequest as a string.
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
      
      // Returns the dump response as a stream. |request| is the request.
      // |response_headers| will be populated with extra response headers, if any.
      CefRefPtr<CefStreamReader> GetDumpResponse(CefRefPtr<CefRequest> request, CefResponse::HeaderMap& response_headers) {
        std::string origin;
        
        // Extract the origin request header, if any. It will be specified for
        // cross-origin requests.
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
        
        if (!origin.empty() && (origin.find("http://" + std::string(kTestHost)) == 0 || origin.find("http://" + std::string(kLocalHost)) == 0)) {
          // Allow cross-origin XMLHttpRequests from test origins.
          response_headers.insert(std::make_pair("Access-Control-Allow-Origin", origin));
          
          // Allow the custom header from the xmlhttprequest.html example.
          response_headers.insert(std::make_pair("Access-Control-Allow-Headers", "My-Custom-Header"));
        }
        
        const std::string& dump = DumpRequestContents(request);
        std::string str = "<html><body bgcolor=\"white\"><pre>" + dump + "</pre></body></html>";
        CefRefPtr<CefStreamReader> stream = CefStreamReader::CreateForData(static_cast<void*>(const_cast<char*>(str.c_str())), str.size());
        DCHECK(stream);
        return stream;
      }
      
      // Provider that dumps the request contents.
      class RequestDumpResourceProvider : public CefResourceManager::Provider {
      public:
        explicit RequestDumpResourceProvider(const std::string& url) : url_(url) {
          DCHECK(!url.empty());
        }
        
        bool OnRequest(CefRefPtr<CefResourceManager::Request> request) OVERRIDE {
          CEF_REQUIRE_IO_THREAD();
          
          const std::string& url = request->url();
          if (url != url_) {
            // Not handled by this provider.
            return false;
          }
          
          CefResponse::HeaderMap response_headers;
          CefRefPtr<CefStreamReader> response = GetDumpResponse(request->request(), response_headers);
          request->Continue(new CefStreamResourceHandler(200, "OK", "text/html", response_headers, response));
          return true;
        }
      private:
        std::string url_;
        DISALLOW_COPY_AND_ASSIGN(RequestDumpResourceProvider);
      };
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
      if (utils::GetResourceDir(resource_dir)) {
        resource_manager->AddDirectoryProvider(test_origin, resource_dir, 100, std::string());
      }
    }
  }
}
