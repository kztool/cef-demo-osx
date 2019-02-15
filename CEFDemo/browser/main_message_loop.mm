// Copyright (c) 2015 The Chromium Embedded Framework Authors. All rights
// reserved. Use of this source code is governed by a BSD-style license that
// can be found in the LICENSE file.

#include "browser/main_message_loop.h"

#include "include/cef_task.h"
#include "include/wrapper/cef_closure_task.h"
#include "include/cef_app.h"

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

