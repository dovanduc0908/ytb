import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const player = MethodChannel('ytb/player');
  const source = MethodChannel('ytb/source');
  testWidgets(
    'Refresh failed CDN source and apply real Wi-Fi/cellular transitions',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AndroidView(viewType: 'ytb/video')),
        ),
      );
      Future<Map<String, dynamic>> state() async =>
          Map<String, dynamic>.from(await player.invokeMethod('state'));
      Future<Map<String, dynamic>> waitFor(
        bool Function(Map<String, dynamic>) check, [
        int timeout = 90,
      ]) async {
        final end = DateTime.now().add(Duration(seconds: timeout));
        do {
          await tester.pump(const Duration(milliseconds: 250));
          final s = await state();
          expect(s['error'], isNull);
          if (check(s)) return s;
        } while (DateTime.now().isBefore(end));
        fail('Timeout: ${await state()}');
      }

      await tester.pump(const Duration(seconds: 1));
      final data = Map<String, dynamic>.from(
        await source.invokeMethod('resolveFacebook', {
          'url': 'https://web.facebook.com/reel/28955594210740984',
        }),
      );
      final tracks = (data['tracks'] as List)
          .map((v) => Map<String, dynamic>.from(v))
          .toList();
      final broken = Map<String, dynamic>.from(tracks.last);
      broken['url'] = Uri.parse(broken['url'])
          .replace(path: '/ytb-qa-intentionally-missing.mp4', query: '')
          .toString();
      await player.invokeMethod('load', {
        'id': data['id'],
        'title': data['title'],
        'tracks': [broken],
        'position': 30000,
        'metadata': data,
      });
      final recovered = await waitFor(
        (s) => s['playing'] == true && (s['position'] as num? ?? 0) >= 30000,
        120,
      );
      expect(recovered['audio'], isNotNull);
      final report = <String, dynamic>{
        'recoveredAt': recovered['position'],
        'recoveredHeight': recovered['height'],
      };
      await player.invokeMethod('quality', {'height': tracks.last['height']});
      await waitFor(
        (s) =>
            s['qualityMode'] == tracks.last['height'] && s['playing'] == true,
      );
      debugPrint('NETWORK_QA_READY');
      final cellular = await waitFor(
        (s) =>
            s['networkPolicy'] == 'cellular' &&
            s['qualityMode'] == 0 &&
            s['playing'] == true &&
            (s['height'] as num? ?? 9999) <= 480,
      );
      report['cellularHeight'] = cellular['height'];
      report['cellularPosition'] = cellular['position'];
      debugPrint('NETWORK_QA_CELLULAR_OK');
      final wifi = await waitFor(
        (s) =>
            s['networkPolicy'] == 'wifi' &&
            s['qualityMode'] == 0 &&
            s['height'] == tracks.last['height'] &&
            s['playing'] == true,
      );
      report['wifiHeight'] = wifi['height'];
      report['wifiPosition'] = wifi['position'];
      expect(wifi['position'], greaterThan(cellular['position'] as num));
      await player.invokeMethod('pause');
      File('/data/user/0/com.duchaik.ytb/cache/network-recovery.json')
          .writeAsStringSync(jsonEncode(report));
      debugPrint('NETWORK_QA_DONE: $report');
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
