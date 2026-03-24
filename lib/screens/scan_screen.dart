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
  String _ocrText = '';
  String _llmResponse = '';
  String? _error;
  final FlutterTts _tts = FlutterTts();

  List<String> _analyzeWithRegex(String text) {
    List<String> found = [];

    if (RegExp(r'(?<!\d)\d{10}(?!\d)').hasMatch(text) ||
        RegExp(r'\b[6-9]\d{9}\b').hasMatch(text)) {
      found.add('PHONE: Found Indian mobile number');
    }

    if (RegExp(r'(?<!\d)\d{12}(?!\d)').hasMatch(text) ||
        RegExp(r'\b\d{4}\s?\d{4}\s?\d{4}\b').hasMatch(text)) {
      found.add('AADHAAR: Found 12-digit ID number');
    }

    if (RegExp(r'\b[A-Z]{5}[0-9]{4}[A-Z]\b').hasMatch(text)) {
      found.add('PAN: Found PAN card number');
    }

    if (RegExp(r'\S+@\S+\.\S+').hasMatch(text)) {
      found.add('EMAIL: Found email address');
    }

    if (RegExp(r'\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b').hasMatch(text)) {
      found.add('BANK: Found card number');
    }

    if (RegExp(r'\b[A-Z]{1,2}[0-9]{7}\b').hasMatch(text)) {
      found.add('PASSPORT: Found passport number');
    }

    if (RegExp(r'[A-Z]{2}[0-9]{1,4}[A-Z0-9]{1,10}').hasMatch(text)) {
      found.add('VEHICLE: Found vehicle registration number');
    }

    if (RegExp(r'(?:DOB|D\.O\.B|Birth\s*Date)[:\s]*\d{1,2}[/-]\d{1,2}[/-]\d{2,4}',
            caseSensitive: false).hasMatch(text)) {
      found.add('DOB: Found date of birth');
    }

    if (RegExp(r'(?:House\s*No|Flat|Street|Village|District|Pin\s*Code|PIN)',
            caseSensitive: false).hasMatch(text)) {
      found.add('ADDRESS: Found address component');
    }

    return found;
  }

  Future<void> _speakResult(List<String> findings) async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);

    if (findings.isEmpty) {
      await _tts.speak('This image appears safe to share');
    } else {
      final types = findings.map((f) => f.split(':').first).join(', ');
      await _tts.speak(
          'Warning! This image contains sensitive information including $types. Do not share this image.');
    }
  }

  @override
  void initState() {
    super.initState();
    _performScan();
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _performScan() async {
    try {
      final inputImage = InputImage.fromFilePath(widget.imagePath);
      final textRecognizer = TextRecognizer();
      final recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

      if (!mounted) return;

      _ocrText = recognizedText.text;

      if (_ocrText.isEmpty) {
        setState(() {
          _isScanning = false;
          _llmResponse = 'No text found in the image.';
        });
        await _speakResult([]);
        return;
      }

      final findings = _analyzeWithRegex(_ocrText);
      _llmResponse = findings.isEmpty ? 'SAFE' : findings.join('\n');

      await _speakResult(findings);

      if (!mounted) return;

      setState(() {
        _isScanning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanning...'),
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
                ),
              ),
              const SizedBox(height: 24),
              if (_isScanning) ...[
                const Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(
                        color: Color(0xFF9333EA),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Scanning for sensitive data...',
                        style: TextStyle(
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
                    border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 48),
                      const SizedBox(height: 8),
                      Text(
                        'Error: $_error',
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
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
                            _llmResponse == 'SAFE' ? Icons.check_circle : Icons.warning,
                            color: _llmResponse == 'SAFE' ? Colors.green : Colors.red,
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
                        _llmResponse,
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
                Row(
                  children: [
                    const Icon(Icons.volume_up, color: Colors.white54, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Result spoken aloud',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.5),
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
                          llmResponse: _llmResponse,
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
