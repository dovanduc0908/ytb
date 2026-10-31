import 'package:flutter_test/flutter_test.dart';
import 'package:ytb/official_youtube.dart';

void main() {
  test(
    'routes videos and playlists to official YouTube without extraction',
    () {
      expect(
        OfficialYoutube.destination('aqz-KE-bpKQ').queryParameters['v'],
        'aqz-KE-bpKQ',
      );
      expect(
        OfficialYoutube.destination('https://youtu.be/aqz-KE-bpKQ').host,
        'www.youtube.com',
      );
      expect(
        OfficialYoutube.destination(
          'https://www.youtube.com/playlist?list=PL123',
        ).queryParameters['list'],
        'PL123',
      );
    },
  );
  test(
    'untrusted URLs become search text and cannot select an external host',
    () {
      for (final value in [
        'https://youtube.com.evil.test/watch?v=aqz-KE-bpKQ',
        'https://user@youtube.com/watch?v=aqz-KE-bpKQ',
        'javascript:alert(1)',
        'https://youtube.com:8443/watch?v=aqz-KE-bpKQ',
        'nhạc của tôi',
      ]) {
        final destination = OfficialYoutube.destination(value);
        expect(destination.host, 'www.youtube.com');
        expect(destination.path, '/results');
        expect(destination.queryParameters['search_query'], value);
      }
    },
  );
}
