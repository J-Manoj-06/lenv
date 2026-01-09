import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/color_word_clash_provider.dart';

class ColorWordClashScreen extends StatelessWidget {
  const ColorWordClashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ColorWordClashProvider(),
      child: const _ColorWordClashContent(),
    );
  }
}

class _ColorWordClashContent extends StatelessWidget {
  const _ColorWordClashContent();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ColorWordClashProvider>();
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDarkTheme
        ? const Color(0xFF1A1A1A)
        : Colors.white;
    final appBarColor = isDarkTheme ? const Color(0xFF1A1A1A) : Colors.white;
    final textColor = isDarkTheme ? Colors.white : Colors.black87;
    final secondaryTextColor = isDarkTheme ? Colors.white70 : Colors.black54;
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
          '🌈 Color-Word Clash',
          style: TextStyle(
            color: textColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Score: ${provider.score}',
                    style: const TextStyle(
                      color: Color(0xFFFF8A00),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Best: ${provider.highScore}',
                    style: TextStyle(color: secondaryTextColor, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: provider.gameState == GameState.idle
          ? _buildStartScreen(context, provider)
          : provider.gameState == GameState.gameOver
          ? _buildGameOverScreen(context, provider)
          : _buildGameScreen(context, provider),
    );
  }

  Widget _buildStartScreen(
    BuildContext context,
    ColorWordClashProvider provider,
  ) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkTheme ? Colors.white : Colors.black87;
    final secondaryTextColor = isDarkTheme ? Colors.white70 : Colors.black54;
    final cardColor = isDarkTheme
        ? const Color(0xFF2A2A2A)
        : Colors.grey.shade100;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🌈', style: TextStyle(fontSize: 80)),
            const SizedBox(height: 24),
            Text(
              'Color-Word Clash',
              style: TextStyle(
                color: textColor,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Tap the COLOR, not the word!',
              textAlign: TextAlign.center,
              style: TextStyle(color: secondaryTextColor, fontSize: 16),
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFFF8A00).withOpacity(0.3),
                ),
              ),
              child: Column(
                children: [
                  const Text(
                    'How to Play',
                    style: TextStyle(
                      color: Color(0xFFFF8A00),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '• Read the word, but ignore it\n'
                    '• Tap button matching TEXT COLOR\n'
                    '• Faster answers = bonus points\n'
                    '• Time decreases each round\n'
                    '• One mistake = game over',
                    style: TextStyle(
                      color: secondaryTextColor,
                      fontSize: 14,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 16),
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 14),
                      children: [
                        TextSpan(
                          text: 'Example: ',
                          style: TextStyle(color: secondaryTextColor),
                        ),
                        TextSpan(
                          text: 'BLUE',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                        TextSpan(
                          text: ' → Tap RED',
                          style: TextStyle(color: secondaryTextColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => provider.startGame(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF8A00),
                padding: const EdgeInsets.symmetric(
                  horizontal: 48,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Start Challenge',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (provider.highScore > 0)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFFF8A00).withOpacity(0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      'High Score',
                      style: TextStyle(color: secondaryTextColor, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${provider.highScore}',
                      style: const TextStyle(
                        color: Color(0xFFFF8A00),
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameScreen(
    BuildContext context,
    ColorWordClashProvider provider,
  ) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDarkTheme
        ? const Color(0xFF2A2A2A)
        : Colors.grey.shade100;

    return Column(
      children: [
        // Round and Timer
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFFF8A00).withOpacity(0.3),
                  ),
                ),
                child: Text(
                  'Round ${provider.round}',
                  style: const TextStyle(
                    color: Color(0xFFFF8A00),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: provider.timeLeft < 0.5
                      ? Colors.red.withOpacity(0.2)
                      : cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: provider.timeLeft < 0.5
                        ? Colors.red
                        : Colors.blueAccent.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.timer,
                      color: provider.timeLeft < 0.5
                          ? Colors.red
                          : Colors.blueAccent,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${provider.timeLeft.toStringAsFixed(1)}s',
                      style: TextStyle(
                        color: provider.timeLeft < 0.5
                            ? Colors.red
                            : Colors.blueAccent,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Progress bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: provider.timeLeft / provider.timeLimit,
              backgroundColor: cardColor,
              color: provider.timeLeft < 0.5 ? Colors.red : Colors.blueAccent,
              minHeight: 8,
            ),
          ),
        ),

        const Spacer(),

        // Word display
        AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: provider.lastAnswerCorrect == null ? 1.0 : 0.5,
          child: Container(
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: provider.lastAnswerCorrect == null
                    ? const Color(0xFFFF8A00).withOpacity(0.3)
                    : provider.lastAnswerCorrect!
                    ? Colors.green
                    : Colors.red,
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color:
                      (provider.lastAnswerCorrect == null
                              ? const Color(0xFFFF8A00)
                              : provider.lastAnswerCorrect!
                              ? Colors.green
                              : Colors.red)
                          .withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                provider.currentWord,
                style: TextStyle(
                  color: provider.currentColor,
                  fontSize: 56,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                ),
              ),
            ),
          ),
        ),

        const Spacer(),

        // Color buttons
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _ColorButton(
                      color: provider.colors[0].color,
                      label: provider.colors[0].name,
                      onTap: () => provider.onColorTap(0),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ColorButton(
                      color: provider.colors[1].color,
                      label: provider.colors[1].name,
                      onTap: () => provider.onColorTap(1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _ColorButton(
                      color: provider.colors[2].color,
                      label: provider.colors[2].name,
                      onTap: () => provider.onColorTap(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ColorButton(
                      color: provider.colors[3].color,
                      label: provider.colors[3].name,
                      onTap: () => provider.onColorTap(3),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGameOverScreen(
    BuildContext context,
    ColorWordClashProvider provider,
  ) {
    final theme = Theme.of(context);
    final isDarkTheme = theme.brightness == Brightness.dark;
    final textColor = isDarkTheme ? Colors.white : Colors.black87;
    final secondaryTextColor = isDarkTheme ? Colors.white70 : Colors.black54;
    final cardColor = isDarkTheme ? const Color(0xFF2A2A2A) : Colors.white;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('💥', style: TextStyle(fontSize: 80)),
            const SizedBox(height: 24),
            Text(
              'Game Over',
              style: TextStyle(
                color: textColor,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFFF8A00).withOpacity(0.3),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          Text(
                            'Score',
                            style: TextStyle(
                              color: secondaryTextColor,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${provider.score}',
                            style: const TextStyle(
                              color: Color(0xFFFF8A00),
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        children: [
                          Text(
                            'Rounds',
                            style: TextStyle(
                              color: secondaryTextColor,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${provider.round}',
                            style: const TextStyle(
                              color: Colors.blueAccent,
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (provider.score == provider.highScore &&
                      provider.score > 0) ...[
                    const SizedBox(height: 16),
                    const Text(
                      '🏆 New High Score! 🏆',
                      style: TextStyle(
                        color: Colors.amber,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () => provider.startGame(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8A00),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Play Again',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                OutlinedButton(
                  onPressed: () {
                    provider.exitGame();
                    Navigator.pop(context);
                  },
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: secondaryTextColor),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Exit',
                    style: TextStyle(color: textColor, fontSize: 16),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorButton extends StatelessWidget {
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _ColorButton({
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 4,
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(color: Colors.black45, offset: Offset(1, 1), blurRadius: 2),
          ],
        ),
      ),
    );
  }
}
