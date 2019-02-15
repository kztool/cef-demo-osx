//
//  utils_h
//  CEFDemo
//
//  Created by 田硕 on 2019/2/15.
//  Copyright © 2019 田硕. All rights reserved.
//

#ifndef utils_h
#define utils_h
#pragma once

#import <Foundation/Foundation.h>
#include <string>
#include <mach-o/dyld.h>

#include "include/cef_parser.h"
#include "include/cef_path_util.h"
#include "include/wrapper/cef_resource_manager.h"

#define ClientWindowHandle CefWindowHandle
#ifdef __cplusplus
#ifdef __OBJC__
@class NSWindow;
#else
class NSWindow;
#endif
#endif

namespace client {
  // Returns the directory containing resource files.
  bool GetResourceDir(std::string& dir);
  
  // Retrieve a resource as a string.
  bool LoadBinaryResource(const char* resource_name, std::string& resource_data);
  
  // Retrieve a resource as a steam reader.
  CefRefPtr<CefStreamReader> GetBinaryResourceReader(const char* resource_name);
}  // namespace client

namespace client {
  class BytesWriteHandler : public CefWriteHandler {
  public:
    explicit BytesWriteHandler(size_t grow);
    ~BytesWriteHandler();
    
    size_t Write(const void* ptr, size_t size, size_t n) OVERRIDE;
    int Seek(int64 offset, int whence) OVERRIDE;
    int64 Tell() OVERRIDE;
    int Flush() OVERRIDE;
    bool MayBlock() OVERRIDE { return false; }
    
    void* GetData() { return data_; }
    int64 GetDataSize() { return offset_; }
    
  private:
    size_t Grow(size_t size);
    
    size_t grow_;
    void* data_;
    int64 datasize_;
    int64 offset_;
    
    base::Lock lock_;
    
    IMPLEMENT_REFCOUNTING(BytesWriteHandler);
    DISALLOW_COPY_AND_ASSIGN(BytesWriteHandler);
  };
}  // namespace client

namespace client {
  namespace file_util {
    
    // Platform-specific path separator.
    extern const char kPathSep;
    
    // Reads the file at |path| into |contents| and returns true on success and
    // false on error.  In case of I/O error, |contents| holds the data that could
    // be read from the file before the error occurred.  When the file size exceeds
    // max_size|, the function returns false with |contents| holding the file
    // truncated to |max_size|. |contents| may be NULL, in which case this function
    // is useful for its side effect of priming the disk cache (could be used for
    // unit tests). Calling this function on the browser process UI or IO threads is
    // not allowed.
    bool ReadFileToString(const std::string& path,
                          std::string* contents,
                          size_t max_size = std::numeric_limits<size_t>::max());
    
    // Writes the given buffer into the file, overwriting any data that was
    // previously there. Returns the number of bytes written, or -1 on error.
    // Calling this function on the browser process UI or IO threads is not allowed.
    int WriteFile(const std::string& path, const char* data, int size);
    
    // Combines |path1| and |path2| with the correct platform-specific path
    // separator.
    std::string JoinPath(const std::string& path1, const std::string& path2);
    
    // Extracts the file extension from |path|.
    std::string GetFileExtension(const std::string& path);
    
  }  // namespace file_util
}  // namespace client

namespace client {
  namespace extension_util {
    // Returns true if |extension_path| can be handled internally via
    // LoadBinaryResource. This checks a hard-coded list of allowed extension path
    // components.
    bool IsInternalExtension(const std::string& extension_path);
    
    // Returns the path relative to the resource directory after removing the
    // PK_DIR_RESOURCES prefix. This will be the relative path expected by
    // LoadBinaryResource (uses '/' as path separator on all platforms). Only call
    // this method for internal extensions, either when IsInternalExtension returns
    // true or when the extension is handled internally through some means other
    // than LoadBinaryResource. Use GetExtensionResourcePath instead if you are
    // unsure whether the extension is internal or external.
    std::string GetInternalExtensionResourcePath(const std::string& extension_path);
    
    // Returns the resource path for |extension_path|. For external extensions this
    // will be the full file path on disk. For internal extensions this will be the
    // relative path expected by LoadBinaryResource (uses '/' as path separator on
    // all platforms). Internal extensions must be on the hard-coded list enforced
    // by IsInternalExtension. If |internal| is non-NULL it will be set to true if
    // the extension is handled internally.
    std::string GetExtensionResourcePath(const std::string& extension_path,
                                         bool* internal);
    
    // Read the contents of |extension_path| into |contents|. For external
    // extensions this will read the file from disk. For internal extensions this
    // will call LoadBinaryResource. Internal extensions must be on the hard-coded
    // list enforced by IsInternalExtension. Returns true on success. Must be
    // called on the FILE thread.
    bool GetExtensionResourceContents(const std::string& extension_path,
                                      std::string& contents);
    
    // Load |extension_path| in |request_context|. May be an internal or external
    // extension. Internal extensions must be on the hard-coded list enforced by
    // IsInternalExtension.
    void LoadExtension(CefRefPtr<CefRequestContext> request_context,
                       const std::string& extension_path,
                       CefRefPtr<CefExtensionHandler> handler);
    
    // Register an internal handler for extension resources. Internal extensions
    // must be on the hard-coded list enforced by IsInternalExtension.
    void AddInternalExtensionToResourceManager(
                                               CefRefPtr<CefExtension> extension,
                                               CefRefPtr<CefResourceManager> resource_manager);
    
    // Returns the URL origin for |extension_id|.
    std::string GetExtensionOrigin(const std::string& extension_id);
    
    // Parse browser_action manifest values as defined at
    // https://developer.chrome.com/extensions/browserAction
    
    // Look for a browser_action.default_popup manifest value.
    std::string GetExtensionURL(CefRefPtr<CefExtension> extension);
    
    // Look for a browser_action.default_icon manifest value and return the resource
    // path. If |internal| is non-NULL it will be set to true if the extension is
    // handled internally.
    std::string GetExtensionIconPath(CefRefPtr<CefExtension> extension,
                                     bool* internal);
    
  }  // namespace extension_util
}  // namespace client

#endif /* utils_h */
