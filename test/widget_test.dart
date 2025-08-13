// FILE: test/widget_test.dart (nouveau)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_wifi_control/main.dart';

void main() {
  testWidgets('App renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const RobotApp());
    
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Robot WiFi Control'), findsOneWidget);
  });
}