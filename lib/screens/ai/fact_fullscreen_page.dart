import 'package:flutter/material.dart';
import '../../widgets/fact_card_deck.dart';

class FactFullScreenPage extends StatelessWidget {
  final List<String> facts;
  const FactFullScreenPage({super.key, required this.facts});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121216),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Today's Fact",
          style: TextStyle(
            color: Colors.white.withOpacity(0.95),
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: FactCardDeck(
          facts: facts,
          onDeckComplete: () => Navigator.pop(context),
        ),
      ),
    );
  }
}
