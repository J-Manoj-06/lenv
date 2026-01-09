import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/path_echo_provider.dart';
import '../../widgets/maze_cell.dart';

class PathEchoScreen extends StatelessWidget {
  const PathEchoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PathEchoProvider(),
      child: const _PathEchoContent(),
    );
  }
}

class _PathEchoContent extends StatelessWidget {
  const _PathEchoContent();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PathEchoProvider>();
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDarkTheme ? const Color(0xFF1A1A1A) : Colors.white;
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
          '🧩 Path Echo',
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
                    'Level ${provider.currentLevel}',
                    style: const TextStyle(
                      color: Color(0xFFFF8A00),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Best: ${provider.highestLevel}',
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
          : provider.gameState == GameState.failed
          ? _buildFailedScreen(context, provider)
          : _buildGameScreen(context, provider),
    );
  }

  Widget _buildStartScreen(BuildContext context, PathEchoProvider provider) {
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
            const Text('🧩', style: TextStyle(fontSize: 80)),
            const SizedBox(height: 24),
            Text(
              'Path Echo',
              style: TextStyle(
                color: textColor,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Memorize the path, then trace it!',
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
                    '• Watch the path light up\n'
                    '• Memorize the sequence\n'
                    '• Tap cells in same order\n'
                    '• Longer paths each level\n'
                    '• Faster animations too!',
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
            if (provider.highestLevel > 1)
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
                      'Highest Level',
                      style: TextStyle(color: secondaryTextColor, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${provider.highestLevel}',
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

  Widget _buildGameScreen(BuildContext context, PathEchoProvider provider) {
    final size = provider.gridSize;
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkTheme ? Colors.white : Colors.black87;
    final secondaryTextColor = isDarkTheme ? Colors.white70 : Colors.black54;
    final cardColor = isDarkTheme ? const Color(0xFF2A2A2A) : Colors.grey.shade100;
    final dividerColor = secondaryTextColor.withOpacity(0.3);

    return Column(
      children: [
        // Status indicator
        Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: provider.gameState == GameState.showing
                  ? Colors.blue.withOpacity(0.2)
                  : provider.gameState == GameState.levelComplete
                  ? Colors.green.withOpacity(0.2)
                  : cardColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: provider.gameState == GameState.showing
                    ? Colors.blueAccent
                    : provider.gameState == GameState.levelComplete
                    ? Colors.green
                    : const Color(0xFFFF8A00).withOpacity(0.3),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  provider.gameState == GameState.showing
                      ? Icons.remove_red_eye
                      : provider.gameState == GameState.levelComplete
                      ? Icons.check_circle
                      : Icons.touch_app,
                  color: provider.gameState == GameState.showing
                      ? Colors.blueAccent
                      : provider.gameState == GameState.levelComplete
                      ? Colors.green
                      : const Color(0xFFFF8A00),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  provider.gameState == GameState.showing
                      ? 'Watch the path...'
                      : provider.gameState == GameState.levelComplete
                      ? 'Perfect! Next level 🎉'
                      : 'Trace the path!',
                  style: TextStyle(
                    color: provider.gameState == GameState.showing
                        ? Colors.blueAccent
                        : provider.gameState == GameState.levelComplete
                        ? Colors.green
                        : textColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Progress
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Progress: ${provider.userPath.length}/${provider.path.length}',
                style: TextStyle(color: secondaryTextColor, fontSize: 14),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Maze Grid
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: size,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: size * size,
                  itemBuilder: (context, index) {
                    final x = index % size;
                    final y = index ~/ size;
                    final point = Point(x, y);

                    final isHighlighted = provider.currentHighlight == point;
                    final isUserPath = provider.visitedCells.contains(point);
                    final isCorrect = provider.userPath.contains(point);

                    return MazeCell(
                      isPath: provider.path.contains(point),
                      isHighlighted: isHighlighted,
                      isUserPath: isUserPath,
                      isCorrect: isCorrect,
                      onTap: () => provider.onCellTap(x, y),
                    );
                  },
                ),
              ),
            ),
          ),
        ),

        // Info panel
        Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFFF8A00).withOpacity(0.3),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    Text(
                      'Grid',
                      style: TextStyle(color: secondaryTextColor, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$size×$size',
                      style: const TextStyle(
                        color: Color(0xFFFF8A00),
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Container(width: 1, height: 40, color: dividerColor),
                Column(
                  children: [
                    Text(
                      'Path Length',
                      style: TextStyle(color: secondaryTextColor, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${provider.path.length}',
                      style: const TextStyle(
                        color: Colors.blueAccent,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFailedScreen(BuildContext context, PathEchoProvider provider) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkTheme ? Colors.white : Colors.black87;
    final secondaryTextColor = isDarkTheme ? Colors.white70 : Colors.black54;
    final cardColor = isDarkTheme ? const Color(0xFF2A2A2A) : Colors.white;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('❌', style: TextStyle(fontSize: 80)),
            const SizedBox(height: 24),
            Text(
              'Wrong Path!',
              style: TextStyle(
                color: textColor,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
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
                  Text(
                    'Level Reached',
                    style: TextStyle(color: secondaryTextColor, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${provider.currentLevel}',
                    style: const TextStyle(
                      color: Color(0xFFFF8A00),
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (provider.currentLevel == provider.highestLevel &&
                      provider.currentLevel > 1) ...[
                    const SizedBox(height: 8),
                    const Text(
                      '🏆 New Record! 🏆',
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
                  onPressed: () => provider.retryLevel(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Retry Level',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () => provider.startGame(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8A00),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'New Game',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
      ),
    );
  }
}
