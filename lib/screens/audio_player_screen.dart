import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// In-app audio player screen
/// Displays audio with play/pause controls, progress bar, and duration
class AudioPlayerScreen extends StatefulWidget {
  final String audioUrl;
  final String fileName;

  const AudioPlayerScreen({
    super.key,
    required this.audioUrl,
    required this.fileName,
  });

  @override
  State<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends State<AudioPlayerScreen> {
  late AudioPlayer _audioPlayer;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeAudio();
  }

  Future<void> _initializeAudio() async {
    _audioPlayer = AudioPlayer();
    try {

      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      // Check if it's a local file or remote URL
      if (widget.audioUrl.startsWith('http://') ||
          widget.audioUrl.startsWith('https://')) {
        // Remote URL - use setUrl
        await _audioPlayer.setUrl(widget.audioUrl);
      } else {
        // Local file path
        final originalFile = File(widget.audioUrl);

        if (!originalFile.existsSync()) {
          throw Exception('Audio file not found: ${widget.audioUrl}');
        }


        // Check if file is still being written to (size changes indicate active writing)
        final initialSize = originalFile.lengthSync();
        await Future.delayed(const Duration(milliseconds: 200));
        final finalSize = originalFile.lengthSync();

        if (initialSize != finalSize) {
          throw Exception(
            'Audio file is still being processed. Please wait a moment and try again.',
          );
        }


        // If file is in cache directory, copy it to a stable location
        if (widget.audioUrl.contains('/cache/')) {

          final appDir = await getApplicationDocumentsDirectory();
          final fileName = widget.audioUrl.split('/').last;
          final stableFile = File('${appDir.path}/$fileName');

          await originalFile.copy(stableFile.path);

          // Verify the copied file
          final copiedFileExists = await stableFile.exists();
          final copiedFileSize = copiedFileExists
              ? await stableFile.length()
              : 0;

          if (!copiedFileExists) {
            throw Exception('Copied file does not exist: ${stableFile.path}');
          }

          if (copiedFileSize == 0) {
            throw Exception('Copied file is empty: ${stableFile.path}');
          }

          // Small delay to ensure file system sync
          await Future.delayed(const Duration(milliseconds: 100));

          await _audioPlayer.setFilePath(stableFile.path);
        } else {
          await _audioPlayer.setFilePath(widget.audioUrl);
        }
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load audio: $e';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));

    if (duration.inHours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141414),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Now Playing',
              style: TextStyle(fontSize: 14, color: Colors.white60),
            ),
            Text(
              widget.fileName,
              style: const TextStyle(fontSize: 16, color: Colors.white),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFA929)),
              ),
            )
          : _errorMessage != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.white54,
                    size: 64,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _isLoading = true;
                      });
                      _initializeAudio();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFA929),
                      foregroundColor: Colors.black,
                    ),
                  ),
                ],
              ),
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Album art / Icon
                Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF42A5F5), Color(0xFF1976D2)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.audio_file,
                    size: 80,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 40),

                // File name
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    widget.fileName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 40),

                // Progress bar with time
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      StreamBuilder<Duration>(
                        stream: _audioPlayer.positionStream,
                        builder: (context, snapshot) {
                          final position = snapshot.data ?? Duration.zero;
                          return StreamBuilder<Duration?>(
                            stream: _audioPlayer.durationStream,
                            builder: (context, durationSnapshot) {
                              final duration =
                                  durationSnapshot.data ?? Duration.zero;
                              final progress = duration.inMilliseconds > 0
                                  ? position.inMilliseconds /
                                        duration.inMilliseconds
                                  : 0.0;

                              return Column(
                                children: [
                                  SliderTheme(
                                    data: SliderThemeData(
                                      trackHeight: 4,
                                      thumbShape: const RoundSliderThumbShape(
                                        elevation: 0,
                                        enabledThumbRadius: 8,
                                      ),
                                      activeTrackColor: const Color(0xFFFFA929),
                                      inactiveTrackColor: Colors.white24,
                                      thumbColor: const Color(0xFFFFA929),
                                    ),
                                    child: Slider(
                                      value: progress.clamp(0.0, 1.0),
                                      onChanged: (value) {
                                        final newPosition = Duration(
                                          milliseconds:
                                              (duration.inMilliseconds * value)
                                                  .toInt(),
                                        );
                                        _audioPlayer.seek(newPosition);
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _formatDuration(position),
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                      Text(
                                        _formatDuration(duration),
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),

                // Play/Pause button
                StreamBuilder<PlayerState>(
                  stream: _audioPlayer.playerStateStream,
                  builder: (context, snapshot) {
                    final playerState = snapshot.data;
                    final isPlaying = playerState?.playing ?? false;

                    return GestureDetector(
                      onTap: () {
                        if (isPlaying) {
                          _audioPlayer.pause();
                        } else {
                          _audioPlayer.play();
                        }
                      },
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF8800), Color(0xFFFF9E2A)],
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 60),
              ],
            ),
    );
  }
}
