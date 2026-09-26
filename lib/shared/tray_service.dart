import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart' as native;
import 'package:window_manager/window_manager.dart';

import '../core/date_utils.dart';
import '../core/enums.dart';
import '../data/models/habit_today_view.dart';
import '../data/providers.dart';

/// Minimize-to-tray + a quick-mark menu, kept in sync with today's habits.
///
/// Lives outside the widget tree (driven by a [ProviderContainer], not a
/// `Consumer`) so `flutter test` — which never calls [init] — never touches
/// the tray/window platform channels that widget tests cannot provide.
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
  bool _ready = false;

  Future<void> init() async {
    if (!(Platform.isWindows || Platform.isLinux)) return;
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
      _ready = true;

      _container.listen<AsyncValue<List<HabitTodayView>>>(
        todayViewsProvider,
        (_, next) => _refresh(next.value),
        fireImmediately: true,
      );
    } catch (_) {
      // Nice-to-have, not load-bearing: e.g. no libappindicator on some
      // Linux desktops. The app has to run fine without a tray icon.
    }
  }

  void _refresh(List<HabitTodayView>? views) {
    final trayIcon = _trayIcon;
    if (!_ready || trayIcon == null) return;

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
