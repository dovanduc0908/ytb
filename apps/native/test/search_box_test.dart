import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ytb/search_box.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ytb/source');
  late TextEditingController controller;
  late List<String> submitted;
  late List<String> requested;
  late Map<String, Completer<Object?>> replies;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('ytb/player'),
          (_) async => {'remote': false},
        );
    controller = TextEditingController();
    submitted = [];
    requested = [];
    replies = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
          expectSync(call.method, 'suggest');
          final query = call.arguments['query'] as String;
          requested.add(query);
          return (replies[query] = Completer<Object?>()).future;
        });
  });
  tearDown(() {
    controller.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('ytb/player'), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: VideoSearchBox(
              controller: controller,
              onSearch: submitted.add,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(TextField));
    await tester.pump();
  }

  testWidgets(
    'voice final result submits once; cancelling preserves typed query',
    (tester) async {
      final voice = Completer<String?>();
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('ytb/voice'), (call) {
            calls++;
            return voice.future;
          });
      await mount(tester);
      await tester.enterText(find.byType(TextField), 'bản gõ cũ');
      await tester.tap(find.byTooltip('Tìm kiếm bằng giọng nói'));
      await tester.pump();
      await tester.tap(find.byTooltip('Tìm kiếm bằng giọng nói'));
      await tester.pump();
      expect(calls, 1);
      voice.complete('  karaoke tình ca  ');
      await tester.pump();
      await tester.pump();
      expect(submitted, ['karaoke tình ca']);
      expect(controller.text, 'karaoke tình ca');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('ytb/voice'),
            (_) async => null,
          );
      await tester.tap(find.byTooltip('Tìm kiếm bằng giọng nói'));
      await tester.pump();
      expect(submitted.length, 1);
      expect(controller.text, 'karaoke tình ca');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('ytb/voice'), null);
    },
  );
  testWidgets('missing speech service shows recovery and keeps search usable', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('ytb/voice'),
          (_) async => throw PlatformException(
            code: 'UNAVAILABLE',
            message: 'Không có dịch vụ giọng nói',
          ),
        );
    await mount(tester);
    await tester.tap(find.byTooltip('Tìm kiếm bằng giọng nói'));
    await tester.pump();
    expect(find.text('Không có dịch vụ giọng nói'), findsOneWidget);
    expect(submitted, isEmpty);
    await tester.enterText(find.byType(TextField), 'karaoke');
    await tester.tap(find.byTooltip('Tìm kiếm'));
    await tester.pump();
    expect(submitted, ['karaoke']);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('ytb/voice'), null);
  });
  testWidgets(
    'rapid typing makes one request; obsolete reply cannot replace current suggestions',
    (tester) async {
      await mount(tester);
      await tester.enterText(find.byType(TextField), 'n');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), 'nh');
      await tester.pump(const Duration(milliseconds: 100));
      expect(requested, isEmpty);
      await tester.pump(const Duration(milliseconds: 100));
      expect(requested, ['nh']);
      await tester.enterText(find.byType(TextField), 'nhac');
      await tester.pump(const Duration(milliseconds: 200));
      replies['nhac']!.complete({
        'suggestions': ['nhạc thư giãn'],
      });
      await tester.pump();
      expect(find.text('nhạc thư giãn'), findsOneWidget);
      replies['nh']!.complete({
        'suggestions': ['old result'],
      });
      await tester.pump();
      expect(find.text('old result'), findsNothing);
      expect(find.text('nhạc thư giãn'), findsOneWidget);
      expect(submitted, isEmpty);
      await tester.tap(find.text('nhạc thư giãn'));
      await tester.pump();
      expect(submitted, ['nhạc thư giãn']);
      expect(controller.text, 'nhạc thư giãn');
      expect(find.byKey(const Key('search-suggestions')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'clear invalidates in-flight response and keeps input usable offline',
    (tester) async {
      await mount(tester);
      await tester.enterText(find.byType(TextField), 'lofi');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byTooltip('Xóa từ khóa'));
      await tester.pump();
      replies['lofi']!.complete({
        'suggestions': ['stale lofi'],
      });
      await tester.pump();
      expect(find.text('stale lofi'), findsNothing);
      await tester.enterText(find.byType(TextField), 'offline');
      await tester.pump(const Duration(milliseconds: 200));
      replies['offline']!.completeError(PlatformException(code: 'NETWORK'));
      await tester.pump();
      expect(find.textContaining('Chưa tải được gợi ý'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(submitted, ['offline']);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'submit before debounce cancels suggestions and remembers query',
    (tester) async {
      await mount(tester);
      await tester.enterText(find.byType(TextField), 'piano');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump(const Duration(milliseconds: 200));
      expect(requested, isEmpty);
      expect(submitted, ['piano']);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.tap(find.byTooltip('Xóa từ khóa'));
      await tester.pump();
      expect(find.text('piano'), findsOneWidget);
      await tester.tap(find.text('Xóa lịch sử tìm kiếm'));
      await tester.pump();
      expect(find.text('piano'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Vietnamese suggestions do not disturb ongoing IME composition', (
    tester,
  ) async {
    await mount(tester);
    await tester.showKeyboard(find.byType(TextField));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'nhạc',
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange(start: 0, end: 4),
      ),
    );
    await tester.idle();
    await tester.pump(const Duration(milliseconds: 200));
    expect(requested, ['nhạc']);
    expect(controller.value.composing, const TextRange(start: 0, end: 4));
    replies['nhạc']!.complete({
      'suggestions': ['nhạc chill'],
    });
    await tester.pump();
    expect(find.text('nhạc chill'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
