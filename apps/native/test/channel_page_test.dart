import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ytb/channel_page.dart';
import 'package:ytb/video_meta.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('view labels distinguish lifetime counts from chart-period counts', () {
    expect(viewsLabel({'views': '1234567'}), '1.234.567 lượt xem');
    expect(
      viewsLabel({'views': '123', 'chartDate': '2026-10-27'}),
      contains('trong kỳ BXH'),
    );
    expect(viewsLabel({'views': '1,2 triệu lượt xem'}), '1,2 triệu lượt xem');
    expect(viewsLabel({}), 'Chưa có số lượt xem');
  });
  testWidgets(
    'creator page resolves missing channel, deduplicates pages and plays',
    (tester) async {
      final calls = <String>[];
      final played = <Map>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('ytb/source'), (
            call,
          ) async {
            calls.add(call.method);
            if (call.method == 'resolve') return {'channelId': 'UC123'};
            if (call.arguments['continuation'] == 'page2') {
              return {
                'videos': [
                  {'id': 'one', 'title': 'One'},
                  {'id': 'two', 'title': 'Two', 'views': '42'},
                ],
              };
            }
            return {
              'title': 'Creator',
              'description': 'Channel description',
              'videos': [
                {'id': 'one', 'title': 'One', 'views': '100'},
              ],
              'continuation': 'page2',
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel('ytb/source'), null),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ChannelPage(
                      video: const {'id': 'seed', 'author': 'Creator'},
                      onPlay: played.add,
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(calls, ['resolve', 'channel']);
      expect(find.text('100 lượt xem'), findsOneWidget);
      await tester.tap(find.text('Tải thêm video'));
      await tester.pumpAndSettle();
      expect(find.text('One'), findsOneWidget);
      await tester.tap(find.text('Two'));
      await tester.pumpAndSettle();
      expect(played.single['channelId'], 'UC123');
      expect(find.text('Open'), findsOneWidget);
    },
  );
}
