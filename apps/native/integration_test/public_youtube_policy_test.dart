import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const source = MethodChannel('ytb/source');
  const player = MethodChannel('ytb/player');
  testWidgets('native boundaries reject YouTube extraction and direct media', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    var ready = false;
    for (var attempt = 0; attempt < 20 && !ready; attempt++) {
      try {
        await player.invokeMethod('state');
        ready = true;
      } on PlatformException {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    expect(
      ready,
      isTrue,
      reason: 'Test must exercise a running player service',
    );
    for (final method in [
      'resolve',
      'resolveFull',
      'search',
      'related',
      'charts',
    ]) {
      await expectLater(
        source.invokeMethod(method, {'id': 'aqz-KE-bpKQ', 'query': 'video'}),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'official playback required',
            'OFFICIAL_YOUTUBE',
          ),
        ),
      );
    }
    await expectLater(
      player.invokeMethod('load', {
        'id': 'aqz-KE-bpKQ',
        'tracks': [
          {
            'height': 360,
            'url': 'https://rr1.googlevideo.com/video',
            'mime': 'video/mp4',
          },
        ],
      }),
      throwsA(
        isA<PlatformException>()
            .having((e) => e.code, 'code', 'PLAYER')
            .having(
              (e) => e.message,
              'reject native YouTube',
              contains('YouTube'),
            ),
      ),
    );
    await expectLater(
      player.invokeMethod('load', {
        'id': 'https://www.facebook.com/watch/?v=12345',
        'tracks': [
          {
            'height': 360,
            'url': 'https://rr1.googlevideo.com/video',
            'mime': 'video/mp4',
          },
        ],
      }),
      throwsA(
        isA<PlatformException>()
            .having((e) => e.code, 'code', 'PLAYER')
            .having(
              (e) => e.message,
              'reject mismatched CDN',
              contains('Nguồn phát'),
            ),
      ),
    );
    await expectLater(
      player.invokeMethod('offlineData', {'id': 'aqz-KE-bpKQ'}),
      throwsA(
        isA<PlatformException>()
            .having((e) => e.code, 'code', 'PLAYER')
            .having(
              (e) => e.message,
              'reject offline YouTube',
              contains('YouTube'),
            ),
      ),
    );
  });
}
