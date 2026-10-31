import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ytb/youtube_account.dart';

void main() {
  test('reads every page with bearer auth and no token in URL', () async {
    var calls = 0;
    final api = YoutubeAccountApi(
      'private-token',
      client: MockClient((request) async {
        expect(request.url.host, 'www.googleapis.com');
        expect(request.url.toString(), isNot(contains('private-token')));
        expect(request.headers['Authorization'], 'Bearer private-token');
        calls++;
        if (calls == 1) {
          return http.Response(
            '{"items":[{"id":"one"}],"nextPageToken":"next"}',
            200,
          );
        }
        expect(request.url.queryParameters['pageToken'], 'next');
        return http.Response('{"items":[{"id":"two"}]}', 200);
      }),
    );
    expect(
      (await api.list('playlists', {
        'part': 'snippet',
        'mine': 'true',
      })).map((e) => e['id']),
      ['one', 'two'],
    );
    expect(calls, 2);
    api.close();
  });
  test('rejects a repeated page instead of looping forever', () async {
    final api = YoutubeAccountApi(
      'token',
      client: MockClient(
        (_) async => http.Response('{"items":[],"nextPageToken":"same"}', 200),
      ),
    );
    await expectLater(
      api.list('subscriptions', {}),
      throwsA(isA<YoutubeAccountError>()),
    );
    api.close();
  });
  for (final code in [401, 403, 500]) {
    test('handles HTTP $code without exposing server response', () async {
      final api = YoutubeAccountApi(
        'token',
        client: MockClient(
          (_) async => http.Response('secret-server-details', code),
        ),
      );
      await expectLater(
        api.list('videos', {}),
        throwsA(
          isA<YoutubeAccountError>().having(
            (e) => e.message,
            'safe message',
            isNot(contains('secret-server-details')),
          ),
        ),
      );
      api.close();
    });
  }
  test('missing OAuth configuration fails before platform login', () async {
    await expectLater(
      YoutubeAccountLogin.authenticate(serverClientId: ''),
      throwsA(isA<YoutubeAccountError>()),
    );
  });
}
