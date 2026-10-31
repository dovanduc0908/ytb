import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ytb/player_overlay.dart';
import 'package:ytb/main.dart' show clock;

void main() {
  for (final size in [const Size(900, 500), const Size(500, 900)]) {
    for (final inset in [0.0, 80.0]) {
      testWidgets('system top swipe leaves playback unchanged: $size / $inset', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final adjustments = <String>[];
        final seeks = <int>[];
        final speeds = <double>[];
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                viewPadding: EdgeInsets.only(top: inset),
                systemGestureInsets: EdgeInsets.only(top: inset),
              ),
              child: Material(
                child: PlayerOverlay(
                  video: const ColoredBox(color: Colors.black),
                  visible: false,
                  fullscreen: true,
                  loading: false,
                  state: const {
                    'playing': true,
                    'position': 30000,
                    'duration': 180000,
                    'speed': 1.0,
                  },
                  onToggle: () {},
                  onPlay: () {},
                  onSeek: seeks.add,
                  onFullscreen: () {},
                  onSettings: () {},
                  formatTime: clock,
                  onSpeed: speeds.add,
                  onAdjust: (kind, delta) async {
                    adjustments.add(kind);
                    return .5;
                  },
                ),
              ),
            ),
          ),
        );
        for (final x in [size.width * .2, size.width * .8]) {
          for (final y in [2.0, 40.0, if (inset > 48) 70.0]) {
            final gesture = await tester.startGesture(Offset(x, y));
            // A fast first move can put the recognizer's start point well
            // outside the protected strip: classify using pointer-down.
            await gesture.moveBy(const Offset(0, 160));
            await gesture.moveBy(const Offset(0, 100));
            await gesture.up();
            await tester.pump();
          }
        }
        final cancelled = await tester.startGesture(const Offset(100, 2));
        await cancelled.moveBy(const Offset(80, 160));
        await cancelled.cancel();
        await tester.pump();
        expect(adjustments, isEmpty);
        expect(seeks, isEmpty);
        expect(speeds, isEmpty);
        expect(find.byKey(const Key('adjustment-volume')), findsNothing);
        expect(find.byKey(const Key('adjustment-brightness')), findsNothing);
        // A fresh gesture in the video still works after release/cancellation.
        await tester.dragFrom(
          Offset(size.width * .2, size.height * .5),
          const Offset(0, -100),
        );
        await tester.pump();
        await tester.dragFrom(
          Offset(size.width * .8, size.height * .5),
          const Offset(0, -100),
        );
        await tester.pump();
        expect(adjustments, containsAll(['brightness', 'volume']));
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
  testWidgets('center controls select the previous and next video', (
    tester,
  ) async {
    var previous = 0;
    var next = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 400,
            child: PlayerOverlay(
              video: const ColoredBox(color: Colors.black),
              visible: true,
              fullscreen: false,
              loading: false,
              state: const {
                'playing': true,
                'position': 2000,
                'duration': 60000,
              },
              onToggle: () {},
              onPlay: () {},
              onSeek: (_) {},
              onPrevious: () => previous++,
              onNext: () => next++,
              onFullscreen: () {},
              onSettings: () {},
              formatTime: clock,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Video trước'));
    await tester.tap(find.byTooltip('Video tiếp theo'));
    expect(previous, 1);
    expect(next, 1);
  });
  testWidgets('subtitles stay readable above the video', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 400,
            child: PlayerOverlay(
              video: const ColoredBox(color: Colors.black),
              visible: false,
              fullscreen: true,
              loading: false,
              state: const {
                'playing': true,
                'position': 2000,
                'duration': 60000,
                'captionText': 'Xin chào',
              },
              onToggle: () {},
              onPlay: () {},
              onSeek: (_) {},
              onFullscreen: () {},
              onSettings: () {},
              formatTime: clock,
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('subtitle-text')), findsOneWidget);
    expect(find.text('Xin chào'), findsOneWidget);
  });
  testWidgets(
    'fullscreen zones adjust, seek once, zoom, and lock blocks touches',
    (tester) async {
      tester.view.physicalSize = const Size(900, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final adjustments = <String>[];
      final rates = <double>[];
      final seeks = <int>[];
      var toggles = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerOverlay(
              video: const ColoredBox(color: Colors.black),
              visible: true,
              fullscreen: true,
              state: const {
                'playing': true,
                'position': 30000,
                'duration': 180000,
                'speed': 1.0,
              },
              loading: false,
              onToggle: () => toggles++,
              onPlay: () {},
              onSeek: seeks.add,
              onFullscreen: () {},
              onSettings: () {},
              formatTime: clock,
              onSpeed: rates.add,
              onAdjust: (kind, delta) async {
                adjustments.add(kind);
                return .5;
              },
            ),
          ),
        ),
      );
      await tester.dragFrom(const Offset(750, 240), const Offset(0, -100));
      await tester.pump();
      expect(adjustments, contains('volume'));
      expect(
        tester.getRect(find.byKey(const Key('adjustment-volume'))).left,
        inInclusiveRange(500, 600),
      );
      await tester.dragFrom(const Offset(150, 240), const Offset(0, -100));
      await tester.pump();
      expect(adjustments, contains('brightness'));
      expect(
        tester.getRect(find.byKey(const Key('adjustment-brightness'))).right,
        inInclusiveRange(300, 400),
      );
      await tester.dragFrom(const Offset(450, 390), const Offset(0, -430));
      await tester.pump();
      expect(rates, isNotEmpty);
      expect(rates.last, 3.75);
      expect(find.byKey(const Key('adjustment-speed')), findsOneWidget);
      await tester.dragFrom(const Offset(450, 390), const Offset(0, 300));
      await tester.pump();
      expect(rates.last, .25);
      final drag = await tester.startGesture(const Offset(250, 100));
      await drag.moveBy(const Offset(30, 0));
      await drag.moveBy(const Offset(180, 0));
      await tester.pump();
      expect(seeks, isEmpty);
      await drag.up();
      await tester.pump();
      expect(seeks, hasLength(1));
      expect(seeks.single, greaterThan(30000));
      final middleSwipe = await tester.startGesture(const Offset(150, 240));
      await middleSwipe.moveBy(const Offset(30, 0));
      await middleSwipe.moveBy(const Offset(130, 0));
      await tester.pump();
      final swipePreview = tester.getRect(
        find.byKey(const Key('seek-time-preview')),
      );
      expect(
        swipePreview.top,
        greaterThan(tester.getRect(find.byType(PlayerOverlay)).center.dy),
      );
      await middleSwipe.up();
      await tester.pump();
      expect(seeks, hasLength(2));
      final finger1 = await tester.startGesture(
        const Offset(300, 250),
        pointer: 1,
      );
      final finger2 = await tester.startGesture(
        const Offset(600, 250),
        pointer: 2,
      );
      await finger1.moveBy(const Offset(-100, 0));
      await finger2.moveBy(const Offset(100, 0));
      await tester.pump();
      await finger1.up();
      await finger2.up();
      await tester.pump();
      expect(find.byTooltip('Đặt lại thu phóng'), findsOneWidget);
      await tester.tap(find.byTooltip('Khóa màn hình'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Mở khóa màn hình'), findsNothing);
      final count = adjustments.length;
      await tester.dragFrom(const Offset(750, 240), const Offset(0, -100));
      await tester.tapAt(const Offset(150, 240));
      await tester.pump(const Duration(milliseconds: 400));
      expect(adjustments.length, count);
      expect(toggles, 0);
      expect(find.byTooltip('Mở khóa màn hình'), findsOneWidget);
      await tester.tapAt(const Offset(150, 240));
      await tester.pump();
      expect(find.byTooltip('Mở khóa màn hình'), findsNothing);
      await tester.tapAt(const Offset(150, 240));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(find.byTooltip('Mở khóa màn hình'), findsNothing);
      await tester.tapAt(const Offset(150, 240));
      await tester.pump();
      await tester.tap(find.byTooltip('Mở khóa màn hình'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Đặt lại thu phóng'), findsOneWidget);
      await tester.tap(find.byTooltip('Đặt lại thu phóng'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Đặt lại thu phóng'), findsNothing);
    },
  );

  testWidgets('timeline drag displays target time and signed seek distance', (
    tester,
  ) async {
    final seeks = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerOverlay(
            video: const ColoredBox(color: Colors.black),
            visible: true,
            fullscreen: false,
            state: const {
              'playing': true,
              'position': 10000,
              'duration': 60000,
            },
            loading: false,
            onToggle: () {},
            onPlay: () {},
            onSeek: seeks.add,
            onFullscreen: () {},
            onSettings: () {},
            formatTime: clock,
          ),
        ),
      ),
    );
    final drag = await tester.startGesture(
      tester.getCenter(find.byType(Slider)),
    );
    await drag.moveBy(const Offset(70, 0));
    await tester.pump();
    expect(find.textContaining(RegExp(r'0:\d{2}  \+0:\d{2}')), findsOneWidget);
    final preview = tester.getRect(find.byKey(const Key('seek-time-preview')));
    final slider = tester.getRect(find.byType(Slider));
    expect(preview.bottom, lessThan(slider.top));
    expect(slider.top - preview.bottom, lessThan(12));
    expect(seeks, isEmpty);
    await drag.up();
    await tester.pump();
    expect(seeks, hasLength(1));
    expect(find.byKey(const Key('seek-time-preview')), findsNothing);
  });

  testWidgets(
    'horizontal swipe shows a bottom progress indicator when controls are hidden',
    (tester) async {
      tester.view.physicalSize = const Size(900, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final seeks = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerOverlay(
              video: const ColoredBox(color: Colors.black),
              visible: false,
              fullscreen: true,
              state: const {
                'playing': true,
                'position': 30000,
                'duration': 180000,
              },
              loading: false,
              onToggle: () {},
              onPlay: () {},
              onSeek: seeks.add,
              onFullscreen: () {},
              onSettings: () {},
              formatTime: clock,
            ),
          ),
        ),
      );
      final swipe = await tester.startGesture(const Offset(150, 250));
      await swipe.moveBy(const Offset(40, 0));
      await swipe.moveBy(const Offset(120, 0));
      await tester.pump();
      expect(find.byKey(const Key('seek-gesture-progress')), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const Key('seek-time-preview'))).top,
        greaterThan(250),
      );
      expect(seeks, isEmpty);
      await swipe.up();
      await tester.pump(const Duration(milliseconds: 100));
      expect(seeks, hasLength(1));
      expect(find.byKey(const Key('seek-gesture-progress')), findsNothing);
    },
  );

  testWidgets('slow downward swipe minimizes without requiring a fling', (
    tester,
  ) async {
    var minimized = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerOverlay(
            video: const ColoredBox(color: Colors.black),
            visible: false,
            fullscreen: false,
            state: const {'playing': true, 'duration': 60000},
            loading: false,
            onToggle: () {},
            onPlay: () {},
            onSeek: (_) {},
            onFullscreen: () {},
            onSettings: () {},
            formatTime: clock,
            onMinimize: () => minimized++,
          ),
        ),
      ),
    );
    await tester.timedDragFrom(
      const Offset(200, 150),
      const Offset(0, 200),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    expect(minimized, 1);
  });

  testWidgets('double tap accumulates ten seconds and clamps at both ends', (
    tester,
  ) async {
    final seeks = <int>[];
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SeekGestureSurface(
            position: 5000,
            duration: 20000,
            enabled: true,
            onToggle: () => taps++,
            onSeek: seeks.add,
          ),
        ),
      ),
    );
    final bounds = tester.getRect(find.byType(SeekGestureSurface));
    Future<void> doubleAt(Offset point) async {
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 150));
    }

    await doubleAt(Offset(bounds.left + 40, bounds.center.dy));
    expect(seeks.last, 0);
    expect(taps, 0);
    await doubleAt(Offset(bounds.right - 40, bounds.center.dy));
    expect(seeks.last, 10000);
    await doubleAt(Offset(bounds.right - 40, bounds.center.dy));
    expect(seeks.last, 20000);
    await doubleAt(Offset(bounds.right - 40, bounds.center.dy));
    expect(seeks.last, 20000);
    await tester.pump(const Duration(seconds: 1));
    await tester.tapAt(bounds.center);
    await tester.pump(const Duration(milliseconds: 400));
    expect(taps, 1);
  });
  testWidgets('Dragging previews locally and sends only one seek on release', (
    tester,
  ) async {
    final seeks = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SeekSlider(position: 0, duration: 60000, onSeek: seeks.add),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Slider)),
    );
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(seeks, isEmpty);
    await gesture.up();
    await tester.pump();
    expect(seeks, hasLength(1));
    expect(seeks.single, greaterThan(30000));
  });
  testWidgets('fullscreen picture fills landscape; controls pause and exit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var fullTaps = 0, plays = 0;
    const picture = Key('picture');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerOverlay(
            video: const ColoredBox(key: picture, color: Colors.black),
            visible: true,
            fullscreen: true,
            state: const {
              'playing': true,
              'position': 20000,
              'duration': 60000,
            },
            loading: false,
            onToggle: () {},
            onPlay: () => plays++,
            onSeek: (_) {},
            onFullscreen: () => fullTaps++,
            onSettings: () {},
            formatTime: clock,
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(picture)), const Size(900, 400));
    await tester.tap(find.byTooltip('Tạm dừng'));
    await tester.tap(find.byTooltip('Thoát toàn màn hình'));
    expect(plays, 1);
    expect(fullTaps, 1);
    expect(tester.takeException(), isNull);
  });
}
