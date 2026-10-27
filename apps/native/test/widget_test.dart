import 'package:flutter_test/flutter_test.dart';
import 'package:ytb/main.dart';

void main() {
  test('YouTube link parsing accepts known hosts, rejects lookalikes', () {
    expect(videoId('https://youtu.be/aqz-KE-bpKQ?t=15'), 'aqz-KE-bpKQ');
    expect(
      videoId('https://www.youtube.com/watch?v=aqz-KE-bpKQ'),
      'aqz-KE-bpKQ',
    );
    expect(videoId('https://youtube.com/shorts/aqz-KE-bpKQ'), 'aqz-KE-bpKQ');
    expect(
      videoId('https://youtube.com.evil.test/watch?v=aqz-KE-bpKQ'),
      isNull,
    );
    expect(videoId('nhạc thư giãn'), isNull);
  });
  test('Speed selector covers the complete requested range', () {
    expect(speeds.length, 14);
    expect(speeds.first, .25);
    expect(speeds.last, 3.5);
    for (var i = 1; i < speeds.length; i++) {
      expect(speeds[i] - speeds[i - 1], 0.25);
    }
  });
  test('Timer display handles hour boundary and clamps negatives', () {
    expect(clock(3600000), '1:00:00');
    expect(clock(61000), '1:01');
    expect(clock(-1000), '0:00');
  });
}
