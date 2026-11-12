#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Tek örnek: ikinci başlatma (örn. uygulama tepside gizliyken kısayola
  // tıklamak) yeni süreç, ikinci DB bağlantısı ve ikinci tepsi simgesi açmaz;
  // varsa mevcut pencereyi öne getirir. Güncelleme uygulayıcısı aynı exe'dir ve
  // eski süreç hâlâ açıkken başlar, bu yüzden denetimden muaftır (bayrak
  // lib/data/update/uygula.dart'taki guncelleBayragi ile aynı olmalı).
  if (wcsstr(GetCommandLineW(), L"--guncelle-uygula=1") == nullptr) {
    // Tutamaç süreç bitene kadar bilerek açık bırakılır.
    HANDLE single_instance =
        ::CreateMutexW(nullptr, TRUE, L"Local\\Aktenak.HabitTracker.TekOrnek");
    if (single_instance != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
      HWND existing = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW",
                                    L"Aktenak Habit Tracker");
      if (existing != nullptr) {
        ::ShowWindow(existing, ::IsIconic(existing) ? SW_RESTORE : SW_SHOW);
        ::SetForegroundWindow(existing);
      }
      return EXIT_SUCCESS;
    }
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Aktenak Habit Tracker", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
