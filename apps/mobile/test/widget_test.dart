import 'package:flutter_test/flutter_test.dart';

import 'package:sicklers_warriors/app.dart';

void main() {
  testWidgets('App renders login page', (WidgetTester tester) async {
    await tester.pumpWidget(const SicklersWarriorsApp());
    await tester.pumpAndSettle();

    expect(find.text('Login'), findsWidgets);
  });
}
