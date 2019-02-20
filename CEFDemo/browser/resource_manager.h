#ifndef CEF_RESOURCE_MANAGER_H_
#define CEF_RESOURCE_MANAGER_H_
#import "utils.h"

namespace client {
  namespace resource_manager {
    // Set up the resource manager for tests.
    void SetupResourceManager(CefRefPtr<CefResourceManager> resource_manager);
  }
}

#endif // CEF_RESOURCE_MANAGER_H_
