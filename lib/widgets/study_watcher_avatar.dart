import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:typed_data';

class StudyWatcherAvatar extends StatefulWidget {
  final double size;
  final String assetPath;

  const StudyWatcherAvatar({
    super.key,
    this.size = 80,
    this.assetPath = 'assets/animations/test/strict_mother.gif',
  });

  @override
  State<StudyWatcherAvatar> createState() => _StudyWatcherAvatarState();
}

class _StudyWatcherAvatarState extends State<StudyWatcherAvatar> {
  late final Future<Uint8List?> _avatarBytesFuture;

  static const List<String> _candidateAssets = [
    'assets/animations/test/strict_mother.gif',
    'assets/strict_mother.gif',
  ];

  @override
  void initState() {
    super.initState();
    _avatarBytesFuture = _loadAvatarBytes();
  }

  Future<Uint8List?> _loadAvatarBytes() async {
    final candidates = <String>{widget.assetPath, ..._candidateAssets};
    for (final path in candidates) {
      try {
        final data = await rootBundle.load(path);
        return data.buffer.asUint8List();
      } catch (_) {
        // Try the next candidate.
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Tooltip(
        message: 'Study watcher is keeping an eye on your focus',
        child: FutureBuilder<Uint8List?>(
          future: _avatarBytesFuture,
          builder: (context, snapshot) {
            final hasImage = snapshot.hasData && snapshot.data != null;

            return Container(
              width: widget.size,
              height: widget.size,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFF2800D).withOpacity(0.85),
                  width: 1.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFF2800D).withOpacity(0.22),
                    blurRadius: 10,
                    spreadRadius: 0.4,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipOval(
                child: hasImage
                    ? Image.memory(
                        snapshot.data!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      )
                    : Container(
                        color: const Color(0xFFFFF3E8),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.visibility,
                          size: widget.size * 0.45,
                          color: const Color(0xFFF2800D),
                        ),
                      ),
              ),
            );
          },
        ),
      ),
    );
  }
}
