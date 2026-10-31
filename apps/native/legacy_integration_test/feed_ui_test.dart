import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ytb/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Branded home, automatic pagination and local privacy controls', (
    tester,
  ) async {
    await tester.pumpWidget(const YtbApp());
    Future<void> waitFor(bool Function() condition) async {
      final end = DateTime.now().add(const Duration(seconds: 35));
      do {
        await tester.pump(const Duration(milliseconds: 250));
        if (condition()) return;
      } while (DateTime.now().isBefore(end));
      fail('UI state timed out');
    }

    await waitFor(
      () => find.byType(PopupMenuButton<String>).evaluate().isNotEmpty,
    );
    expect(find.text('Duchaik YTB'), findsOneWidget);
    expect(find.textContaining('Đăng nhập'), findsNothing);
    final list = tester.widget<CustomScrollView>(
      find.byType(CustomScrollView).first,
    );
    final controller = list.controller!;
    final before = controller.position.maxScrollExtent;
    controller.jumpTo(before);
    await waitFor(() => controller.position.maxScrollExtent > before + 1000);
    debugPrint('DUCHAIK_UI: automatic feed pagination passed');
    await tester.tap(find.byTooltip('Cài đặt').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Đề xuất theo thói quen xem'), findsOneWidget);
    expect(find.textContaining('Đăng nhập'), findsNothing);
    final enabled = tester
        .widget<SwitchListTile>(find.byType(SwitchListTile))
        .value;
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      !enabled,
    );
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      enabled,
    );
    expect(tester.takeException(), isNull);
  });
}
