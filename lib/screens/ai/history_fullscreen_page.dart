import 'package:flutter/material.dart';
import '../../widgets/history_card_deck.dart';

class HistoryFullScreenPage extends StatelessWidget {
  final List<HistoryCardData> cards;

  const HistoryFullScreenPage({super.key, required this.cards});

  @override
  Widget build(BuildContext context) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDarkTheme ? const Color(0xFF121212) : Colors.white;
    final appBarColor = isDarkTheme ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDarkTheme ? Colors.white : Colors.black87;
    final subtitleColor = isDarkTheme ? Colors.grey.shade400 : Colors.black54;
    final iconColor = isDarkTheme ? Colors.white : Colors.black87;
    
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: appBarColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: iconColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Today in History',
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Swipe to explore • ${cards.length} events',
              style: TextStyle(
                color: subtitleColor,
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
