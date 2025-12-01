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
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        elevation: 2,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '🎮 Brain Games',
          style: TextStyle(
            color: Colors.white,
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
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
