//
//  utils_h
//  CEFDemo
//
//  Created by 田硕 on 2019/2/15.
//  Copyright © 2019 田硕. All rights reserved.
//

#ifndef CEF_UTILS_H_
#define CEF_UTILS_H_
#pragma once

#import <set>
#import <mach-o/dyld.h>
#import <iomanip>

#import "include/cef_app.h"
#import "include/cef_client.h"
#import "include/cef_parser.h"
#import "include/cef_path_util.h"
#import "include/cef_application_mac.h"

#import "include/views/cef_window.h"

#import "include/wrapper/cef_library_loader.h"
#import "include/wrapper/cef_resource_manager.h"
#import "include/wrapper/cef_stream_resource_handler.h"

#define NEWLINE "\n"

#define ClientWindowHandle CefWindowHandle

#define CURRENTLY_ON_MAIN_THREAD() \
client::MainMessageLoop::Get()->RunsTasksOnCurrentThread()

#define REQUIRE_MAIN_THREAD() DCHECK(CURRENTLY_ON_MAIN_THREAD())

#define MAIN_POST_TASK(task) client::MainMessageLoop::Get()->PostTask(task)

#define MAIN_POST_CLOSURE(closure) \
client::MainMessageLoop::Get()->PostClosure(closure)

#define CEFM_FLAG(flag)                      \
if (status & flag) {                    \
result += std::string(#flag) + "<br/>"; \
}

#define CEFM_VALUE(val, def)   \
if (val == def) {         \
return std::string(#def); \
}

#define CEFM_CASE(code)  \
case code:          \
return #code

#ifdef __cplusplus
#ifdef __OBJC__
@class NSWindow;
@class NSView;
@class NSButton;
@class NSTextField;
#else
class NSWindow;
class NSView;
class NSButton;
class NSTextField;
#endif
#endif

namespace client {
  enum WindowType {
    WindowType_None,
    WindowType_Home,
    WindowType_App,
    WindowType_Web,
    WindowType_DevTools,
    WindowType_Extension,
    WindowType_SSL,
    WindowType_Other,
  };
}

namespace client {
  namespace switches {
    // CEF and Chromium support a wide range of command-line switches. This file
    // only contains command-line switches specific to the cefclient application.
    // View CEF/Chromium documentation or search for *_switches.cc files in the
    // Chromium source code to identify other existing command-line switches.
    // Below is a partial listing of relevant *_switches.cc files:
    //   base/base_switches.cc
    //   cef/libcef/common/cef_switches.cc
    //   chrome/common/chrome_switches.cc (not all apply)
    //   content/public/common/content_switches.cc

    const char kCachePath[] = "cache-path";
    const char kUrl[] = "url";
    const char kMouseCursorChangeDisabled[] = "mouse-cursor-change-disabled";
    const char kRequestContextPerBrowser[] = "request-context-per-browser";
    const char kRequestContextSharedCache[] = "request-context-shared-cache";
    const char kRequestContextBlockCookies[] = "request-context-block-cookies";
    const char kWidevineCdmPath[] = "widevine-cdm-path";
    const char kSslClientCertificate[] = "ssl-client-certificate";
    const char kLoadExtension[] = "load-extension";
    const char kNoActivate[] = "no-activate";
  }  // namespace switches
}  // namespace client

namespace client {
  namespace utils {
    // Returns the directory containing resource files.
    bool GetResourceDir(std::string& dir);
    
    // Retrieve a resource as a string.
    bool LoadBinaryResource(const char* resource_name, std::string& resource_data);
    
    // Retrieve a resource as a steam reader.
    CefRefPtr<CefStreamReader> GetBinaryResourceReader(const char* resource_name);
    
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
    
    // Tell if the file exist
    bool FileExists(const char* path);
    
    // Returns a data: URI with the specified contents.
    std::string GetDataURI(const std::string& data, const std::string& mime_type);
    
    // Returns the string representation of the specified error code.
    std::string GetErrorString(cef_errorcode_t code);
    
    // Show a JS alert message.
    void Alert(CefRefPtr<CefBrowser> browser, const std::string& message);
    
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
    std::string GetExtensionResourcePath(const std::string& extension_path, bool* internal);
    
    // Read the contents of |extension_path| into |contents|. For external
    // extensions this will read the file from disk. For internal extensions this
    // will call LoadBinaryResource. Internal extensions must be on the hard-coded
    // list enforced by IsInternalExtension. Returns true on success. Must be
    // called on the FILE thread.
    bool GetExtensionResourceContents(const std::string& extension_path, std::string& contents);
    
    // Load |extension_path| in |request_context|. May be an internal or external
    // extension. Internal extensions must be on the hard-coded list enforced by
    // IsInternalExtension.
    void LoadExtension(CefRefPtr<CefRequestContext> request_context,
                       const std::string& extension_path,
                       CefRefPtr<CefExtensionHandler> handler);
    
    // Register an internal handler for extension resources. Internal extensions
    // must be on the hard-coded list enforced by IsInternalExtension.
    void AddInternalExtensionToResourceManager(CefRefPtr<CefExtension> extension,
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
    std::string GetExtensionIconPath(CefRefPtr<CefExtension> extension, bool* internal);
  }
}

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
  // Simple image caching implementation.
  class ImageCache: public base::RefCountedThreadSafe<ImageCache, CefDeleteOnUIThread> {
  public:
    ImageCache();
    
    // Image representation at a specific scale factor.
    struct ImageRep {
      ImageRep(const std::string& path, float scale_factor);
      
      // Full file system path.
      std::string path_;
      
      // Image scale factor (usually 1.0f or 2.0f).
      float scale_factor_;
    };
    typedef std::vector<ImageRep> ImageRepSet;
    
    // Unique image that may have multiple representations.
    struct ImageInfo {
      ImageInfo(const std::string& id,
                const ImageRepSet& reps,
                bool internal,
                bool force_reload);
      
      // Helper for returning an empty image.
      static ImageInfo Empty();
      
      // Helpers for creating common representations.
      static ImageInfo Create1x(const std::string& id,
                                const std::string& path_1x,
                                bool internal);
      static ImageInfo Create2x(const std::string& id,
                                const std::string& path_1x,
                                const std::string& path_2x,
                                bool internal);
      static ImageInfo Create2x(const std::string& id);
      
      // Image unique ID.
      std::string id_;
      
      // Image representations to load.
      ImageRepSet reps_;
      
      // True if the image is internal (loaded via LoadBinaryResource).
      bool internal_;
      
      // True to force reload.
      bool force_reload_;
    };
    typedef std::vector<ImageInfo> ImageInfoSet;
    
    typedef std::vector<CefRefPtr<CefImage>> ImageSet;
    
    typedef base::Callback<void(const ImageSet& /*images*/)> LoadImagesCallback;
    
    // Loads the images represented by |image_info|. Executes |callback|
    // either synchronously or asychronously on the UI thread after completion.
    void LoadImages(const ImageInfoSet& image_info,
                    const LoadImagesCallback& callback);
    
    // Returns an image that has already been cached. Must be called on the
    // UI thread.
    CefRefPtr<CefImage> GetCachedImage(const std::string& image_id);
    
  private:
    // Only allow deletion via CefRefPtr.
    friend struct CefDeleteOnThread<TID_UI>;

    ~ImageCache();
    
    enum ImageType {
      TYPE_NONE,
      TYPE_PNG,
      TYPE_JPEG,
    };
    
    static ImageType GetImageType(const std::string& path);
    
    struct ImageContent;
    typedef std::vector<ImageContent> ImageContentSet;
    
    // Load missing image contents on the FILE thread.
    void LoadMissing(const ImageInfoSet& image_info,
                     const ImageSet& images,
                     const LoadImagesCallback& callback);
    static bool LoadImageContents(const ImageInfo& info, ImageContent* content);
    static bool LoadImageContents(const std::string& path,
                                  bool internal,
                                  ImageType* type,
                                  std::string* contents);
    
    // Create missing CefImage representations on the UI thread.
    void UpdateCache(const ImageInfoSet& image_info,
                     const ImageContentSet& contents,
                     const LoadImagesCallback& callback);
    static CefRefPtr<CefImage> CreateImage(const std::string& image_id,
                                           const ImageContent& content);
    
    // Map image ID to image representation. Only accessed on the UI thread.
    typedef std::map<std::string, CefRefPtr<CefImage>> ImageMap;
    ImageMap image_map_;
  };
}


namespace client {
  // Represents the message loop running on the main application thread in the
  // browser process. This will be the same as the CEF UI thread on Linux, OS X
  // and Windows when not using multi-threaded message loop mode. The methods of
  // this class are thread-safe unless otherwise indicated.
  class MainMessageLoop {
  public:
    MainMessageLoop();
    // Returns the singleton instance of this object.
    static MainMessageLoop* Get();
    
    // Run the message loop. The thread that this method is called on will be
    // considered the main thread. This blocks until Quit() is called.
    virtual int Run();
    
    // Quit the message loop.
    virtual void Quit();
    
    // Post a task for execution on the main message loop.
    virtual void PostTask(CefRefPtr<CefTask> task);
    
    // Returns true if this message loop runs tasks on the current thread.
    virtual bool RunsTasksOnCurrentThread() const;
    
    // Post a closure for execution on the main message loop.
    void PostClosure(const base::Closure& closure);
    
  protected:
    // Only allow deletion via scoped_ptr.
    friend struct base::DefaultDeleter<MainMessageLoop>;
    virtual ~MainMessageLoop();
    
  private:
    DISALLOW_COPY_AND_ASSIGN(MainMessageLoop);
  };

  // Use this struct in conjuction with RefCountedThreadSafe to ensure that an
  // object is deleted on the main thread. For example:
  //
  // class Foo : public base::RefCountedThreadSafe<Foo, DeleteOnMainThread> {
  //  public:
  //   Foo();
  //   void DoSomething();
  //
  //  private:
  //   // Allow deletion via CefRefPtr only.
  //   friend struct DeleteOnMainThread;
  //   friend class base::RefCountedThreadSafe<Foo, DeleteOnMainThread>;
  //
  //   virtual ~Foo() {}
  // };
  //
  // base::CefRefPtr<Foo> foo = new Foo();
  // foo->DoSomething();
  // foo = NULL;  // Deletion of |foo| will occur on the main thread.
  //
  struct DeleteOnMainThread {
    template <typename T>
    static void Destruct(const T* x) {
      if (CURRENTLY_ON_MAIN_THREAD()) {
        delete x;
      } else {
        client::MainMessageLoop::Get()->PostClosure(base::Bind(&DeleteOnMainThread::Destruct<T>, x));
      }
    }
  };
}  // namespace client

#endif // CEF_UTILS_H_
