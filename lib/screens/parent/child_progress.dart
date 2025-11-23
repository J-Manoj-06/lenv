import 'package:flutter/material.dart';

class ChildProgressScreen extends StatelessWidget {
  const ChildProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Child Progress')),
      body: const Center(child: Text('Child Progress - Coming Soon')),
    );
  }
}
