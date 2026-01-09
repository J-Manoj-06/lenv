// Basic widget test that doesn't require Firebase initialization.
// This avoids touching the real app (which uses Firebase during startup),
// and simply validates Flutter rendering and interactions.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _CounterWidget extends StatefulWidget {
  const _CounterWidget();
  @override
  State<_CounterWidget> createState() => _CounterWidgetState();
}

class _CounterWidgetState extends State<_CounterWidget> {
  int _count = 0;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Counter Test')),
      body: Center(child: Text('$_count', key: const Key('count'))),
      floatingActionButton: FloatingActionButton(
        onPressed: () => setState(() => _count++),
        child: const Icon(Icons.add),
      ),
    );
  }
}

void main() {
  testWidgets('Local counter increments', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: _CounterWidget()));

    // Initial state
    expect(find.byKey(const Key('count')), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('1'), findsNothing);

    // Tap FAB and re-pump
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    // State updated
    expect(find.text('0'), findsNothing);
    expect(find.text('1'), findsOneWidget);
  });
}
