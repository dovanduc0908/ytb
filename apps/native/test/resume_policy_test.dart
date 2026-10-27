import 'package:flutter_test/flutter_test.dart';
import 'package:ytb/resume_policy.dart';

void main() {
  test('only finite videos longer than 30 minutes resume', () {
    expect(resumePosition(duration: 1800000, position: 50000), 0);
    expect(resumePosition(duration: 1801000, position: 50000), 50000);
    expect(resumePosition(duration: 3600000, position: 50000, isLive: true), 0);
    expect(
      resumePosition(duration: 3600000, position: 50000, isShort: true),
      0,
    );
    expect(resumePosition(duration: 3600000, position: 3590000), 0);
    expect(resumePosition(duration: 3600000, position: 0), 0);
  });
}
