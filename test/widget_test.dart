import 'package:flutter_test/flutter_test.dart';
import 'package:p2p_sync_app/main.dart';

void main() {
  testWidgets('SpDrop app shell renders', (WidgetTester tester) async {
    await tester.pumpWidget(const SpDropApp());
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('SpDrop'), findsWidgets);
  });
}
