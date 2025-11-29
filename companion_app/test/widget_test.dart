import 'package:companion_app/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders Nano Companion home UI', (WidgetTester tester) async {
    await tester.pumpWidget(const CompanionApp());
    expect(find.text('Nano Companion'), findsOneWidget);
    expect(find.text('Request Permissions'), findsOneWidget);
  });
}
