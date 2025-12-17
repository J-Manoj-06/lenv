import 'package:flutter/material.dart';
import '../../widgets/history_card_deck.dart';

class HistoryFullScreenPage extends StatelessWidget {
  final List<HistoryCardData> cards;

  const HistoryFullScreenPage({super.key, required this.cards});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Today in History',
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Swipe to explore • ${cards.length} events',
              style: TextStyle(
                color: Colors.black54,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: HistoryCardDeck(
          cards: cards,
          onDeckComplete: () => Navigator.pop(context),
        ),
      ),
    );
  }
}
