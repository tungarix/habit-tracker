import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart' show Rect;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nativeapi/nativeapi.dart' as native;
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../core/constants.dart';
import '../core/date_utils.dart';
import '../core/enums.dart';
import '../core/window_placement.dart';
import '../data/models/habit_today_view.dart';
import '../data/providers.dart';

const _appId = 'com.aktenak.habit_tracker';
const _appDisplayName = 'Aktenak Habit Tracker';

/// Opens [path] in the system file manager (Explorer / the Linux default).
/// Explorer exits non-zero even on success, so the result is ignored.
Future<void> openFolder(String path) async {
  try {
    if (Platform.isWindows) {
      await Process.run('explorer', [path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [path]);
    }
  } catch (_) {}
}

/// "Start at login" is a plain OS setting, not app state — reading and
/// writing it straight from the native object avoids a DB-cached flag that
/// could drift from what Windows/Linux actually has configured (e.g. after
/// the user removes it themselves from system settings).
class LaunchAtLoginSetting {
  static bool get isSupported {
    if (!(Platform.isWindows || Platform.isLinux)) return false;
    try {
      return native.LaunchAtLogin.isSupported();
    } catch (_) {
      return false;
    }
  }

  static bool get isEnabled {
    final instance = _open();
    if (instance == null) return false;
    try {
      return instance.isEnabled;
    } finally {
      instance.dispose();
    }
  }

  /// Returns whether the toggle now matches [value].
  static bool setEnabled(bool value) {
    final instance = _open();
    if (instance == null) return false;
    try {
      // --tray: oturum açılışında pencere fırlamasın, tepside başlasın
      // (windows/runner/flutter_window.cpp bu bayrakta pencereyi göstermez).
      instance.setProgram(Platform.resolvedExecutable, const ['--tray']);
      return value ? instance.enable() : instance.disable();
    } finally {
      instance.dispose();
    }
  }

  /// Re-registers the current executable path (and the `--tray` flag) if
  /// "start at login" is on.
  ///
  /// Call once at startup: this is a portable app, so a version moved to a
  /// new folder (or replaced in place by unzipping a newer release) would
  /// otherwise leave Windows/Linux pointed at a path that may no longer
  /// hold this exe — `setEnabled` only refreshes the path when the toggle
  /// itself is flipped, which doesn't happen on every launch.
  static void syncPathIfEnabled() {
    if (!isEnabled) return;
    setEnabled(true);
  }

  static native.LaunchAtLogin? _open() {
    if (!isSupported) return null;
    try {
      return native.LaunchAtLogin.createWithIdAndDisplayName(
        _appId,
        _appDisplayName,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Minimize-to-tray with a quick-mark menu, plus an evening reminder
/// notification — everything that has to reach past the widget tree into
/// real OS integration.
///
/// Driven by a [ProviderContainer] rather than a `Consumer` so `flutter
/// test` — which never calls [init] — never touches the tray/window/
/// notification platform channels widget tests cannot provide.
/// Windows/Linux only; macOS/mobile builds skip it entirely.
class TrayService with WindowListener {
  TrayService(this._container, {this.startInTray = false});

  final ProviderContainer _container;

  /// Launched with `--tray` (start-at-login): stay hidden until "Aç".
  final bool startInTray;

  /// Last un-maximised bounds; saved alongside the maximised flag so that
  /// un-maximising after a restart returns to a normal-sized window.
  Rect? _normalBounds;
  bool _pendingMaximize = false;
  Timer? _placementSaveTimer;

  native.TrayIcon? _trayIcon;
  // Never read again, only held: its Finalizer would free the native icon
  // the moment nothing references the Dart wrapper, even though the tray
  // icon still points at it natively.
  // ignore: unused_field
  native.Image? _iconImage;
  native.Menu? _menu;
  final List<native.MenuItem> _menuItems = [];
  bool _trayReady = false;

  bool _notificationsReady = false;
  Timer? _reminderTimer;
  String? _lastReminderedDate;

  Future<void> init() async {
    if (!(Platform.isWindows || Platform.isLinux)) return;
    try {
      LaunchAtLoginSetting.syncPathIfEnabled();
    } catch (_) {
      // Best-effort — a stale launch-at-login path is a papercut, not a
      // reason to fail startup.
    }
    await _initTray();
    await _initNotifications();

    // Without a working tray icon a hidden start would leave the app
    // running with no way to open it.
    if (startInTray && !_trayReady) {
      await _safely(windowManager.show);
    } else if (startInTray && Platform.isLinux) {
      // The Linux runner always shows the window itself.
      await _safely(windowManager.hide);
    }
  }

  Future<void> _initTray() async {
    try {
      await windowManager.ensureInitialized();
      // Before runApp, so before the first frame — the window appears in
      // place instead of jumping there.
      await _restorePlacement();
      await windowManager.setPreventClose(true);
      windowManager.addListener(this);

      if (!native.TrayManager.instance.isSupported()) return;
      final trayIcon = native.TrayIcon.create();
      if (trayIcon == null) return;
      _trayIcon = trayIcon;

      final image = native.ImageAsset.fromAsset('assets/tray_icon.ico');
      if (image != null) {
        _iconImage = image;
        trayIcon.icon = image;
      }
      trayIcon.setTooltip('Aktenak');
      trayIcon.setVisible(true);
      trayIcon.addListener((event) {
        if (event is native.TrayIconClickedEvent) _showWindow();
      });
      _trayReady = true;

      _container.listen<AsyncValue<List<HabitTodayView>>>(
        todayViewsProvider,
        (_, next) => _refreshTray(next.value),
        fireImmediately: true,
      );
    } catch (_) {
      // Nice-to-have, not load-bearing: e.g. no libappindicator on some
      // Linux desktops. The app has to run fine without a tray icon.
    }
  }

  Future<void> _initNotifications() async {
    try {
      if (!native.NotificationManager.instance.isSupported()) return;
      if (!native.NotificationManager.instance.initialize()) return;
      _notificationsReady = true;

      // Restored so a same-day restart (e.g. via tray Çıkış + reopen)
      // doesn't re-fire a reminder already shown before the restart.
      _lastReminderedDate = await _container
          .read(databaseProvider)
          .getSetting(AppConstants.lastReminderDateKey);

      _reminderTimer?.cancel();
      _reminderTimer = Timer.periodic(
        const Duration(minutes: 5),
        (_) => _maybeRemind(),
      );
      _maybeRemind(); // also catches "opened the app after the hour"
    } catch (_) {
      // Same story: no reminder beats a crashed app.
    }
  }

  void _maybeRemind() {
    if (!_notificationsReady) return;
    final hour = _container.read(reminderHourProvider);
    if (hour == null || DateTime.now().hour < hour) return;

    final today = _container.read(todayProvider);
    final todayStr = formatYmd(today);
    if (_lastReminderedDate == todayStr) return;

    final views = _container.read(todayViewsProvider).value ?? const [];
    final pending = views.where((v) => v.scheduledToday && !v.doneToday).length;
    if (pending == 0) return;

    final shown = native.NotificationManager.instance.show(
      'Aktenak',
      '$pending alışkanlık bugün için hâlâ bekliyor.',
      'evening-reminder-$todayStr',
      '',
    );
    if (shown) {
      _lastReminderedDate = todayStr;
      _container
          .read(databaseProvider)
          .setSetting(AppConstants.lastReminderDateKey, todayStr);
    }
  }

  void _refreshTray(List<HabitTodayView>? views) {
    final trayIcon = _trayIcon;
    if (!_trayReady || trayIcon == null) return;

    final scheduled = (views ?? const <HabitTodayView>[])
        .where((v) => v.scheduledToday)
        .toList();
    final done = scheduled.where((v) => v.doneToday).length;
    trayIcon.setTooltip('Aktenak — bugün $done/${scheduled.length}');

    final pending = scheduled
        .where(
          (v) => !v.doneToday && v.habit.kind == HabitKind.bool_.storageName,
        )
        .toList();

    final menu = native.Menu.create();
    if (menu == null) return;
    final items = <native.MenuItem>[];

    native.MenuItem? addItem(
      String label, {
      bool enabled = true,
      void Function()? onClick,
    }) {
      final item = native.MenuItem.createWithLabelAndType(
        label,
        native.MenuItemType.normal,
      );
      if (item == null) return null;
      item.isEnabled = enabled;
      if (onClick != null) {
        item.addListener((event) {
          if (event is native.MenuItemClickedEvent) onClick();
        });
      }
      items.add(item);
      menu.addItem(item);
      return item;
    }

    addItem('Aç', onClick: _showWindow);
    menu.addSeparator();
    if (pending.isEmpty) {
      addItem('Bugün için bekleyen yok', enabled: false);
    } else {
      for (final v in pending) {
        final habitId = v.habit.id;
        addItem(
          '✓  ${v.habit.name}',
          onClick: () {
            final today = _container.read(todayProvider);
            _container
                .read(habitRepositoryProvider)
                .setStatus(habitId, formatYmd(today), EntryStatus.done);
          },
        );
      }
    }
    menu.addSeparator();
    addItem(
      'Çıkış',
      onClick: () async {
        await _savePlacement();
        await windowManager.setPreventClose(false);
        await windowManager.destroy();
      },
    );

    trayIcon.setContextMenu(menu);

    // Old menu/items are now detached from the tray icon — safe to drop.
    final oldMenu = _menu;
    final oldItems = List<native.MenuItem>.of(_menuItems);
    _menu = menu;
    _menuItems
      ..clear()
      ..addAll(items);
    Future.microtask(() {
      for (final item in oldItems) {
        item.dispose();
      }
      oldMenu?.dispose();
    });
  }

  @override
  void onWindowClose() async {
    await _savePlacement();
    if (await windowManager.isPreventClose()) {
      await windowManager.hide();
    }
  }

  // ---------------------------------------------------------------------------
  // Window position / size
  // ---------------------------------------------------------------------------

  // Windows reports once at the end of a drag (…Resized/…Moved); Linux only
  // streams the continuous events — the debounce covers both.
  @override
  void onWindowResized() => _schedulePlacementSave();
  @override
  void onWindowMoved() => _schedulePlacementSave();
  @override
  void onWindowResize() => _schedulePlacementSave();
  @override
  void onWindowMove() => _schedulePlacementSave();
  @override
  void onWindowMaximize() => _schedulePlacementSave();
  @override
  void onWindowUnmaximize() => _schedulePlacementSave();

  void _schedulePlacementSave() {
    _placementSaveTimer?.cancel();
    _placementSaveTimer = Timer(
      const Duration(milliseconds: 500),
      _savePlacement,
    );
  }

  Future<void> _restorePlacement() async {
    try {
      final saved = WindowPlacement.decode(
        await _container
            .read(databaseProvider)
            .getSetting(AppConstants.windowPlacementKey),
      );
      if (saved == null) return;

      final displays = await screenRetriever.getAllDisplays();
      final screens = [
        for (final d in displays)
          if (d.visiblePosition != null && d.visibleSize != null)
            ScreenArea(
              d.visiblePosition!.dx,
              d.visiblePosition!.dy,
              d.visibleSize!.width,
              d.visibleSize!.height,
            ),
      ];
      // A monitor that has since been unplugged would put the window
      // somewhere unreachable — keep the default placement instead.
      if (!saved.isReachableOn(screens)) return;

      final rect = Rect.fromLTWH(saved.x, saved.y, saved.width, saved.height);
      _normalBounds = rect;
      await windowManager.setBounds(rect);
      // Not now: maximize() shows the window, and the runner's own first
      // Show() (SW_SHOWNORMAL) would un-maximise it again anyway. Applied
      // in [onFirstFrame] / [_showWindow] instead.
      _pendingMaximize = saved.maximized;
    } catch (_) {
      // Default placement is fine; never block startup over this.
    }
  }

  Future<void> _savePlacement() async {
    _placementSaveTimer?.cancel();
    try {
      // A minimised window reports bogus bounds (-32000,-32000 on Windows).
      if (await windowManager.isMinimized()) return;
      final maximized = await windowManager.isMaximized();
      if (!maximized && await windowManager.isVisible()) {
        _normalBounds = await windowManager.getBounds();
      }
      final b = _normalBounds;
      if (b == null) return;
      final placement = WindowPlacement(
        x: b.left,
        y: b.top,
        width: b.width,
        height: b.height,
        maximized: maximized,
      );
      // Decode rejects nonsense (e.g. a zero-sized hidden window); don't
      // overwrite a good record with one.
      if (WindowPlacement.decode(placement.encode()) == null) return;
      await _container
          .read(databaseProvider)
          .setSetting(AppConstants.windowPlacementKey, placement.encode());
    } catch (_) {
      // Losing the remembered position is not worth surfacing.
    }
  }

  /// Call after the first frame (main.dart). The runner shows the window on
  /// that frame; wait for it to actually be visible, then re-maximise.
  Future<void> onFirstFrame() async {
    if (startInTray || !_pendingMaximize) return;
    _pendingMaximize = false;
    try {
      for (var i = 0; i < 40 && !await windowManager.isVisible(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await windowManager.maximize();
    } catch (_) {}
  }

  /// Tray "Aç" / icon click. Also applies a maximise deferred by a
  /// `--tray` start, which never showed the window until now.
  Future<void> _showWindow() async {
    await _safely(windowManager.show);
    if (_pendingMaximize) {
      _pendingMaximize = false;
      await _safely(windowManager.maximize);
    }
  }

  static Future<void> _safely(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {}
  }
}
