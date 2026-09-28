import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nativeapi/nativeapi.dart' as native;
import 'package:window_manager/window_manager.dart';

import '../core/constants.dart';
import '../core/date_utils.dart';
import '../core/enums.dart';
import '../data/models/habit_today_view.dart';
import '../data/providers.dart';

const _appId = 'com.aktenak.habit_tracker';
const _appDisplayName = 'Aktenak Habit Tracker';

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
      instance.setProgram(Platform.resolvedExecutable, const []);
      return value ? instance.enable() : instance.disable();
    } finally {
      instance.dispose();
    }
  }

  /// Re-registers the current executable path if "start at login" is on.
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
  TrayService(this._container);

  final ProviderContainer _container;

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
  }

  Future<void> _initTray() async {
    try {
      await windowManager.ensureInitialized();
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
        if (event is native.TrayIconClickedEvent) windowManager.show();
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

    addItem('Aç', onClick: () => windowManager.show());
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
    if (await windowManager.isPreventClose()) {
      await windowManager.hide();
    }
  }
}
