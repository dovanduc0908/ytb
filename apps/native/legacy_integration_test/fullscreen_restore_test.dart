import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const player = MethodChannel('ytb/player');
  testWidgets('fullscreen restores volume and brightness for each visit', (
    tester,
  ) async {
    Future<double> adjust(String kind, double delta) async =>
        (await player.invokeMethod<num>('adjust', {
          'kind': kind,
          'delta': delta,
        }))!.toDouble();
    final originalVolume = await adjust('volume', 0);
    final originalBrightness = await adjust('brightness', 0);
    try {
      for (var i = 0; i < 2; i++) {
        await player.invokeMethod('fullscreen', {'enabled': true});
        await adjust('volume', originalVolume > .5 ? -.3 : .3);
        await adjust('brightness', originalBrightness > .5 ? -.3 : .3);
        await player.invokeMethod('fullscreen', {'enabled': false});
        expect(await adjust('volume', 0), closeTo(originalVolume, .01));
        expect(await adjust('brightness', 0), closeTo(originalBrightness, .01));
      }
    } finally {
      await player.invokeMethod('fullscreen', {'enabled': false});
      await adjust('volume', originalVolume - await adjust('volume', 0));
      await adjust(
        'brightness',
        originalBrightness - await adjust('brightness', 0),
      );
    }
  });
}
