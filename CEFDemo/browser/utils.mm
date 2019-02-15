//
//  utils.mm
//  CEFDemo
//
//  Created by 田硕 on 2019/2/15.
//  Copyright © 2019 田硕. All rights reserved.
//

#include "utils.h"

namespace client {
  namespace file_util {
    // namespace private functions
    namespace {
      bool AllowFileIO() {
        if (CefCurrentlyOn(TID_UI) || CefCurrentlyOn(TID_IO)) {
          NOTREACHED() << "file IO is not allowed on the current thread";
          return false;
        }
        return true;
      }
    }  // namespace
    
    const char kPathSep = '/';
    
    bool ReadFileToString(const std::string& path,
                          std::string* contents,
                          size_t max_size) {
      if (!AllowFileIO())
        return false;
      
      if (contents)
        contents->clear();
      FILE* file = fopen(path.c_str(), "rb");
      if (!file)
        return false;
      
      const size_t kBufferSize = 1 << 16;
      scoped_ptr<char[]> buf(new char[kBufferSize]);
      size_t len;
      size_t size = 0;
      bool read_status = true;
      
      // Many files supplied in |path| have incorrect size (proc files etc).
      // Hence, the file is read sequentially as opposed to a one-shot read.
      while ((len = fread(buf.get(), 1, kBufferSize, file)) > 0) {
        if (contents)
          contents->append(buf.get(), std::min(len, max_size - size));
        
        if ((max_size - size) < len) {
          read_status = false;
          break;
        }
        
        size += len;
      }
      read_status = read_status && !ferror(file);
      fclose(file);
      
      return read_status;
    }
    
    int WriteFile(const std::string& path, const char* data, int size) {
      if (!AllowFileIO())
        return -1;
      
      FILE* file = fopen(path.c_str(), "wb");
      if (!file)
        return -1;
      
      int written = 0;
      
      do {
        size_t write = fwrite(data + written, 1, size - written, file);
        if (write == 0)
          break;
        written += static_cast<int>(write);
      } while (written < size);
      
      fclose(file);
      
      return written;
    }
    
    std::string JoinPath(const std::string& path1, const std::string& path2) {
      if (path1.empty() && path2.empty())
        return std::string();
      if (path1.empty())
        return path2;
      if (path2.empty())
        return path1;
      
      std::string result = path1;
      if (result[result.size() - 1] != kPathSep)
        result += kPathSep;
      if (path2[0] == kPathSep)
        result += path2.substr(1);
      else
        result += path2;
      return result;
    }
    
    std::string GetFileExtension(const std::string& path) {
      size_t sep = path.find_last_of(".");
      if (sep != std::string::npos)
        return path.substr(sep + 1);
      return std::string();
    }
  } // namespace file_util
} // namespace client


namespace client {
  namespace extension_util {
    // namespace private functions
    namespace {
      std::string GetResourcesPath() {
        CefString resources_dir;
        if (CefGetPath(PK_DIR_RESOURCES, resources_dir) && !resources_dir.empty()) {
          return resources_dir.ToString() + file_util::kPathSep;
        }
        return std::string();
      }
      
      // Internal extension paths may be prefixed with PK_DIR_RESOURCES and always
      // use forward slash as path separator.
      std::string GetInternalPath(const std::string& extension_path) {
        const std::string& resources_path = GetResourcesPath();
        std::string internal_path;
        if (!resources_path.empty() && extension_path.find(resources_path) == 0U) {
          internal_path = extension_path.substr(resources_path.size());
        } else {
          internal_path = extension_path;
        }
        
        return internal_path;
      }
      
      typedef base::Callback<void(CefRefPtr<CefDictionaryValue> /*manifest*/)> ManifestCallback;
      
      void RunManifestCallback(const ManifestCallback& callback,
                               CefRefPtr<CefDictionaryValue> manifest) {
        if (!CefCurrentlyOn(TID_UI)) {
          // Execute on the browser UI thread.
          CefPostTask(TID_UI, base::Bind(RunManifestCallback, callback, manifest));
          return;
        }
        callback.Run(manifest);
      }
      
      // Asynchronously reads the manifest and executes |callback| on the UI thread.
      void GetInternalManifest(const std::string& extension_path,
                               const ManifestCallback& callback) {
        if (!CefCurrentlyOn(TID_FILE)) {
          // Execute on the browser FILE thread.
          CefPostTask(TID_FILE,
                      base::Bind(GetInternalManifest, extension_path, callback));
          return;
        }
        
        const std::string& manifest_path = GetInternalExtensionResourcePath(
                                                                            file_util::JoinPath(extension_path, "manifest.json"));
        std::string manifest_contents;
        if (!LoadBinaryResource(manifest_path.c_str(), manifest_contents) ||
            manifest_contents.empty()) {
          LOG(ERROR) << "Failed to load manifest from " << manifest_path;
          RunManifestCallback(callback, NULL);
          return;
        }
        
        cef_json_parser_error_t error_code;
        CefString error_msg;
        CefRefPtr<CefValue> value = CefParseJSONAndReturnError(
                                                               manifest_contents, JSON_PARSER_RFC, error_code, error_msg);
        if (!value || value->GetType() != VTYPE_DICTIONARY) {
          if (error_msg.empty())
            error_msg = "Incorrectly formatted dictionary contents.";
          LOG(ERROR) << "Failed to parse manifest from " << manifest_path << "; "
          << error_msg.ToString();
          RunManifestCallback(callback, NULL);
          return;
        }
        
        RunManifestCallback(callback, value->GetDictionary());
      }
      
      void LoadExtensionWithManifest(CefRefPtr<CefRequestContext> request_context,
                                     const std::string& extension_path,
                                     CefRefPtr<CefExtensionHandler> handler,
                                     CefRefPtr<CefDictionaryValue> manifest) {
        CEF_REQUIRE_UI_THREAD();
        
        // Load the extension internally. Resource requests will be handled via
        // AddInternalExtensionToResourceManager.
        request_context->LoadExtension(extension_path, manifest, handler);
      }
    }  // namespace
    
    bool IsInternalExtension(const std::string& extension_path) {
      // List of internally handled extensions.
      static const char* extensions[] = {"set_page_color"};
      
      const std::string& internal_path = GetInternalPath(extension_path);
      for (size_t i = 0; i < arraysize(extensions); ++i) {
        // Exact match or first directory component.
        const std::string& extension = extensions[i];
        if (internal_path == extension ||
            internal_path.find(extension + '/') == 0) {
          return true;
        }
      }
      
      return false;
    }
    
    std::string GetInternalExtensionResourcePath(
                                                 const std::string& extension_path) {
      return "extensions/" + GetInternalPath(extension_path);
    }
    
    std::string GetExtensionResourcePath(const std::string& extension_path,
                                         bool* internal) {
      const bool is_internal = IsInternalExtension(extension_path);
      if (internal)
        *internal = is_internal;
      if (is_internal)
        return GetInternalExtensionResourcePath(extension_path);
      return extension_path;
    }
    
    bool GetExtensionResourceContents(const std::string& extension_path,
                                      std::string& contents) {
      CEF_REQUIRE_FILE_THREAD();
      
      if (IsInternalExtension(extension_path)) {
        const std::string& contents_path =
        GetInternalExtensionResourcePath(extension_path);
        return LoadBinaryResource(contents_path.c_str(), contents);
      }
      
      return file_util::ReadFileToString(extension_path, &contents);
    }
    
    void LoadExtension(CefRefPtr<CefRequestContext> request_context,
                       const std::string& extension_path,
                       CefRefPtr<CefExtensionHandler> handler) {
      if (!CefCurrentlyOn(TID_UI)) {
        // Execute on the browser UI thread.
        CefPostTask(TID_UI, base::Bind(LoadExtension, request_context,
                                       extension_path, handler));
        return;
      }
      
      if (IsInternalExtension(extension_path)) {
        // Read the extension manifest and load asynchronously.
        GetInternalManifest(extension_path,
                            base::Bind(LoadExtensionWithManifest, request_context,
                                       extension_path, handler));
      } else {
        // Load the extension from disk.
        request_context->LoadExtension(extension_path, NULL, handler);
      }
    }
    
    void AddInternalExtensionToResourceManager(
                                               CefRefPtr<CefExtension> extension,
                                               CefRefPtr<CefResourceManager> resource_manager) {
      DCHECK(IsInternalExtension(extension->GetPath()));
      
      if (!CefCurrentlyOn(TID_IO)) {
        // Execute on the browser IO thread.
        CefPostTask(TID_IO, base::Bind(AddInternalExtensionToResourceManager,
                                       extension, resource_manager));
        return;
      }
      
      const std::string& origin = GetExtensionOrigin(extension->GetIdentifier());
      const std::string& resource_path =
      GetInternalExtensionResourcePath(extension->GetPath());
      
      // Read resources from a directory on disk.
      std::string resource_dir;
      if (GetResourceDir(resource_dir)) {
        resource_dir += "/" + resource_path;
        resource_manager->AddDirectoryProvider(origin, resource_dir, 50,
                                               std::string());
      }
    }
    
    std::string GetExtensionOrigin(const std::string& extension_id) {
      return "chrome-extension://" + extension_id + "/";
    }
    
    std::string GetExtensionURL(CefRefPtr<CefExtension> extension) {
      CefRefPtr<CefDictionaryValue> browser_action =
      extension->GetManifest()->GetDictionary("browser_action");
      if (browser_action) {
        const std::string& default_popup =
        browser_action->GetString("default_popup");
        if (!default_popup.empty())
          return GetExtensionOrigin(extension->GetIdentifier()) + default_popup;
      }
      
      return std::string();
    }
    
    std::string GetExtensionIconPath(CefRefPtr<CefExtension> extension,
                                     bool* internal) {
      CefRefPtr<CefDictionaryValue> browser_action =
      extension->GetManifest()->GetDictionary("browser_action");
      if (browser_action) {
        const std::string& default_icon = browser_action->GetString("default_icon");
        if (!default_icon.empty()) {
          return GetExtensionResourcePath(
                                          file_util::JoinPath(extension->GetPath(), default_icon), internal);
        }
      }
      
      return std::string();
    }
  }  // namespace extension_util
}  // namespace client



namespace client {
  namespace {
    // Implementation adapted from Chromium's base/mac/foundation_util.mm
    bool UncachedAmIBundled() {
      return [[[NSBundle mainBundle] bundlePath] hasSuffix:@".app"];
    }
    
    bool AmIBundled() {
      static bool am_i_bundled = UncachedAmIBundled();
      return am_i_bundled;
    }
    
    bool FileExists(const char* path) {
      FILE* f = fopen(path, "rb");
      if (f) {
        fclose(f);
        return true;
      }
      return false;
    }
    
    bool ReadFileToString(const char* path, std::string& data) {
      // Implementation adapted from base/file_util.cc
      FILE* file = fopen(path, "rb");
      if (!file)
        return false;
      
      char buf[1 << 16];
      size_t len;
      while ((len = fread(buf, 1, sizeof(buf), file)) > 0)
        data.append(buf, len);
      fclose(file);
      
      return true;
    }
  }  // namespace
  
  bool LoadBinaryResource(const char* resource_name, std::string& resource_data) {
    std::string path;
    if (!GetResourceDir(path))
      return false;
    
    path.append("/");
    path.append(resource_name);
    
    return ReadFileToString(path.c_str(), resource_data);
  }
  
  CefRefPtr<CefStreamReader> GetBinaryResourceReader(const char* resource_name) {
    std::string path;
    if (!GetResourceDir(path))
      return NULL;
    
    path.append("/");
    path.append(resource_name);
    
    if (!FileExists(path.c_str()))
      return NULL;
    
    return CefStreamReader::CreateForFile(path);
  }
  
  // Implementation adapted from Chromium's base/base_path_mac.mm
  bool GetResourceDir(std::string& dir) {
    // Retrieve the executable directory.
    uint32_t pathSize = 0;
    _NSGetExecutablePath(NULL, &pathSize);
    if (pathSize > 0) {
      dir.resize(pathSize);
      _NSGetExecutablePath(const_cast<char*>(dir.c_str()), &pathSize);
    }
    
    if (AmIBundled()) {
      // Trim executable name up to the last separator.
      std::string::size_type last_separator = dir.find_last_of("/");
      dir.resize(last_separator);
      dir.append("/../Resources");
      return true;
    }
    
    dir.append("/Resources");
    return true;
  }
}  // namespace client
