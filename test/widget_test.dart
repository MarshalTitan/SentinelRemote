import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sentinel_remote/main.dart';

void main() {
  testWidgets('unpaired app has no sample characters or active game actions', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(const SentinelRemoteApp());
    await tester.pumpAndSettle();
    expect(find.text('Sentinel Remote'), findsOneWidget);
    expect(find.text('Pair a PC to get started.'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
    for (final label in ['Screenshot', 'Skip + keep queue', 'Stop + reset']) {
      final button = find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
      );
      expect(button, findsOneWidget);
      expect(tester.widget<ButtonStyleButton>(button).onPressed, isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
