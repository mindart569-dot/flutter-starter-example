import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'result_screen.dart';

class ScanScreen extends StatefulWidget {
  final String imagePath;

  const ScanScreen({super.key, required this.imagePath});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _isScanning = true;
  String _statusMessage = 'Starting scan...';
  String _ocrText = '';
  String _analysisResult = '';
  String? _error;
  final FlutterTts _tts = FlutterTts();

  @override
  void initState() {
    super.initState();
    print('[ScanScreen] initState called');
    _performScan();
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Map<String, dynamic> _analyzeWithRegex(
      String text, RecognizedText recognizedText) {
    print('[ScanScreen] === STARTING MULTI-PASS DETECTION ===');
    print(
        '[ScanScreen] Analyzing text: ${text.substring(0, text.length > 100 ? 100 : text.length)}...');

    // PASS 1: Full text detection (catches multi-word patterns)
    print('[ScanScreen] PASS 1: Full text detection');
    List<Map<String, dynamic>> pass1Results =
        _detectInFullText(text, recognizedText);
    print('[ScanScreen] PASS 1 found: ${pass1Results.length} items');

    // PASS 2: Line-by-line detection (catches line-level patterns)
    print('[ScanScreen] PASS 2: Line-by-line detection');
    List<Map<String, dynamic>> pass2Results = _detectInLines(recognizedText);
    print('[ScanScreen] PASS 2 found: ${pass2Results.length} items');

    // PASS 3: Element-by-element detection (catches word-level patterns)
    print('[ScanScreen] PASS 3: Element-by-element detection');
    List<Map<String, dynamic>> pass3Results = _detectInElements(recognizedText);
    print('[ScanScreen] PASS 3 found: ${pass3Results.length} items');

    // PASS 4: Relaxed pattern detection (if previous passes found too few items)
    List<Map<String, dynamic>> pass4Results = [];
    final combinedSoFar = [...pass1Results, ...pass2Results, ...pass3Results];
    if (_shouldRunRelaxedDetection(combinedSoFar, text)) {
      print(
          '[ScanScreen] PASS 4: Relaxed pattern detection (triggered by low detection count)');
      pass4Results = _detectWithRelaxedPatterns(text, recognizedText);
      print('[ScanScreen] PASS 4 found: ${pass4Results.length} items');
    }

    // Merge all results (remove duplicates)
    List<Map<String, dynamic>> allFindings = _mergeDetectionResults([
      ...pass1Results,
      ...pass2Results,
      ...pass3Results,
      ...pass4Results,
    ]);

    print('[ScanScreen] Total after merging: ${allFindings.length} items');

    // Self-validation check
    final validationResult = _validateDetectionCompleteness(allFindings, text);
    if (!validationResult['complete']) {
      print(
          '[ScanScreen] WARNING: Detection may be incomplete: ${validationResult['reason']}');
      print('[ScanScreen] Triggering fail-safe re-scan...');

      // FAIL-SAFE: Re-run with maximum sensitivity
      final failsafeResults = _failsafeDetection(text, recognizedText);
      allFindings =
          _mergeDetectionResults([...allFindings, ...failsafeResults]);
      print('[ScanScreen] After fail-safe: ${allFindings.length} items');
    }

    print(
        '[ScanScreen] === FINAL DETECTION COMPLETE: ${allFindings.length} items ===');
    _logDetectionSummary(allFindings);

    return {
      'findings': allFindings,
      'rawText': text,
    };
  }

  // PASS 1: Detect patterns in full text (preserves original detection logic)
  List<Map<String, dynamic>> _detectInFullText(
      String text, RecognizedText recognizedText) {
    List<Map<String, dynamic>> found = [];
    final patterns = _getDetectionPatterns();

    for (var pattern in patterns) {
      final regex = pattern['regex'] as RegExp;
      final matches = regex.allMatches(text);

      for (var match in matches) {
        final matchedText = match.group(0) ?? '';
        // Find approximate bounding box by searching in OCR results
        final bbox = _findBoundingBoxForText(matchedText, recognizedText);

        if (bbox != null) {
          found.add({
            'type': pattern['type'],
            'value': matchedText,
            'description': pattern['description'],
            'confidence': pattern['confidence'],
            'icon': pattern['icon'],
            'boundingBox': bbox,
          });
          print('[ScanScreen] PASS 1 - Found ${pattern['type']}: $matchedText');
        }
      }
    }

    return found;
  }

  // PASS 2: Detect patterns line-by-line
  List<Map<String, dynamic>> _detectInLines(RecognizedText recognizedText) {
    List<Map<String, dynamic>> found = [];
    final patterns = _getDetectionPatterns();

    for (var block in recognizedText.blocks) {
      for (var line in block.lines) {
        final lineText = line.text;

        for (var pattern in patterns) {
          final regex = pattern['regex'] as RegExp;
          if (regex.hasMatch(lineText)) {
            final bbox = line.boundingBox;

            found.add({
              'type': pattern['type'],
              'value': lineText,
              'description': pattern['description'],
              'confidence': pattern['confidence'],
              'icon': pattern['icon'],
              'boundingBox': {
                'left': bbox.left.toDouble(),
                'top': bbox.top.toDouble(),
                'width': bbox.width.toDouble(),
                'height': bbox.height.toDouble(),
              },
            });
            print(
                '[ScanScreen] PASS 2 - Found ${pattern['type']} in line: $lineText');
          }
        }
      }
    }

    return found;
  }

  // PASS 3: Detect patterns element-by-element
  List<Map<String, dynamic>> _detectInElements(RecognizedText recognizedText) {
    List<Map<String, dynamic>> found = [];
    final patterns = _getDetectionPatterns();

    for (var block in recognizedText.blocks) {
      for (var line in block.lines) {
        for (var element in line.elements) {
          final elementText = element.text;

          for (var pattern in patterns) {
            final regex = pattern['regex'] as RegExp;
            if (regex.hasMatch(elementText)) {
              final bbox = element.boundingBox;

              found.add({
                'type': pattern['type'],
                'value': elementText,
                'description': pattern['description'],
                'confidence': pattern['confidence'],
                'icon': pattern['icon'],
                'boundingBox': {
                  'left': bbox.left.toDouble(),
                  'top': bbox.top.toDouble(),
                  'width': bbox.width.toDouble(),
                  'height': bbox.height.toDouble(),
                },
              });
              print(
                  '[ScanScreen] PASS 3 - Found ${pattern['type']} in element: $elementText');
            }
          }
        }
      }
    }

    return found;
  }

  // PASS 4: Relaxed pattern detection
  List<Map<String, dynamic>> _detectWithRelaxedPatterns(
      String text, RecognizedText recognizedText) {
    List<Map<String, dynamic>> found = [];

    // Relaxed phone detection (any 10 digits)
    final relaxedPhoneRegex = RegExp(r'\d{10}');
    for (var match in relaxedPhoneRegex.allMatches(text)) {
      final matchedText = match.group(0) ?? '';
      final bbox = _findBoundingBoxForText(matchedText, recognizedText);
      if (bbox != null) {
        found.add({
          'type': 'PHONE',
          'value': matchedText,
          'description': 'potential phone number',
          'confidence': 0.70,
          'icon': '📱',
          'boundingBox': bbox,
        });
        print('[ScanScreen] PASS 4 - Found relaxed PHONE: $matchedText');
      }
    }

    // Relaxed Aadhaar detection (any 12 digits with optional spaces)
    final relaxedAadhaarRegex = RegExp(r'\d{4}\s?\d{4}\s?\d{4}');
    for (var match in relaxedAadhaarRegex.allMatches(text)) {
      final matchedText = match.group(0) ?? '';
      final bbox = _findBoundingBoxForText(matchedText, recognizedText);
      if (bbox != null) {
        found.add({
          'type': 'AADHAAR',
          'value': matchedText,
          'description': 'potential 12-digit ID',
          'confidence': 0.75,
          'icon': '🪪',
          'boundingBox': bbox,
        });
        print('[ScanScreen] PASS 4 - Found relaxed AADHAAR: $matchedText');
      }
    }

    // Relaxed date detection (any date pattern)
    final relaxedDateRegex = RegExp(r'\d{1,2}[/-]\d{1,2}[/-]\d{2,4}');
    for (var match in relaxedDateRegex.allMatches(text)) {
      final matchedText = match.group(0) ?? '';
      final bbox = _findBoundingBoxForText(matchedText, recognizedText);
      if (bbox != null) {
        found.add({
          'type': 'DOB',
          'value': matchedText,
          'description': 'potential date',
          'confidence': 0.70,
          'icon': '📅',
          'boundingBox': bbox,
        });
        print('[ScanScreen] PASS 4 - Found relaxed DOB: $matchedText');
      }
    }

    // Relaxed card number detection (any 16 digits with optional separators)
    final relaxedCardRegex = RegExp(r'\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}');
    for (var match in relaxedCardRegex.allMatches(text)) {
      final matchedText = match.group(0) ?? '';
      final bbox = _findBoundingBoxForText(matchedText, recognizedText);
      if (bbox != null) {
        found.add({
          'type': 'BANK',
          'value': matchedText,
          'description': 'potential card number',
          'confidence': 0.72,
          'icon': '💳',
          'boundingBox': bbox,
        });
        print('[ScanScreen] PASS 4 - Found relaxed BANK: $matchedText');
      }
    }

    return found;
  }

  // Fail-safe detection with maximum sensitivity
  List<Map<String, dynamic>> _failsafeDetection(
      String text, RecognizedText recognizedText) {
    print('[ScanScreen] FAIL-SAFE: Running maximum sensitivity detection');
    List<Map<String, dynamic>> found = [];

    // Detect any number sequence that could be sensitive
    final numberSequenceRegex = RegExp(r'\d{4,}');
    for (var match in numberSequenceRegex.allMatches(text)) {
      final matchedText = match.group(0) ?? '';
      if (matchedText.length >= 8) {
        final bbox = _findBoundingBoxForText(matchedText, recognizedText);
        if (bbox != null) {
          found.add({
            'type': 'SENSITIVE_NUMBER',
            'value': matchedText,
            'description': 'number sequence',
            'confidence': 0.60,
            'icon': '🔢',
            'boundingBox': bbox,
          });
          print('[ScanScreen] FAIL-SAFE - Found number sequence: $matchedText');
        }
      }
    }

    return found;
  }

  // Helper: Get all detection patterns
  List<Map<String, dynamic>> _getDetectionPatterns() {
    return [
      {
        'type': 'PHONE',
        'regex': RegExp(r'(?<!\d)[6-9]\d{9}(?!\d)'),
        'description': 'Indian mobile number',
        'confidence': 0.95,
        'icon': '📱'
      },
      {
        'type': 'AADHAAR',
        'regex': RegExp(r'(?<!\d)\d{4}[\s]?\d{4}[\s]?\d{4}(?!\d)'),
        'description': '12-digit ID number',
        'confidence': 0.90,
        'icon': '🪪'
      },
      {
        'type': 'PAN',
        'regex': RegExp(r'\b[A-Z]{5}[0-9]{4}[A-Z]\b'),
        'description': 'PAN card number',
        'confidence': 0.88,
        'icon': '🪪'
      },
      {
        'type': 'EMAIL',
        'regex': RegExp(r'\b[\w.]+@[\w.]+\.\w+\b'),
        'description': 'email address',
        'confidence': 0.92,
        'icon': '📧'
      },
      {
        'type': 'VEHICLE',
        'regex': RegExp(r'\b[A-Z]{2}\d{1,4}[A-Z0-9]{1,10}\b'),
        'description': 'vehicle registration',
        'confidence': 0.75,
        'icon': '🚗'
      },
      {
        'type': 'DOB',
        'regex': RegExp(
          r'(?:DOB|D\.O\.B|Date\s*of\s*Birth|Born)[:\s]*\d{1,2}[/-]\d{1,2}[/-]\d{2,4}',
          caseSensitive: false,
        ),
        'description': 'date of birth',
        'confidence': 0.85,
        'icon': '📅'
      },
      {
        'type': 'ADDRESS',
        'regex': RegExp(
          r'(?:House\s*(?:No|#)|Flat\s*(?:No|#)|Street|Street\s*No|Village|District|Pin\s*(?:Code)?|PIN\s*Code)',
          caseSensitive: false,
        ),
        'description': 'address component',
        'confidence': 0.80,
        'icon': '🏠'
      },
      {
        'type': 'BANK',
        'regex': RegExp(r'\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b'),
        'description': 'card number',
        'confidence': 0.87,
        'icon': '💳'
      },
    ];
  }

  // Helper: Find bounding box for matched text
  Map<String, double>? _findBoundingBoxForText(
      String searchText, RecognizedText recognizedText) {
    // Search through all elements to find matching text
    for (var block in recognizedText.blocks) {
      for (var line in block.lines) {
        // Check if line contains the search text
        if (line.text.contains(searchText)) {
          final bbox = line.boundingBox;
          return {
            'left': bbox.left.toDouble(),
            'top': bbox.top.toDouble(),
            'width': bbox.width.toDouble(),
            'height': bbox.height.toDouble(),
          };
        }

        // Check individual elements
        for (var element in line.elements) {
          if (element.text.contains(searchText)) {
            final bbox = element.boundingBox;
            return {
              'left': bbox.left.toDouble(),
              'top': bbox.top.toDouble(),
              'width': bbox.width.toDouble(),
              'height': bbox.height.toDouble(),
            };
          }
        }
      }
    }

    // If not found, return null (item will be skipped)
    return null;
  }

  // Helper: Merge detection results and remove duplicates
  List<Map<String, dynamic>> _mergeDetectionResults(
      List<Map<String, dynamic>> results) {
    final Map<String, Map<String, dynamic>> uniqueResults = {};

    for (var result in results) {
      final key = '${result['type']}_${result['value']}';

      // Keep the result with higher confidence if duplicate
      if (!uniqueResults.containsKey(key) ||
          (result['confidence'] as double) >
              (uniqueResults[key]!['confidence'] as double)) {
        uniqueResults[key] = result;
      }
    }

    return uniqueResults.values.toList();
  }

  // Helper: Determine if relaxed detection should run
  bool _shouldRunRelaxedDetection(
      List<Map<String, dynamic>> currentResults, String text) {
    // If text is substantial but detections are low, run relaxed detection
    final wordCount = text.split(RegExp(r'\s+')).length;

    if (wordCount > 20 && currentResults.length < 3) {
      return true;
    }

    // If no detections at all but text exists
    if (currentResults.isEmpty && text.trim().isNotEmpty) {
      return true;
    }

    return false;
  }

  // Self-validation: Check if detection is complete
  Map<String, dynamic> _validateDetectionCompleteness(
      List<Map<String, dynamic>> findings, String text) {
    // Check if text seems to contain data but no detections
    if (findings.isEmpty && text.length > 50) {
      return {
        'complete': false,
        'reason': 'Text is substantial but no detections found',
      };
    }

    // Check for unexpectedly low detection count
    final wordCount = text.split(RegExp(r'\s+')).length;
    if (wordCount > 50 && findings.length < 2) {
      return {
        'complete': false,
        'reason': 'Large text but very few detections (${findings.length})',
      };
    }

    // All checks passed
    return {
      'complete': true,
      'reason': 'Detection appears complete',
    };
  }

  // Helper: Log detection summary
  void _logDetectionSummary(List<Map<String, dynamic>> findings) {
    final typeCount = <String, int>{};
    for (var finding in findings) {
      final type = finding['type'] as String;
      typeCount[type] = (typeCount[type] ?? 0) + 1;
    }

    print('[ScanScreen] === DETECTION SUMMARY ===');
    for (var entry in typeCount.entries) {
      print('[ScanScreen]   ${entry.key}: ${entry.value} item(s)');
    }
    print('[ScanScreen] === END SUMMARY ===');
  }

  Future<void> _speakResult(List<Map<String, dynamic>> findings) async {
    try {
      print('[ScanScreen] Speaking result...');
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.5);

      if (findings.isEmpty) {
        await _tts.speak('This image appears safe to share');
      } else {
        final types = findings.map((f) => f['type']).join(', ');
        await _tts.speak(
          'Warning! This image contains sensitive information including $types. Do not share this image.',
        );
      }
      print('[ScanScreen] TTS complete');
    } catch (e) {
      print('[ScanScreen] TTS error: $e');
    }
  }

  Future<void> _performScan() async {
    print('[ScanScreen] _performScan started');

    try {
      // Step 1: Initialize OCR
      print('[ScanScreen] Step 1: Initializing OCR...');
      setState(() => _statusMessage = 'Initializing OCR...');

      final inputImage = InputImage.fromFilePath(widget.imagePath);
      final textRecognizer = TextRecognizer();

      // Step 2: Process image
      print('[ScanScreen] Step 2: Processing image...');
      setState(() => _statusMessage = 'Extracting text from image...');

      final recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

      print(
          '[ScanScreen] OCR complete. Text length: ${recognizedText.text.length}');
      print('[ScanScreen] OCR text: "${recognizedText.text}"');

      _ocrText = recognizedText.text;

      // Step 3: Check if text is empty
      if (_ocrText.trim().isEmpty) {
        print('[ScanScreen] No text found in image');
        _analysisResult = 'No text found in this image';
        await _speakResult([]);

        if (!mounted) return;
        setState(() {
          _isScanning = false;
          _statusMessage = 'No text detected';
        });
        return;
      }

      // Step 4: Analyze text with regex and get bounding boxes
      print('[ScanScreen] Step 3: Analyzing text...');
      setState(() => _statusMessage = 'Analyzing for sensitive data...');

      final analysisResult = _analyzeWithRegex(_ocrText, recognizedText);
      final findings = analysisResult['findings'] as List<Map<String, dynamic>>;

      if (findings.isEmpty) {
        _analysisResult = 'SAFE';
      } else {
        // Convert findings to JSON string for passing to result screen
        _analysisResult = findings
            .map((f) =>
                '${f['type']}: ${f['description']} (${(f['confidence'] * 100).toInt()}% confidence)')
            .join('\n');
      }

      print('[ScanScreen] Analysis result: $_analysisResult');

      // Step 5: Speak result
      print('[ScanScreen] Step 4: Speaking result...');
      _speakResult(findings);

      // Step 6: Update UI and navigate
      print('[ScanScreen] Step 5: Updating UI and navigating...');
      if (!mounted) return;

      setState(() {
        _isScanning = false;
        _statusMessage = 'Scan complete';
      });

      // Navigate after frame builds
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        print('[ScanScreen] Navigating to ResultScreen...');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ResultScreen(
              llmResponse: _analysisResult,
              imagePath: widget.imagePath,
              detectedRegions: findings,
            ),
          ),
        );
        print('[ScanScreen] Navigation complete');
      });
    } catch (e, stackTrace) {
      print('[ScanScreen] ERROR: $e');
      print('[ScanScreen] STACK TRACE: $stackTrace');

      if (!mounted) return;

      setState(() {
        _isScanning = false;
        _error = e.toString();
        _statusMessage = 'Scan failed';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanning'),
        automaticallyImplyLeading: false,
        leading: _isScanning
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(
                  File(widget.imagePath),
                  height: 300,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    print('[ScanScreen] Image load error: $error');
                    return Container(
                      height: 300,
                      color: Colors.grey[800],
                      child: const Center(
                        child: Icon(Icons.broken_image,
                            size: 64, color: Colors.white54),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              if (_isScanning) ...[
                Center(
                  child: Column(
                    children: [
                      const CircularProgressIndicator(
                        color: Color(0xFF9333EA),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _statusMessage,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: Colors.red.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.red, size: 48),
                      const SizedBox(height: 8),
                      Text(
                        'Error: $_error',
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        child: const Text('Go Back'),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D1B4E),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _analysisResult == 'SAFE'
                                ? Icons.check_circle
                                : Icons.warning,
                            color: _analysisResult == 'SAFE'
                                ? Colors.green
                                : Colors.red,
                            size: 28,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Analysis Result',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white24),
                      const SizedBox(height: 8),
                      Text(
                        _analysisResult,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Icon(Icons.volume_up, color: Colors.white54, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Result spoken aloud',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ResultScreen(
                          llmResponse: _analysisResult,
                          imagePath: widget.imagePath,
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF9333EA),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'View Summary',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
