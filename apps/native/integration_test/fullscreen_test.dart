import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ytb/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ytb/player_overlay.dart';
import 'package:ytb/search_box.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const player = MethodChannel('ytb/player');
  testWidgets(
    'Actual watch UI rotates, fills screen, plays and returns on Back',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('speed', 3.5);
      await tester.pumpWidget(const YtbApp());
      tester
          .widget<VideoSearchBox>(find.byType(VideoSearchBox))
          .onSearch('Blender open movie');
      Future<Map<String, dynamic>> state() async =>
          Map<String, dynamic>.from(await player.invokeMethod('state'));
      Future<void> waitFor(Future<bool> Function() condition) async {
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        do {
          await tester.pump(const Duration(milliseconds: 250));
          if (await condition()) return;
        } while (DateTime.now().isBefore(deadline));
        debugPrint('YTB_FULLSCREEN_STATE:${await state()}');
        fail('Timed out waiting for watch UI / native orientation');
      }

      await waitFor(
        () async =>
            find.text('Spring - Blender Open Movie').evaluate().isNotEmpty,
      );
      await tester.tap(find.text('Spring - Blender Open Movie').first);
      await tester.pump();
      await waitFor(() async {
        final s = await state();
        return s['id'] == 'WhWc3b3KhnY' &&
            s['ready'] == true &&
            (s['firstFrameMs'] as num) >= 0;
      });
      await player.invokeMethod('pause');
      await waitFor(
        () async => find.byTooltip('Toàn màn hình').evaluate().isNotEmpty,
      );
      final before = await state();
      expect(before['speed'], 1.0);
      expect(prefs.getDouble('speed'), isNull);
      await tester.tap(find.byTooltip('Toàn màn hình'));
      await waitFor(
        () async =>
            tester.view.physicalSize.width > tester.view.physicalSize.height,
      );
      await tester.pump(const Duration(seconds: 1));
      final fullscreenSize = tester.getSize(find.byType(PlayerOverlay));
      final viewport = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(fullscreenSize.width, closeTo(viewport.width, 1));
      expect(fullscreenSize.height, closeTo(viewport.height, 1));
      await waitFor(() async {
        final s = await state();
        final layout = Map.from(s['videoLayout'] as Map);
        return (layout['surfaceWidth'] as num? ?? 0) >=
                tester.view.physicalSize.width - 2 &&
            (s['frameSerial'] as num) > (before['frameSerial'] as num);
      });
      final native = await state();
      final nativeLayout = Map.from(native['videoLayout'] as Map);
      expect(nativeLayout['width'], closeTo(tester.view.physicalSize.width, 2));
      expect(
        nativeLayout['height'],
        closeTo(tester.view.physicalSize.height, 2),
      );
      final expectedHeight =
          (nativeLayout['width'] as num) *
          (native['height'] as num) /
          (native['width'] as num);
      expect(nativeLayout['surfaceHeight'], closeTo(expectedHeight, 3));
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byTooltip('Thoát toàn màn hình'), findsOneWidget);
      final viewportRect = tester.getRect(find.byType(PlayerOverlay));
      final volumeBefore = (await player.invokeMethod<num>('adjust', {
        'kind': 'volume',
        'delta': 0,
      }))!.toDouble();
      final brightnessBefore = (await player.invokeMethod<num>('adjust', {
        'kind': 'brightness',
        'delta': 0,
      }))!.toDouble();
      try {
        await tester.dragFrom(
          Offset(
            viewportRect.left + viewportRect.width * .12,
            viewportRect.center.dy,
          ),
          const Offset(0, -70),
        );
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byKey(const Key('adjustment-volume')), findsOneWidget);
        expect(
          tester.getRect(find.byKey(const Key('adjustment-volume'))).right,
          lessThan(viewportRect.center.dx),
        );
        await tester.dragFrom(
          Offset(
            viewportRect.right - viewportRect.width * .12,
            viewportRect.center.dy,
          ),
          const Offset(0, -70),
        );
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byKey(const Key('adjustment-brightness')), findsOneWidget);
        expect(
          tester.getRect(find.byKey(const Key('adjustment-brightness'))).left,
          greaterThan(viewportRect.center.dx),
        );
        debugPrint('ICON_QA_BRIGHTNESS');
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 2)),
        );
        await tester.dragFrom(
          Offset(
            viewportRect.center.dx,
            viewportRect.top + viewportRect.height * .76,
          ),
          const Offset(0, -70),
        );
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byKey(const Key('adjustment-speed')), findsOneWidget);
      } finally {
        final volumeNow = (await player.invokeMethod<num>('adjust', {
          'kind': 'volume',
          'delta': 0,
        }))!.toDouble();
        final brightnessNow = (await player.invokeMethod<num>('adjust', {
          'kind': 'brightness',
          'delta': 0,
        }))!.toDouble();
        await player.invokeMethod('adjust', {
          'kind': 'volume',
          'delta': volumeBefore - volumeNow,
        });
        await player.invokeMethod('adjust', {
          'kind': 'brightness',
          'delta': brightnessBefore - brightnessNow,
        });
        await player.invokeMethod('speed', {'value': 1.0});
      }
      final swipe = await tester.startGesture(
        Offset(
          viewportRect.left + viewportRect.width * .2,
          viewportRect.center.dy,
        ),
      );
      await swipe.moveBy(const Offset(30, 0));
      await swipe.moveBy(const Offset(120, 0));
      await tester.pump();
      final preview = tester.getRect(
        find.byKey(const Key('seek-time-preview')),
      );
      expect(preview.top, greaterThan(viewportRect.center.dy));
      await swipe.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        (await state())['position'],
        greaterThanOrEqualTo(before['position']),
      );
      await player.invokeMethod('play');
      await waitFor(() async {
        final s = await state();
        expect(s['error'], isNull);
        return s['playing'] == true &&
            (s['position'] as num) > (before['position'] as num) + 1500;
      });
      await player.invokeMethod('pause');
      await waitFor(
        () async =>
            find.byTooltip('Khóa màn hình').hitTestable().evaluate().isNotEmpty,
      );
      await tester.tap(find.byTooltip('Khóa màn hình').hitTestable());
      await tester.pump(const Duration(milliseconds: 300));
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.view.physicalSize.width,
        greaterThan(tester.view.physicalSize.height),
      );
      expect(find.byTooltip('Mở khóa màn hình'), findsNothing);
      final lockedRect = tester.getRect(find.byType(PlayerOverlay));
      await tester.tapAt(Offset(lockedRect.left + 100, lockedRect.center.dy));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byTooltip('Mở khóa màn hình'), findsOneWidget);
      await tester.tap(find.byTooltip('Mở khóa màn hình'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.binding.handlePopRoute();
      await waitFor(
        () async =>
            tester.view.physicalSize.height > tester.view.physicalSize.width,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byTooltip('Toàn màn hình'), findsOneWidget);
      expect((await state())['error'], isNull);
      final rect = tester.getRect(find.byType(PlayerOverlay));
      await tester.timedDragFrom(
        Offset(rect.left + 30, rect.top + 40),
        const Offset(0, 200),
        const Duration(milliseconds: 700),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(PlayerOverlay), findsNothing);
      expect(find.byType(AndroidView), findsOneWidget);
      expect(tester.getSize(find.byType(AndroidView)).width, 96);
      expect(tester.takeException(), isNull);
      final report = {
        'fullscreenWidth': fullscreenSize.width,
        'fullscreenHeight': fullscreenSize.height,
        'viewportWidth': viewport.width,
        'viewportHeight': viewport.height,
        'nativeLayout': nativeLayout,
        'playAfterRotation': true,
        'backToPortrait': true,
        'lockBlocksBack': true,
        'swipeMiniplayer': true,
        'speedReset': true,
      };
      File('/data/user/0/com.duchaik.ytb/cache/fullscreen-qa.json')
          .writeAsStringSync(jsonEncode(report));
      debugPrint('YTB_FULLSCREEN_QA:${jsonEncode(report)}');
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
