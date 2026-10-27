import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const source = MethodChannel('ytb/source'),
      player = MethodChannel('ytb/player');
  testWidgets('real audio, channel pages and learned background music queue', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AndroidView(viewType: 'ytb/video')),
      ),
    );
    await tester.runAsync(() async {
      Future<Map> state() async => Map.from(await player.invokeMethod('state'));
      Future<Map> until(bool Function(Map) done, [int seconds = 35]) async {
        final end = DateTime.now().add(Duration(seconds: seconds));
        do {
          final s = await state();
          expect(s['error'], isNull);
          if (done(s)) return s;
          await Future<void>.delayed(const Duration(milliseconds: 250));
        } while (DateTime.now().isBefore(end));
        fail('Timeout: ${await state()}');
      }

      final oldQueue = Map.from(await player.invokeMethod('queue'));
      final before = await state();
      debugPrint('MUSIC_BEFORE:${before['musicLearning']}');
      await player.invokeMethod('musicAuto', {'enabled': true});
      await player.invokeMethod('queue', {'items': [], 'repeat': 0});
      try {
        final results = Map.from(
          await source.invokeMethod('search', {
            'query': 'Sơn Tùng M-TP official music video',
          }),
        );
        final songs = <Map>[];
        for (final card in (results['videos'] as List).take(16)) {
          final media = Map.from(
            await source.invokeMethod('resolve', {'id': card['id']}),
          );
          if (media['category'] == 'Music' &&
              (media['duration'] as num) >= 45 &&
              (media['duration'] as num) <= 1800) {
            songs.add(media);
          }
          if (songs.length == 6) break;
        }
        expect(songs.length, 6);
        final first = songs.first;
        expect(int.tryParse('${first['views']}'), greaterThan(0));
        expect(first['channelId'], startsWith('UC'));
        final channel = Map.from(
          await source.invokeMethod('channel', {'id': first['channelId']}),
        );
        expect((channel['videos'] as List).length, greaterThan(0));
        if (channel['continuation'] != null) {
          final next = Map.from(
            await source.invokeMethod('channel', {
              'id': first['channelId'],
              'continuation': channel['continuation'],
            }),
          );
          final ids = (channel['videos'] as List).map((v) => v['id']).toSet();
          expect(
            (next['videos'] as List).any((v) => !ids.contains(v['id'])),
            true,
          );
        }
        debugPrint(
          'AUDIO_CHANNEL:${jsonEncode({
            'title': first['title'],
            'views': first['views'],
            'channel': channel['title'],
            'videos': (channel['videos'] as List).length,
            'track': {'mime': first['tracks'][0]['audioMime'], 'bitrate': first['tracks'][0]['audioBitrate'], 'gain': first['tracks'][0]['audioGain']},
          })}',
        );
        for (var i = 0; i < songs.length; i++) {
          final media = songs[i];
          await player.invokeMethod('load', {
            'id': media['id'],
            'title': media['title'],
            'author': media['author'],
            'tracks': media['tracks'],
            'metadata': Map.from(media)..remove('tracks'),
            'position': 0,
          });
          await player.invokeMethod('speed', {'value': 1.0});
          await until((s) => s['playing'] == true && s['audio'] != null);
          await until((s) => (s['musicLearning'] as num) >= i + 1, 45);
          final s = await state();
          debugPrint(
            'MUSIC_LEARN:${jsonEncode({'number': i + 1, 'id': s['id'], 'audio': s['audio'], 'bitrate': s['audioBitrate'], 'channels': s['audioChannels'], 'sampleRate': s['sampleRate'], 'underruns': s['audioUnderruns'], 'learned': s['musicLearning']})}',
          );
        }
        await until((s) => (s['musicLearning'] as num) >= 6);
        final end = DateTime.now().add(const Duration(seconds: 90));
        Map queue;
        do {
          queue = Map.from(await player.invokeMethod('queue'));
          if ((queue['items'] as List).isNotEmpty) break;
          await Future<void>.delayed(const Duration(seconds: 1));
        } while (DateTime.now().isBefore(end));
        expect((queue['items'] as List).length, greaterThanOrEqualTo(3));
        expect(
          (queue['items'] as List).every((v) => v['autoMusic'] == true),
          true,
        );
        final nextId = queue['items'][0]['id'];
        final s = await state();
        await player.invokeMethod('seek', {
          'position': (s['duration'] as num).toInt() - 500,
        });
        final next = await until(
          (s) => s['id'] == nextId && s['playing'] == true,
          60,
        );
        expect(next['audio'], isNotNull);
        // A film discards automatic music entries but never synthesizes a movie queue.
        final movie = Map.from(
          await source.invokeMethod('resolve', {'id': 'aqz-KE-bpKQ'}),
        );
        await player.invokeMethod('load', {
          'id': movie['id'],
          'tracks': movie['tracks'],
          'title': movie['title'],
          'author': movie['author'],
          'metadata': Map.from(movie)..remove('tracks'),
        });
        expect((await state())['isMusic'], false);
        expect(
          (Map.from(await player.invokeMethod('queue'))['items'] as List).where(
            (v) => v['autoMusic'] == true,
          ),
          isEmpty,
        );
        debugPrint(
          'MUSIC_QUEUE:learned-six; automatic-next; movie-excluded; PASS',
        );
      } finally {
        await player.invokeMethod('pause');
        if (before['musicLearning'] == 0) {
          await player.invokeMethod('musicAuto', {'clear': true});
        }
        await player.invokeMethod('musicAuto', {
          'enabled': before['musicAuto'] == true,
        });
        await player.invokeMethod('queue', {
          'items': oldQueue['items'],
          'repeat': oldQueue['repeat'],
        });
      }
    });
  }, timeout: const Timeout(Duration(minutes: 9)));
}
