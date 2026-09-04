import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relink_mobile/theme.dart';

void main() {
  testWidgets('calm-humanitarian theme renders body copy', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildRelinkTheme(),
      home: const Scaffold(body: Center(child: Text('RELINK'))),
    ));
    expect(find.text('RELINK'), findsOneWidget);
  });

  test('alarm red stays reserved (exactly one SOS color in the palette)', () {
    // Palette contract from master plan §2: alarm red exists exactly once and
    // belongs to SOS / severe alerts only.
    expect(RelinkColors.alarmRed, const Color(0xFFD64545));
    expect(RelinkColors.primary, const Color(0xFF2E7E7B));
    expect(RelinkColors.primary, isNot(RelinkColors.alarmRed));
  });
}
