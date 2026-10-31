import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ytb/main.dart' as app;
import 'package:ytb/shorts_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const player = MethodChannel('ytb/player');
  testWidgets('logo, in-player karaoke, queue and Shorts session transitions', (
    tester,
  ) async {
    await player.invokeMethod('pause');
    await player.invokeMethod('queue',{'items':[],'repeat':0});
    app.main();
    Future<void> waitFor(bool Function() condition, {int seconds = 30}) async {
      for (var i = 0; i < seconds * 4; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        if (condition()) return;
      }
      fail('UI wait timed out');
    }

    Future<Map> state() async => Map.from(await player.invokeMethod('state'));
    Future<Map> playing() async {
      for (var i = 0; i < 990; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        final s = await state();
        if (s['playing'] == true && s['ready'] == true) return s;
      }
      fail('Playback did not start');
    }

    await waitFor(
      () => find.byKey(const Key('video-search-input')).evaluate().isNotEmpty,
    );
    expect(find.text('Duchaik YTB'), findsNothing);
    expect(find.byTooltip('Tìm kiếm bằng giọng nói'), findsOneWidget);
    expect(find.byTooltip('Kết nối TV'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('video-search-input')),
      'https://youtu.be/aqz-KE-bpKQ',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await playing();
    await waitFor(
      () => find.byKey(const Key('related-scroll')).evaluate().isNotEmpty,
    );
    await tester.pump(const Duration(seconds: 2));
    final input = find.byKey(const Key('video-search-input'));
    await tester.ensureVisible(input);
    await tester.enterText(input, 'karaoke tình ca');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump(const Duration(seconds: 3));
    expect((await state())['id'], 'aqz-KE-bpKQ');
    expect((await state())['playing'], true);
    await tester.drag(
      find.byKey(const Key('related-scroll')),
      const Offset(0, -600),
    );
    await tester.pump(const Duration(seconds: 1));
    await waitFor(
      () => find.byTooltip('Tùy chọn bài hát').evaluate().isNotEmpty,
    );
    final menu = find.byTooltip('Tùy chọn bài hát').first;
    await tester.ensureVisible(menu);
    await tester.tap(menu);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Phát tiếp'));
    await tester.pump(const Duration(seconds: 1));
    expect(
      (Map.from(await player.invokeMethod('queue'))['items'] as List).length,
      1,
    );
    expect((await state())['id'], 'aqz-KE-bpKQ');
    await tester.tap(find.text('Shorts'));
    await tester.pump(const Duration(seconds: 2));
    await waitFor(() => find.byType(ShortsPage).evaluate().isNotEmpty);
    var first = await playing();
    expect(first['id'], isNot('aqz-KE-bpKQ'));
    final shortIds = <String>{first['id']};
    for (var i = 0; i < 99; i++) {
      await tester.drag(find.byType(PageView), const Offset(0, -650));
      await tester.pump(const Duration(milliseconds: 700));
      final s = await playing();
      shortIds.add(s['id']);
    }
    expect(shortIds.length, greaterThan(90));
    await tester.tap(find.text('Karaoke'));
    await tester.pump(const Duration(seconds: 2));
    final restored = await playing();
    expect(restored['id'], 'aqz-KE-bpKQ');
    await player.invokeMethod('pause');
    File('/data/user/0/com.duchaik.ytb/cache/features-ui-06.json')
        .writeAsStringSync(
          jsonEncode({
            'logoOnly': true,
            'karaokeKeepsPlayback': true,
            'enqueue': true,
            'shortsDistinct': shortIds.length,
            'restoresLongVideo': true,
          }),
        );
  }, timeout: const Timeout(Duration(minutes: 6)));
}
