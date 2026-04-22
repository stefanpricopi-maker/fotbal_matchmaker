import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('smoke — Material se construiește', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Text('SIMF'),
        ),
      ),
    );
    expect(find.text('SIMF'), findsOneWidget);
  });
}
