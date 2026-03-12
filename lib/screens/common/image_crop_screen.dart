import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';

/// Pure-Flutter square image cropper — no native plugins required.
///
/// Usage:
///   final File? cropped = await ImageCropScreen.push(context, pickedFile);
///   if (cropped != null) { /* upload cropped */ }
class ImageCropScreen extends StatefulWidget {
  final File imageFile;

  const ImageCropScreen({super.key, required this.imageFile});

  /// Push this screen and return the cropped [File], or null if cancelled.
  static Future<File?> push(BuildContext context, File imageFile) {
    return Navigator.of(context).push<File?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ImageCropScreen(imageFile: imageFile),
      ),
    );
  }

  @override
  State<ImageCropScreen> createState() => _ImageCropScreenState();
}

class _ImageCropScreenState extends State<ImageCropScreen> {
  // The GlobalKey on the RepaintBoundary that wraps exactly the crop square
  final GlobalKey _cropKey = GlobalKey();

  // Transformation state
  double _scale = 1.0;
  double _prevScale = 1.0;
  Offset _offset = Offset.zero;
  Offset _prevOffset = Offset.zero;
  Offset _focalPointStart = Offset.zero;

  bool _isCropping = false;

  static const double _cropSize = 300.0; // logical pixels of the square

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111111) : Colors.black;
    const primary = Color(0xFFF2800D);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Move and Scale', style: TextStyle(fontSize: 16)),
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text(
            'Cancel',
            style: TextStyle(color: Colors.white70, fontSize: 15),
          ),
        ),
        leadingWidth: 80,
        actions: [
          _isCropping
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: primary,
                      strokeWidth: 2,
                    ),
                  ),
                )
              : TextButton(
                  onPressed: _crop,
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      color: primary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: Center(child: _buildCropArea())),
          _buildHint(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildCropArea() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // ── Capture boundary (only the square) ──────────────────────────────
        RepaintBoundary(
          key: _cropKey,
          child: ClipRect(
            child: SizedBox(
              width: _cropSize,
              height: _cropSize,
              child: GestureDetector(
                onScaleStart: (d) {
                  _prevScale = _scale;
                  _prevOffset = _offset;
                  _focalPointStart = d.localFocalPoint;
                },
                onScaleUpdate: (d) {
                  setState(() {
                    _scale = (_prevScale * d.scale).clamp(0.5, 8.0);
                    // Pan: move offset proportional to focal point delta
                    final delta = d.localFocalPoint - _focalPointStart;
                    _offset = _prevOffset + delta;
                  });
                },
                child: Transform(
                  transform: Matrix4.identity()
                    ..translate(
                      _cropSize / 2 + _offset.dx,
                      _cropSize / 2 + _offset.dy,
                    )
                    ..scale(_scale)
                    ..translate(-_cropSize / 2, -_cropSize / 2),
                  child: Image.file(
                    widget.imageFile,
                    width: _cropSize,
                    height: _cropSize,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
          ),
        ),

        // ── Circular overlay mask ────────────────────────────────────────────
        IgnorePointer(
          child: CustomPaint(
            size: const Size(_cropSize, _cropSize),
            painter: _CircleOverlayPainter(),
          ),
        ),
      ],
    );
  }

  Widget _buildHint() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Text(
        'Pinch to zoom · Drag to reposition',
        style: TextStyle(color: Colors.white54, fontSize: 13),
      ),
    );
  }

  Future<void> _crop() async {
    if (_isCropping) return;
    setState(() => _isCropping = true);

    try {
      // Render the RepaintBoundary at 3× pixel density for crisp output
      final boundary =
          _cropKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      image.dispose();

      if (byteData == null) {
        _showError('Could not process image. Please try again.');
        return;
      }

      // Write to temp file
      final tempDir = await getTemporaryDirectory();
      final outFile = File(
        '${tempDir.path}/cropped_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await outFile.writeAsBytes(byteData.buffer.asUint8List());

      if (mounted) Navigator.of(context).pop(outFile);
    } catch (e) {
      _showError('Crop failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isCropping = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }
}

/// Draws a semi-transparent overlay with a circular hole in the centre,
/// plus a circular border — giving the WhatsApp-style crop ring.
class _CircleOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 2;

    // Darken everything outside the circle
    final outerPath = Path()..addRect(rect);
    final circlePath = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    final maskPath = Path.combine(
      PathOperation.difference,
      outerPath,
      circlePath,
    );
    canvas.drawPath(maskPath, Paint()..color = Colors.black.withOpacity(0.55));

    // Bright ring border
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}
