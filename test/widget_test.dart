import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Imports your actual game file
import 'package:life_simulator/main.dart'; 

void main() {
  testWidgets('App loads smoke test', (WidgetTester tester) async {
    // 1. Build our app (Using your actual app name)
    await tester.pumpWidget(const LifeSimulatorApp());

    // 2. Verify that the game's title appears on the screen
    expect(find.text('Life Simulator'), findsWidgets);
  });
}