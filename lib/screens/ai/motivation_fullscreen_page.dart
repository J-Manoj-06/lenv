import 'package:flutter/material.dart';
import '../../widgets/motivation_card_deck.dart';
import '../../widgets/swipe_card_deck.dart';

class MotivationFullScreenPage extends StatelessWidget {
  final List<CardData> cards;

  const MotivationFullScreenPage({super.key, required this.cards});

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
          "Today's Motivation",
          style: TextStyle(
            color: Colors.white.withOpacity(0.95),
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: MotivationCardDeck(
          cards: cards,
          onDeckComplete: () => Navigator.pop(context),
        ),
      ),
    );
  }
}
