import 'package:flutter_test/flutter_test.dart';

import 'package:relink_mobile/main.dart';

void main() {
  testWidgets('placeholder app renders RELINK', (WidgetTester tester) async {
    await tester.pumpWidget(const RelinkApp());
    expect(find.text('RELINK'), findsOneWidget);
  });
}
