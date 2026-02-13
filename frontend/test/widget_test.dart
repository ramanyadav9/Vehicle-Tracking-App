import 'package:flutter_test/flutter_test.dart';
import 'package:bus_tracker_app/main.dart';

void main() {
  testWidgets('App launches', (WidgetTester tester) async {
    await tester.pumpWidget(const BusTrackerApp());
    expect(find.text('TRANSIT'), findsOneWidget);
  });
}
