import 'package:flutter/material.dart';
import 'ghost_memory_game_screen.dart';
import 'nback_challenge_screen.dart';
import 'pattern_pulse_screen.dart';
import 'color_word_clash_screen.dart';
import 'path_echo_screen.dart';

class BrainGamesMenuScreen extends StatelessWidget {
  const BrainGamesMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDarkTheme
        ? const Color(0xFF1A1A1A)
        : Colors.white;
    final appBarColor = isDarkTheme ? const Color(0xFF1A1A1A) : Colors.white;
    final textColor = isDarkTheme ? Colors.white : Colors.black87;
    final iconColor = isDarkTheme ? Colors.white70 : Colors.black87;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: appBarColor,
        elevation: 2,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: iconColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '🎮 Brain Games',
          style: TextStyle(
            color: textColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _GameCard(
            title: 'Ghost Memory Tiles',
            icon: '👻',
            description: 'Memorize and match tiles in sequence',
            color: Colors.purpleAccent,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const GhostMemoryGameScreen(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _GameCard(
            title: 'N-Back Challenge',
            icon: '🧠',
            description: 'Match symbols from N steps ago',
            color: Colors.blueAccent,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const NBackChallengeScreen(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _GameCard(
            title: 'Pattern Pulse',
            icon: '🎵',
            description: 'Repeat the color sequence',
            color: Colors.cyan,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const PatternPulseScreen(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _GameCard(
            title: 'Color-Word Clash',
            icon: '🌈',
            description: 'Tap the color, not the word!',
            color: Colors.orange,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const ColorWordClashScreen(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _GameCard(
            title: 'Path Echo',
            icon: '🧩',
            description: 'Memorize and trace the path',
            color: Colors.teal,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const PathEchoScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  final String title;
  final String icon;
  final String description;
  final Color color;
  final VoidCallback onTap;

  const _GameCard({
    required this.title,
    required this.icon,
    required this.description,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDarkTheme ? const Color(0xFF2A2A2A) : Colors.white;
    final textColor = isDarkTheme ? Colors.white : Colors.black87;
    final secondaryTextColor = isDarkTheme ? Colors.white70 : Colors.black54;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(icon, style: const TextStyle(fontSize: 32)),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(color: secondaryTextColor, fontSize: 14),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: color, size: 20),
          ],
        ),
      ),
    );
  }
}
