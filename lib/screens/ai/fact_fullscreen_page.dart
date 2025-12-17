import 'package:flutter/material.dart';
import '../../widgets/fact_card_deck.dart';

class FactFullScreenPage extends StatelessWidget {
  final List<String> facts;
  const FactFullScreenPage({super.key, required this.facts});

  @override
  Widget build(BuildContext context) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDarkTheme ? const Color(0xFF121212) : Colors.white;
    final appBarColor = isDarkTheme ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDarkTheme ? Colors.white : Colors.black87;
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
        title: Text(
          "Today's Fact",
          style: TextStyle(
            color: textColor,
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
