import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/nback_provider.dart';

class NBackChallengeScreen extends StatelessWidget {
  const NBackChallengeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => NBackProvider(),
      child: const _NBackChallengeContent(),
    );
  }
}

class _NBackChallengeContent extends StatelessWidget {
  const _NBackChallengeContent();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NBackProvider>();
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDarkTheme ? const Color(0xFF1A1A1A) : Colors.white;
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
          '🧠 N-Back Challenge',
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
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: !provider.isPlaying && provider.round == 0
          ? _buildStartScreen(context, provider)
          : !provider.isPlaying && provider.round > 0
          ? _buildLevelCompleteScreen(context, provider)
          : _buildGameScreen(context, provider),
    );
  }

  Widget _buildStartScreen(BuildContext context, NBackProvider provider) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkTheme ? Colors.white : Colors.black87;
    final secondaryTextColor = isDarkTheme ? Colors.white70 : Colors.black54;
    final cardColor = isDarkTheme ? const Color(0xFF2A2A2A) : Colors.grey.shade100;
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🧠', style: TextStyle(fontSize: 80)),
            const SizedBox(height: 24),
            Text(
              'N-Back Challenge',
              style: TextStyle(
                color: textColor,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Match symbols that appeared N steps ago!',
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
                    '• Watch symbols appear every 1.5s\n'
                    '• Tap MATCH if current = N steps ago\n'
                    '• Tap SKIP if different\n'
                    '• Reach 80% accuracy to level up\n'
                    '• Below 50% decreases N',
                    style: TextStyle(
                      color: secondaryTextColor,
                      fontSize: 14,
                      height: 1.6,
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
                'Start Game',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (provider.maxNReached > 1)
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
                      'Max N Reached',
                      style: TextStyle(color: secondaryTextColor, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${provider.maxNReached}-Back',
                      style: const TextStyle(
                        color: Color(0xFFFF8A00),
                        fontSize: 28,
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

  Widget _buildGameScreen(BuildContext context, NBackProvider provider) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkTheme ? Colors.white : Colors.black87;
    final cardColor = isDarkTheme ? const Color(0xFF2A2A2A) : Colors.grey.shade100;
    
    return Column(
      children: [
        // Level and Progress
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
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
                    child: Row(
                      children: [
                        const Icon(
                          Icons.layers,
                          color: Color(0xFFFF8A00),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${provider.currentN}-Back',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.blueAccent.withOpacity(0.3),
                      ),
                    ),
                    child: Text(
                      '${provider.round} / ${provider.roundsInLevel}',
                      style: const TextStyle(
                        color: Colors.blueAccent,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: provider.round / provider.roundsInLevel,
                  backgroundColor: cardColor,
                  color: const Color(0xFFFF8A00),
                  minHeight: 8,
                ),
              ),
            ],
          ),
        ),

        const Spacer(),

        // Symbol Card
        Center(
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: provider.lastAnswerCorrect == null
                    ? const Color(0xFFFF8A00).withOpacity(0.5)
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
            child: Center(
              child: Text(
                provider.currentSymbol,
                style: const TextStyle(
                  fontSize: 80,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Accuracy
        Text(
          'Accuracy: ${provider.accuracy.toStringAsFixed(0)}%',
          style: TextStyle(
            color: provider.accuracy >= 80
                ? Colors.green
                : provider.accuracy >= 50
                ? Colors.orange
                : Colors.red,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),

        const Spacer(),

        // Buttons
        Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: provider.canAnswer
                      ? () => provider.onSkipPressed()
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cardColor,
                    disabledBackgroundColor: isDarkTheme ? const Color(0xFF1A1A1A) : Colors.grey.shade200,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: provider.canAnswer
                            ? Colors.grey
                            : Colors.grey.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    'SKIP',
                    style: TextStyle(
                      color: provider.canAnswer ? textColor : (isDarkTheme ? Colors.white38 : Colors.black38),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: provider.canAnswer
                      ? () => provider.onMatchPressed()
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8A00),
                    disabledBackgroundColor: const Color(
                      0xFFFF8A00,
                    ).withOpacity(0.3),
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'MATCH',
                    style: TextStyle(
                      color: provider.canAnswer ? Colors.white : Colors.white38,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLevelCompleteScreen(
    BuildContext context,
    NBackProvider provider,
  ) {
    final acc = provider.accuracy;
    final levelUp = acc >= 80 && provider.currentN < 8;
    final levelDown = acc < 50 && provider.currentN > 1;
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkTheme ? Colors.white : Colors.black87;
    final secondaryTextColor = isDarkTheme ? Colors.white70 : Colors.black54;
    final cardColor = isDarkTheme ? const Color(0xFF2A2A2A) : Colors.grey.shade100;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              levelUp
                  ? '🎉'
                  : levelDown
                  ? '📉'
                  : '✅',
              style: const TextStyle(fontSize: 80),
            ),
            const SizedBox(height: 24),
            Text(
              levelUp
                  ? 'Level Up!'
                  : levelDown
                  ? 'Level Down'
                  : 'Level Complete',
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
                            'Accuracy',
                            style: TextStyle(
                              color: secondaryTextColor,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${acc.toStringAsFixed(0)}%',
                            style: TextStyle(
                              color: acc >= 80
                                  ? Colors.green
                                  : acc >= 50
                                  ? Colors.orange
                                  : Colors.red,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
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
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (levelUp)
                    Text(
                      'Next: ${provider.currentN}-Back',
                      style: const TextStyle(
                        color: Colors.green,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  if (levelDown)
                    Text(
                      'Next: ${provider.currentN}-Back',
                      style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () => provider.nextLevel(),
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
                    'Continue',
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
                    provider.endGame();
                    Navigator.pop(context);
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white54),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Exit',
                    style: TextStyle(color: Colors.white, fontSize: 16),
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
