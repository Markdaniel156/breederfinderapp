// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:breederfinderapp/main.dart';
import 'package:breederfinderapp/services/geofencing_service.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Create a mock or real GeofencingService for the test
    final geofenceService = GeofencingService();

    // Build our app and trigger a frame.
    // We pass the geofenceService because MyApp requires it.
    await tester.pumpWidget(MyApp(geofenceService: geofenceService));

    // Verify that the login screen is shown (contains 'Breeder Finder')
    expect(find.text('Breeder Finder'), findsOneWidget);
  });
}
