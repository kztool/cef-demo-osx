//
//  resource_manager.h
//  CEFDemo
//
//  Created by 田硕 on 2019/2/20.
//  Copyright © 2019 田硕. All rights reserved.
//

#ifndef CEF_RESOURCE_MANAGER_H_
#define CEF_RESOURCE_MANAGER_H_

#import "utils.h"

namespace client {
  namespace resource_manager {
    // Set up the resource manager for tests.
    void SetupResourceManager(CefRefPtr<CefResourceManager> resource_manager);
  }
}

#endif
