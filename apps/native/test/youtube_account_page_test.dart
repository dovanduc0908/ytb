import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ytb/youtube_account_page.dart';

void main() {
  testWidgets('large text remains scrollable in a short landscape viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(640, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const YoutubeAccountPage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(NestedScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Playlist').hitTestable(), findsOneWidget);
  });

  testWidgets('cancel consent leaves login available and no account data', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: YoutubeAccountPage()));
    await tester.tap(find.text('Đăng nhập'));
    await tester.pumpAndSettle();
    expect(find.text('Tiếp tục với Google'), findsOneWidget);
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    expect(find.text('Chưa kết nối Google'), findsOneWidget);
    expect(find.text('Ngắt kết nối'), findsNothing);
    await tester.tap(find.text('Đăng nhập'));
    await tester.pumpAndSettle();
    expect(find.text('Tiếp tục với Google'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account page and consent fit a small landscape screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(640, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: YoutubeAccountPage()));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Đăng nhập'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Hủy').hitTestable(), findsOneWidget);
    expect(find.text('Tiếp tục với Google').hitTestable(), findsOneWidget);
  });
}
