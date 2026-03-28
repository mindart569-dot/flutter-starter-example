import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class RedactScreen extends StatefulWidget {
  final String imagePath;
  final List<Map<String, dynamic>> detectedRegions;
  final bool autoRedact;
  final bool autoShare;

  const RedactScreen({
    super.key,
    required this.imagePath,
    this.detectedRegions = const [],
    this.autoRedact = false,
    this.autoShare = false,
  });

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
  Offset? _startPoint;
  RedactionBox? _selectedBox;
  bool _isDragging = false;
  bool _isProcessing = false;
  Offset? _dragOffset;
  Size? _imageSize;
  bool _hasAppliedAutoRedact = false;

  @override
  void initState() {
    super.initState();
    _loadImageSize();
    // Pre-populate detected regions after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.autoRedact && !_hasAppliedAutoRedact) {
        _applyAutoRedact();
      }
    });
  }

  Future<void> _loadImageSize() async {
    final imageFile = File(widget.imagePath);
    final bytes = await imageFile.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    setState(() {
      _imageSize = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
    });
  }

  void _applyAutoRedact() {
    if (widget.detectedRegions.isEmpty || _imageSize == null) {
      // Retry after getting image size
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_imageSize != null && !_hasAppliedAutoRedact) {
          _applyAutoRedact();
        }
      });
      return;
    }

    setState(() {
      _hasAppliedAutoRedact = true;

      // Convert detected regions to redaction boxes
      for (var region in widget.detectedRegions) {
        final bbox = region['boundingBox'] as Map<String, dynamic>;
        final rect = Rect.fromLTWH(
          bbox['left'] as double,
          bbox['top'] as double,
          bbox['width'] as double,
          bbox['height'] as double,
        );

        // Add padding around detected region for better coverage
        final paddedRect = Rect.fromLTRB(
          (rect.left - 10).clamp(0.0, _imageSize!.width),
          (rect.top - 10).clamp(0.0, _imageSize!.height),
          (rect.right + 10).clamp(0.0, _imageSize!.width),
          (rect.bottom + 10).clamp(0.0, _imageSize!.height),
        );

        _boxes.add(RedactionBox(rect: paddedRect, isSelected: false));
      }
    });

    // If auto-share is enabled, trigger save and share after a brief delay
    if (widget.autoShare && _boxes.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _saveAndShare();
        }
      });
    }
  }

  Future<void> _saveAndShare() async {
    setState(() => _isProcessing = true);

    try {
      // BULLETPROOF: Get all regions that need to be redacted
      List<Rect> rectsToRedact = [];

      // First, use manually created boxes if they exist
      if (_boxes.isNotEmpty) {
        rectsToRedact = _boxes.map((box) => box.rect).toList();
        print(
            '[RedactScreen] Using ${_boxes.length} manually created redaction boxes');
      }

      // CRITICAL: If no manual boxes but we have detected regions, use those!
      if (rectsToRedact.isEmpty && widget.detectedRegions.isNotEmpty) {
        print(
            '[RedactScreen] No manual boxes - auto-generating from ${widget.detectedRegions.length} detected regions');

        // Load image size if not already loaded
        if (_imageSize == null) {
          final imageFile = File(widget.imagePath);
          final bytes = await imageFile.readAsBytes();
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          _imageSize = Size(
            frame.image.width.toDouble(),
            frame.image.height.toDouble(),
          );
        }

        // Convert ALL detected regions to rectangles with padding
        for (var region in widget.detectedRegions) {
          final bbox = region['boundingBox'] as Map<String, dynamic>;
          final rect = Rect.fromLTWH(
            bbox['left'] as double,
            bbox['top'] as double,
            bbox['width'] as double,
            bbox['height'] as double,
          );

          // Add generous padding for complete coverage
          final paddedRect = Rect.fromLTRB(
            (rect.left - 15).clamp(0.0, _imageSize!.width),
            (rect.top - 15).clamp(0.0, _imageSize!.height),
            (rect.right + 15).clamp(0.0, _imageSize!.width),
            (rect.bottom + 15).clamp(0.0, _imageSize!.height),
          );

          rectsToRedact.add(paddedRect);
          print(
              '[RedactScreen] Auto-redacting ${region['type']}: ${region['value']}');
        }
      }

      // FAIL-SAFE: If still no rectangles and we have detected regions, BLOCK sharing
      if (rectsToRedact.isEmpty && widget.detectedRegions.isNotEmpty) {
        throw Exception('Cannot create redaction boxes from detected regions');
      }

      // If no sensitive data at all, allow sharing original (this should never happen in normal flow)
      if (rectsToRedact.isEmpty && widget.detectedRegions.isEmpty) {
        print(
            '[RedactScreen] WARNING: No sensitive data detected, sharing original image');
      }

      print(
          '[RedactScreen] Drawing ${rectsToRedact.length} BLACK rectangles on image');

      // Step 1: Load original image using dart:ui
      final imageFile = File(widget.imagePath);
      final bytes = await imageFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final originalImage = frame.image;

      print(
          '[RedactScreen] Original image size: ${originalImage.width}x${originalImage.height}');

      // Step 2: Create canvas to draw on
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Step 3: Draw original image first
      canvas.drawImage(originalImage, Offset.zero, Paint());
      print('[RedactScreen] Drew original image on canvas');

      // Step 4: Draw SOLID BLACK rectangles over ALL sensitive regions
      final blackPaint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.fill;

      for (int i = 0; i < rectsToRedact.length; i++) {
        final rect = rectsToRedact[i];
        canvas.drawRect(rect, blackPaint);
        print(
            '[RedactScreen] Drew black box $i: ${rect.left},${rect.top} ${rect.width}x${rect.height}');
      }

      // Step 5: Convert canvas to image
      final picture = recorder.endRecording();
      final redactedImage = await picture.toImage(
        originalImage.width,
        originalImage.height,
      );
      print('[RedactScreen] Created redacted image');

      // Step 6: Encode as PNG
      final pngBytes = await redactedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (pngBytes == null) {
        throw Exception('Failed to encode redacted image as PNG');
      }

      print('[RedactScreen] Encoded PNG: ${pngBytes.lengthInBytes} bytes');

      // Step 7: Save to temporary file
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempFile =
          File('${tempDir.path}/safeshare_redacted_$timestamp.png');
      await tempFile.writeAsBytes(pngBytes.buffer.asUint8List());

      print('[RedactScreen] Saved redacted image to: ${tempFile.path}');
      print('[RedactScreen] File size: ${await tempFile.length()} bytes');

      if (!mounted) return;

      // Step 8: Share the REDACTED version (NEVER the original)
      await Share.shareXFiles(
        [XFile(tempFile.path)],
        text: 'Shared safely via SafeShare 🛡️',
      );

      print('[RedactScreen] Share dialog opened');

      // Clean up temp file after a delay (give time for share to complete)
      Future.delayed(const Duration(seconds: 5), () async {
        try {
          await tempFile.delete();
        } catch (e) {
          print('[RedactScreen] Could not delete temp file: $e');
        }
      });

      if (!mounted) return;

      // Show success dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF2D1B4E),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('Done!', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: Text(
            rectsToRedact.isEmpty
                ? '✅ Image shared successfully!'
                : '✅ Image shared successfully with ${rectsToRedact.length} sensitive area(s) redacted!\n\nAll sensitive data has been covered with solid black boxes.',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                Navigator.pop(context); // Close redact screen
                Navigator.pop(context); // Close result screen
              },
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e, stackTrace) {
      // FAIL-SAFE: On any error, block sharing completely
      print('[RedactScreen] ERROR in _saveAndShare: $e');
      print('[RedactScreen] Stack trace: $stackTrace');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '⚠️ Unable to secure image. Sharing blocked for your safety.\n\nError: $e',
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Redact Sensitive Areas'),
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton.icon(
            onPressed: _boxes.isEmpty
                ? null
                : () {
                    setState(() {
                      if (_boxes.isNotEmpty) {
                        _boxes.removeLast();
                      }
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
            color: widget.autoRedact
                ? Colors.green.withValues(alpha: 0.3)
                : Colors.orange.withValues(alpha: 0.2),
            child: Row(
              children: [
                Icon(
                  widget.autoRedact ? Icons.check_circle : Icons.touch_app,
                  color: widget.autoRedact ? Colors.green : Colors.orange,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.autoRedact
                        ? '✅ ${_boxes.length} sensitive area(s) automatically redacted'
                        : 'Tap and drag to mark areas to redact (${_boxes.length} selected)',
                    style: TextStyle(
                      color: widget.autoRedact ? Colors.green : Colors.orange,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onPanStart: (details) => _onPanStart(details, constraints),
                  onPanUpdate: (details) => _onPanUpdate(details, constraints),
                  onPanEnd: _onPanEnd,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(
                        File(widget.imagePath),
                        fit: BoxFit.contain,
                        frameBuilder:
                            (context, child, frame, wasSynchronouslyLoaded) {
                          if (frame != null) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _updateImageSize(context);
                            });
                          }
                          return child;
                        },
                      ),
                      CustomPaint(
                        painter: RedactionPainter(boxes: _boxes),
                        size: Size.infinite,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (_isProcessing)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Processing image...',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _boxes.isEmpty || _isProcessing
                              ? null
                              : () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[800],
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: _boxes.isEmpty || _isProcessing
                              ? null
                              : _saveAndShare,
                          icon: _isProcessing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save),
                          label: Text(
                            _isProcessing ? 'Processing...' : 'Save & Share',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _updateImageSize(BuildContext context) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox != null && _imageSize == null) {
      setState(() {
        _imageSize = renderBox.size;
      });
    }
  }

  void _onPanStart(DragStartDetails details, BoxConstraints constraints) {
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

  void _onPanUpdate(DragUpdateDetails details, BoxConstraints constraints) {
    if (_isDragging && _selectedBox != null) {
      setState(() {
        final newTopLeft = details.localPosition - _dragOffset!;
        final size = _selectedBox!.rect.size;
        _selectedBox!.rect = Rect.fromLTWH(
          newTopLeft.dx.clamp(0, constraints.maxWidth - size.width),
          newTopLeft.dy.clamp(0, constraints.maxHeight - size.height),
          size.width,
          size.height,
        );
      });
    } else if (_startPoint != null) {
      setState(() {
        final currentPoint = details.localPosition;
        final rect = Rect.fromPoints(_startPoint!, currentPoint);
        final normalizedRect = Rect.fromLTRB(
          rect.left.clamp(0.0, constraints.maxWidth),
          rect.top.clamp(0.0, constraints.maxHeight),
          rect.right.clamp(0.0, constraints.maxWidth),
          rect.bottom.clamp(0.0, constraints.maxHeight),
        );
        if (normalizedRect.width > 20 && normalizedRect.height > 20) {
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
}

class RedactionPainter extends CustomPainter {
  final List<RedactionBox> boxes;

  RedactionPainter({required this.boxes});

  @override
  void paint(Canvas canvas, Size size) {
    for (final box in boxes) {
      final fillPaint = Paint()
        ..color = Colors.red.withValues(alpha: 0.5)
        ..style = PaintingStyle.fill;

      canvas.drawRect(box.rect, fillPaint);

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
