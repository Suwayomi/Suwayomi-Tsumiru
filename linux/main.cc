#include <unistd.h>

#include <cstdio>

#include "my_application.h"

int main(int argc, char** argv) {
  int exit_status;
  {
    g_autoptr(MyApplication) app = my_application_new();
    exit_status = g_application_run(G_APPLICATION(app), argc, argv);
  }
  // Skip libc exit handlers: NVIDIA's EGL teardown races Flutter's raster thread.
  std::fflush(nullptr);
  _exit(exit_status);
}
