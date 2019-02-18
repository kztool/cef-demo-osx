// Copyright (c) 2015 The Chromium Embedded Framework Authors. All rights
// reserved. Use of this source code is governed by a BSD-style license that
// can be found in the LICENSE file.

#ifndef CEF_TESTS_CEFCLIENT_BROWSER_TEST_RUNNER_H_
#define CEF_TESTS_CEFCLIENT_BROWSER_TEST_RUNNER_H_
#pragma once

#include <set>
#include <string>

#include "include/cef_browser.h"
#include "include/cef_request.h"
#include "include/wrapper/cef_message_router.h"
#include "include/wrapper/cef_resource_manager.h"

namespace client {
  namespace test_runner {
    // Returns the contents of the CefRequest as a string.
    std::string DumpRequestContents(CefRefPtr<CefRequest> request);

    // Returns the dump response as a stream. |request| is the request.
    // |response_headers| will be populated with extra response headers, if any.
    CefRefPtr<CefStreamReader> GetDumpResponse(
                                               CefRefPtr<CefRequest> request,
                                               CefResponse::HeaderMap& response_headers);

    // Returns a data: URI with the specified contents.
    std::string GetDataURI(const std::string& data, const std::string& mime_type);

    // Returns the string representation of the specified error code.
    std::string GetErrorString(cef_errorcode_t code);

    // Set up the resource manager for tests.
    void SetupResourceManager(CefRefPtr<CefResourceManager> resource_manager);

    // Show a JS alert message.
    void Alert(CefRefPtr<CefBrowser> browser, const std::string& message);
  }  // namespace test_runner
}  // namespace client

#endif  // CEF_TESTS_CEFCLIENT_BROWSER_TEST_RUNNER_H_

