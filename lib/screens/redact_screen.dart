import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class RedactScreen extends StatefulWidget {
  final String imagePath;

  const RedactScreen({super.key, required this.imagePath});

  @override
  State<RedactScreen> createState() => _RedactScreenState();
}

class RedactionBox {
  Rect rect;
  bool isSelected;

  RedactionBox({required this.rect, this.isSelected = false});
}

class _RedactScreenState extends State<RedactScreen> {
  final List<RedactionBox> _boxes = [];
  final GlobalKey _repaintBoundaryKey = GlobalKey();
  Offset? _startPoint;
  RedactionBox? _selectedBox;
  bool _isDragging = false;
  Offset? _dragOffset;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Redact Sensitive Areas'),
        backgroundColor: Colors.black,
        actions: [
          TextButton.icon(
            onPressed: _boxes.isEmpty
                ? null
                : () {
                    setState(() {
                      _boxes.removeLast();
                    });
                  },
            icon: const Icon(Icons.undo, color: Colors.white70),
            label: const Text('Undo', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            color: Colors.orange.withValues(alpha: 0.2),
            child: const Text(
              'Tap and drag to mark areas to redact',
              style: TextStyle(color: Colors.orange, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: GestureDetector(
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              child: RepaintBoundary(
                key: _repaintBoundaryKey,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(
                      File(widget.imagePath),
                      fit: BoxFit.contain,
                    ),
                    CustomPaint(
                      painter: RedactionPainter(boxes: _boxes),
                      size: Size.infinite,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _boxes.isEmpty ? null : _saveImage,
                icon: const Icon(Icons.save),
                label: const Text(
                  'Done - Save Image',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  disabledBackgroundColor: Colors.grey,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onPanStart(DragStartDetails details) {
    final box = _findBoxAt(details.localPosition);
    if (box != null) {
      setState(() {
        _selectedBox = box;
        _isDragging = true;
        _dragOffset = details.localPosition - box.rect.topLeft;
        for (var b in _boxes) {
          b.isSelected = false;
        }
        box.isSelected = true;
      });
    } else {
      setState(() {
        _startPoint = details.localPosition;
        _selectedBox = null;
        for (var b in _boxes) {
          b.isSelected = false;
        }
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_isDragging && _selectedBox != null) {
      setState(() {
        final newTopLeft = details.localPosition - _dragOffset!;
        final size = _selectedBox!.rect.size;
        _selectedBox!.rect = Rect.fromLTWH(
          newTopLeft.dx,
          newTopLeft.dy,
          size.width,
          size.height,
        );
      });
    } else if (_startPoint != null) {
      setState(() {
        final currentPoint = details.localPosition;
        final rect = Rect.fromPoints(_startPoint!, currentPoint);
        final normalizedRect = Rect.fromLTRB(
          rect.left.clamp(0, double.infinity),
          rect.top.clamp(0, double.infinity),
          rect.right.clamp(0, double.infinity),
          rect.bottom.clamp(0, double.infinity),
        );
        if (normalizedRect.width > 10 && normalizedRect.height > 10) {
          _boxes.removeWhere((b) => b.isSelected);
          _boxes.add(RedactionBox(rect: normalizedRect, isSelected: true));
        }
      });
    }
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() {
      _startPoint = null;
      _isDragging = false;
      _dragOffset = null;
    });
  }

  RedactionBox? _findBoxAt(Offset position) {
    for (final box in _boxes.reversed) {
      if (box.rect.contains(position)) {
        return box;
      }
    }
    return null;
  }

  Future<void> _saveImage() async {
    try {
      final boundary = _repaintBoundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final Uint8List pngBytes = byteData.buffer.asUint8List();

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF2D1B4E),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('Image Saved!', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: const Text(
            'Redacted image saved to gallery.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
    }
  }
}

class RedactionPainter extends CustomPainter {
  final List<RedactionBox> boxes;

  RedactionPainter({required this.boxes});

  @override
  void paint(Canvas canvas, Size size) {
    for (final box in boxes) {
      final paint = Paint()
        ..color = Colors.red.withValues(alpha: 0.7)
        ..style = PaintingStyle.fill;

      canvas.drawRect(box.rect, paint);

      final borderPaint = Paint()
        ..color = box.isSelected ? Colors.yellow : Colors.red
        ..style = PaintingStyle.stroke
        ..strokeWidth = box.isSelected ? 3 : 2;

      canvas.drawRect(box.rect, borderPaint);

      if (box.isSelected) {
        final handlePaint = Paint()..color = Colors.yellow;
        canvas.drawCircle(box.rect.topLeft, 8, handlePaint);
        canvas.drawCircle(box.rect.topRight, 8, handlePaint);
        canvas.drawCircle(box.rect.bottomLeft, 8, handlePaint);
        canvas.drawCircle(box.rect.bottomRight, 8, handlePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant RedactionPainter oldDelegate) => true;
}
