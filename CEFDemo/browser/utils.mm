//
//  utils.mm
//  CEFDemo
//
//  Created by 田硕 on 2019/2/15.
//  Copyright © 2019 田硕. All rights reserved.
//

#import "utils.h"
#import "main_context.h"

namespace client {
  namespace utils {
    const char kPathSep = '/';
    
    namespace {   // ###### private functions ######
      bool AllowFileIO() {
        if (CefCurrentlyOn(TID_UI) || CefCurrentlyOn(TID_IO)) {
          NOTREACHED() << "file IO is not allowed on the current thread";
          return false;
        }
        return true;
      }
      
      bool AmIBundled() {
        static bool am_i_bundled = [[[NSBundle mainBundle] bundlePath] hasSuffix:@".app"];
        return am_i_bundled;
      }
      
      std::string GetResourcesPath() {
        CefString resources_dir;
        if (CefGetPath(PK_DIR_RESOURCES, resources_dir) && !resources_dir.empty()) {
          return resources_dir.ToString() + kPathSep;
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
        
        const std::string& manifest_path = GetInternalExtensionResourcePath(JoinPath(extension_path, "manifest.json"));
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
    }  // namespace
    

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
    
    bool FileExists(const char* path) {
      FILE* f = fopen(path, "rb");
      if (f) {
        fclose(f);
        return true;
      }
      return false;
    }
    
    std::string GetDataURI(const std::string& data, const std::string& mime_type) {
      return "data:" + mime_type + ";base64," + CefURIEncode(CefBase64Encode(data.data(), data.size()), false).ToString();
    }
    
    std::string GetErrorString(cef_errorcode_t code) {
      // Case condition that returns |code| as a string.
      switch (code) {
          CEFM_CASE(ERR_NONE);
          CEFM_CASE(ERR_FAILED);
          CEFM_CASE(ERR_ABORTED);
          CEFM_CASE(ERR_INVALID_ARGUMENT);
          CEFM_CASE(ERR_INVALID_HANDLE);
          CEFM_CASE(ERR_FILE_NOT_FOUND);
          CEFM_CASE(ERR_TIMED_OUT);
          CEFM_CASE(ERR_FILE_TOO_BIG);
          CEFM_CASE(ERR_UNEXPECTED);
          CEFM_CASE(ERR_ACCESS_DENIED);
          CEFM_CASE(ERR_NOT_IMPLEMENTED);
          CEFM_CASE(ERR_CONNECTION_CLOSED);
          CEFM_CASE(ERR_CONNECTION_RESET);
          CEFM_CASE(ERR_CONNECTION_REFUSED);
          CEFM_CASE(ERR_CONNECTION_ABORTED);
          CEFM_CASE(ERR_CONNECTION_FAILED);
          CEFM_CASE(ERR_NAME_NOT_RESOLVED);
          CEFM_CASE(ERR_INTERNET_DISCONNECTED);
          CEFM_CASE(ERR_SSL_PROTOCOL_ERROR);
          CEFM_CASE(ERR_ADDRESS_INVALID);
          CEFM_CASE(ERR_ADDRESS_UNREACHABLE);
          CEFM_CASE(ERR_SSL_CLIENT_AUTH_CERT_NEEDED);
          CEFM_CASE(ERR_TUNNEL_CONNECTION_FAILED);
          CEFM_CASE(ERR_NO_SSL_VERSIONS_ENABLED);
          CEFM_CASE(ERR_SSL_VERSION_OR_CIPHER_MISMATCH);
          CEFM_CASE(ERR_SSL_RENEGOTIATION_REQUESTED);
          CEFM_CASE(ERR_CERT_COMMON_NAME_INVALID);
          CEFM_CASE(ERR_CERT_DATE_INVALID);
          CEFM_CASE(ERR_CERT_AUTHORITY_INVALID);
          CEFM_CASE(ERR_CERT_CONTAINS_ERRORS);
          CEFM_CASE(ERR_CERT_NO_REVOCATION_MECHANISM);
          CEFM_CASE(ERR_CERT_UNABLE_TO_CHECK_REVOCATION);
          CEFM_CASE(ERR_CERT_REVOKED);
          CEFM_CASE(ERR_CERT_INVALID);
          CEFM_CASE(ERR_CERT_END);
          CEFM_CASE(ERR_INVALID_URL);
          CEFM_CASE(ERR_DISALLOWED_URL_SCHEME);
          CEFM_CASE(ERR_UNKNOWN_URL_SCHEME);
          CEFM_CASE(ERR_TOO_MANY_REDIRECTS);
          CEFM_CASE(ERR_UNSAFE_REDIRECT);
          CEFM_CASE(ERR_UNSAFE_PORT);
          CEFM_CASE(ERR_INVALID_RESPONSE);
          CEFM_CASE(ERR_INVALID_CHUNKED_ENCODING);
          CEFM_CASE(ERR_METHOD_NOT_SUPPORTED);
          CEFM_CASE(ERR_UNEXPECTED_PROXY_AUTH);
          CEFM_CASE(ERR_EMPTY_RESPONSE);
          CEFM_CASE(ERR_RESPONSE_HEADERS_TOO_BIG);
          CEFM_CASE(ERR_CACHE_MISS);
          CEFM_CASE(ERR_INSECURE_RESPONSE);
        default:
          return "UNKNOWN";
      }
    }
    
    bool LoadBinaryResource(const char* resource_name, std::string& resource_data) {
      std::string path;
      if (!GetResourceDir(path))
        return false;
      
      path.append("/");
      path.append(resource_name);
      
      return ReadFileToString(path, &resource_data);
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
      
      return ReadFileToString(extension_path, &contents);
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
          return GetExtensionResourcePath(JoinPath(extension->GetPath(), default_icon), internal);
        }
      }
      
      return std::string();
    }
  }
}

namespace client {
  BytesWriteHandler::BytesWriteHandler(size_t grow)
  : grow_(grow), datasize_(grow), offset_(0) {
    DCHECK_GT(grow, 0U);
    data_ = malloc(grow);
    DCHECK(data_ != NULL);
  }
  
  BytesWriteHandler::~BytesWriteHandler() {
    if (data_)
      free(data_);
  }
  
  size_t BytesWriteHandler::Write(const void* ptr, size_t size, size_t n) {
    base::AutoLock lock_scope(lock_);
    size_t rv;
    if (offset_ + static_cast<int64>(size * n) >= datasize_ &&
        Grow(size * n) == 0) {
      rv = 0;
    } else {
      memcpy(reinterpret_cast<char*>(data_) + offset_, ptr, size * n);
      offset_ += size * n;
      rv = n;
    }
    
    return rv;
  }
  
  int BytesWriteHandler::Seek(int64 offset, int whence) {
    int rv = -1L;
    base::AutoLock lock_scope(lock_);
    switch (whence) {
      case SEEK_CUR:
        if (offset_ + offset > datasize_ || offset_ + offset < 0)
          break;
        offset_ += offset;
        rv = 0;
        break;
      case SEEK_END: {
        int64 offset_abs = std::abs(offset);
        if (offset_abs > datasize_)
          break;
        offset_ = datasize_ - offset_abs;
        rv = 0;
        break;
      }
      case SEEK_SET:
        if (offset > datasize_ || offset < 0)
          break;
        offset_ = offset;
        rv = 0;
        break;
    }
    
    return rv;
  }
  
  int64 BytesWriteHandler::Tell() {
    base::AutoLock lock_scope(lock_);
    return offset_;
  }
  
  int BytesWriteHandler::Flush() {
    return 0;
  }
  
  size_t BytesWriteHandler::Grow(size_t size) {
    lock_.AssertAcquired();
    size_t rv;
    size_t s = (size > grow_ ? size : grow_);
    void* tmp = realloc(data_, datasize_ + s);
    DCHECK(tmp != NULL);
    if (tmp) {
      data_ = tmp;
      datasize_ += s;
      rv = datasize_;
    } else {
      rv = 0;
    }
    
    return rv;
  }
}  // namespace client

namespace client {
  namespace {
    const char kEmptyId[] = "__empty";
  }
  
  ImageCache::ImageCache() {}
  
  ImageCache::~ImageCache() {
    CEF_REQUIRE_UI_THREAD();
  }
  
  ImageCache::ImageRep::ImageRep(const std::string& path, float scale_factor)
  : path_(path), scale_factor_(scale_factor) {
    DCHECK(!path_.empty());
    DCHECK_GT(scale_factor_, 0.0f);
  }
  
  ImageCache::ImageInfo::ImageInfo(const std::string& id,
                                   const ImageRepSet& reps,
                                   bool internal,
                                   bool force_reload)
  : id_(id), reps_(reps), internal_(internal), force_reload_(force_reload) {
#ifndef NDEBUG
    DCHECK(!id_.empty());
    if (id_ != kEmptyId)
      DCHECK(!reps_.empty());
#endif
  }
  
  // static
  ImageCache::ImageInfo ImageCache::ImageInfo::Empty() {
    return ImageInfo(kEmptyId, ImageRepSet(), true, false);
  }
  
  // static
  ImageCache::ImageInfo ImageCache::ImageInfo::Create1x(
                                                        const std::string& id,
                                                        const std::string& path_1x,
                                                        bool internal) {
    ImageRepSet reps;
    reps.push_back(ImageRep(path_1x, 1.0f));
    return ImageInfo(id, reps, internal, false);
  }
  
  // static
  ImageCache::ImageInfo ImageCache::ImageInfo::Create2x(
                                                        const std::string& id,
                                                        const std::string& path_1x,
                                                        const std::string& path_2x,
                                                        bool internal) {
    ImageRepSet reps;
    reps.push_back(ImageRep(path_1x, 1.0f));
    reps.push_back(ImageRep(path_2x, 2.0f));
    return ImageInfo(id, reps, internal, false);
  }
  
  // static
  ImageCache::ImageInfo ImageCache::ImageInfo::Create2x(const std::string& id) {
    return Create2x(id, id + ".1x.png", id + ".2x.png", true);
  }
  
  struct ImageCache::ImageContent {
    ImageContent() {}
    
    struct RepContent {
      RepContent(ImageType type, float scale_factor, const std::string& contents)
      : type_(type), scale_factor_(scale_factor), contents_(contents) {}
      
      ImageType type_;
      float scale_factor_;
      std::string contents_;
    };
    typedef std::vector<RepContent> RepContentSet;
    RepContentSet contents_;
    
    CefRefPtr<CefImage> image_;
  };
  
  void ImageCache::LoadImages(const ImageInfoSet& image_info,
                              const LoadImagesCallback& callback) {
    DCHECK(!image_info.empty());
    DCHECK(!callback.is_null());
    
    if (!CefCurrentlyOn(TID_UI)) {
      CefPostTask(TID_UI, base::Bind(&ImageCache::LoadImages, this, image_info,
                                     callback));
      return;
    }
    
    ImageSet images;
    bool missing_images = false;
    
    ImageInfoSet::const_iterator it = image_info.begin();
    for (; it != image_info.end(); ++it) {
      const ImageInfo& info = *it;
      
      if (info.id_ == kEmptyId) {
        // Image intentionally left empty.
        images.push_back(NULL);
        continue;
      }
      
      ImageMap::iterator it2 = image_map_.find(info.id_);
      if (it2 != image_map_.end()) {
        if (!info.force_reload_) {
          // Image already exists.
          images.push_back(it2->second);
          continue;
        }
        
        // Remove the existing image from the map.
        image_map_.erase(it2);
      }
      
      // Load the image.
      images.push_back(NULL);
      if (!missing_images)
        missing_images = true;
    }
    
    if (missing_images) {
      CefPostTask(TID_FILE, base::Bind(&ImageCache::LoadMissing, this, image_info,
                                       images, callback));
    } else {
      callback.Run(images);
    }
  }
  
  CefRefPtr<CefImage> ImageCache::GetCachedImage(const std::string& image_id) {
    CEF_REQUIRE_UI_THREAD();
    DCHECK(!image_id.empty());
    
    ImageMap::const_iterator it = image_map_.find(image_id);
    if (it != image_map_.end())
      return it->second;
    
    return NULL;
  }
  
  // static
  ImageCache::ImageType ImageCache::GetImageType(const std::string& path) {
    std::string ext = utils::GetFileExtension(path);
    if (ext.empty())
      return TYPE_NONE;
    
    std::transform(ext.begin(), ext.end(), ext.begin(), tolower);
    if (ext == "png")
      return TYPE_PNG;
    if (ext == "jpg" || ext == "jpeg")
      return TYPE_JPEG;
    
    return TYPE_NONE;
  }
  
  void ImageCache::LoadMissing(const ImageInfoSet& image_info,
                               const ImageSet& images,
                               const LoadImagesCallback& callback) {
    CEF_REQUIRE_FILE_THREAD();
    
    DCHECK_EQ(image_info.size(), images.size());
    
    ImageContentSet contents;
    
    ImageInfoSet::const_iterator it1 = image_info.begin();
    ImageSet::const_iterator it2 = images.begin();
    for (; it1 != image_info.end() && it2 != images.end(); ++it1, ++it2) {
      const ImageInfo& info = *it1;
      ImageContent content;
      if (*it2 || info.id_ == kEmptyId) {
        // Image already exists or is intentionally empty.
        content.image_ = *it2;
      } else {
        LoadImageContents(info, &content);
      }
      contents.push_back(content);
    }
    
    CefPostTask(TID_UI, base::Bind(&ImageCache::UpdateCache, this, image_info,
                                   contents, callback));
  }
  
  // static
  bool ImageCache::LoadImageContents(const ImageInfo& info,
                                     ImageContent* content) {
    CEF_REQUIRE_FILE_THREAD();
    
    ImageRepSet::const_iterator it = info.reps_.begin();
    for (; it != info.reps_.end(); ++it) {
      const ImageRep& rep = *it;
      ImageType rep_type;
      std::string rep_contents;
      if (!LoadImageContents(rep.path_, info.internal_, &rep_type,
                             &rep_contents)) {
        LOG(ERROR) << "Failed to load image " << info.id_ << " from path "
        << rep.path_;
        return false;
      }
      content->contents_.push_back(
                                   ImageContent::RepContent(rep_type, rep.scale_factor_, rep_contents));
    }
    
    return true;
  }
  
  // static
  bool ImageCache::LoadImageContents(const std::string& path,
                                     bool internal,
                                     ImageType* type,
                                     std::string* contents) {
    CEF_REQUIRE_FILE_THREAD();
    
    *type = GetImageType(path);
    if (*type == TYPE_NONE)
      return false;
    
    if (internal) {
      if (!utils::LoadBinaryResource(path.c_str(), *contents))
        return false;
    } else if (!utils::ReadFileToString(path, contents)) {
      return false;
    }
    
    return !contents->empty();
  }
  
  void ImageCache::UpdateCache(const ImageInfoSet& image_info,
                               const ImageContentSet& contents,
                               const LoadImagesCallback& callback) {
    CEF_REQUIRE_UI_THREAD();
    
    DCHECK_EQ(image_info.size(), contents.size());
    
    ImageSet images;
    
    ImageInfoSet::const_iterator it1 = image_info.begin();
    ImageContentSet::const_iterator it2 = contents.begin();
    for (; it1 != image_info.end() && it2 != contents.end(); ++it1, ++it2) {
      const ImageInfo& info = *it1;
      const ImageContent& content = *it2;
      if (content.image_ || info.id_ == kEmptyId) {
        // Image already exists or is intentionally empty.
        images.push_back(content.image_);
      } else {
        CefRefPtr<CefImage> image = CreateImage(info.id_, content);
        images.push_back(image);
        
        // Add the image to the map.
        image_map_.insert(std::make_pair(info.id_, image));
      }
    }
    
    callback.Run(images);
  }
  
  // static
  CefRefPtr<CefImage> ImageCache::CreateImage(const std::string& image_id,
                                              const ImageContent& content) {
    CEF_REQUIRE_UI_THREAD();
    
    // Shouldn't be creating an image if one already exists.
    DCHECK(!content.image_);
    
    if (content.contents_.empty())
      return NULL;
    
    CefRefPtr<CefImage> image = CefImage::CreateImage();
    
    ImageContent::RepContentSet::const_iterator it = content.contents_.begin();
    for (; it != content.contents_.end(); ++it) {
      const ImageContent::RepContent& rep = *it;
      if (rep.type_ == TYPE_PNG) {
        if (!image->AddPNG(rep.scale_factor_, rep.contents_.c_str(),
                           rep.contents_.size())) {
          LOG(ERROR) << "Failed to create image " << image_id << " for PNG@"
          << rep.scale_factor_;
          return NULL;
        }
      } else if (rep.type_ == TYPE_JPEG) {
        if (!image->AddJPEG(rep.scale_factor_, rep.contents_.c_str(),
                            rep.contents_.size())) {
          LOG(ERROR) << "Failed to create image " << image_id << " for JPG@"
          << rep.scale_factor_;
          return NULL;
        }
      } else {
        NOTREACHED();
        return NULL;
      }
    }
    
    return image;
  }
}

namespace client {
  namespace {
    MainMessageLoop* g_main_message_loop = NULL;
  }  // namespace
  
  MainMessageLoop::MainMessageLoop() {
    DCHECK(!g_main_message_loop);
    g_main_message_loop = this;
  }
  
  MainMessageLoop::~MainMessageLoop() {
    g_main_message_loop = NULL;
  }
  
  // static
  MainMessageLoop* MainMessageLoop::Get() {
    DCHECK(g_main_message_loop);
    return g_main_message_loop;
  }
  
  void MainMessageLoop::PostClosure(const base::Closure& closure) {
    PostTask(CefCreateClosureTask(closure));
  }
  
  int MainMessageLoop::Run() {
    CefRunMessageLoop();
    return 0;
  }
  
  void MainMessageLoop::Quit() {
    CefQuitMessageLoop();
  }
  
  void MainMessageLoop::PostTask(CefRefPtr<CefTask> task) {
    CefPostTask(TID_UI, task);
  }
  
  bool MainMessageLoop::RunsTasksOnCurrentThread() const {
    return CefCurrentlyOn(TID_UI);
  }
}  // namespace client
