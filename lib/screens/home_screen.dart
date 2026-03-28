import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'scan_screen.dart';

class ScanHistory {
  final String imagePath;
  final DateTime date;
  final String findings;
  final int riskScore;

  ScanHistory({
    required this.imagePath,
    required this.date,
    required this.findings,
    required this.riskScore,
  });

  Map<String, dynamic> toJson() => {
        'imagePath': imagePath,
        'date': date.toIso8601String(),
        'findings': findings,
        'riskScore': riskScore,
      };

  factory ScanHistory.fromJson(Map<String, dynamic> json) => ScanHistory(
        imagePath: json['imagePath'],
        date: DateTime.parse(json['date']),
        findings: json['findings'],
        riskScore: json['riskScore'],
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _imagesScanned = 0;
  List<ScanHistory> _recentScans = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getStringList('scanHistory') ?? [];
    
    final history = historyJson
        .map((json) => ScanHistory.fromJson(jsonDecode(json)))
        .toList();

    setState(() {
      _imagesScanned = prefs.getInt('imagesScanned') ?? 0;
      _recentScans = history.take(3).toList();
    });
  }

  Future<void> _saveScan(String imagePath, String findings, int riskScore) async {
    final prefs = await SharedPreferences.getInstance();
    
    final newScan = ScanHistory(
      imagePath: imagePath,
      date: DateTime.now(),
      findings: findings,
      riskScore: riskScore,
    );

    final historyJson = prefs.getStringList('scanHistory') ?? [];
    historyJson.insert(0, jsonEncode(newScan.toJson()));
    
    if (historyJson.length > 10) {
      historyJson.removeRange(10, historyJson.length);
    }

    await prefs.setStringList('scanHistory', historyJson);
    await prefs.setInt('imagesScanned', _imagesScanned + 1);

    if (mounted) {
      setState(() {
        _imagesScanned++;
        _recentScans.insert(0, newScan);
        if (_recentScans.length > 3) {
          _recentScans = _recentScans.take(3).toList();
        }
      });
    }
  }

  Future<void> _pickImage(BuildContext context, ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source);

    if (pickedFile != null && context.mounted) {
      await _saveScan(pickedFile.path, '', 0);
      
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ScanScreen(imagePath: pickedFile.path),
        ),
      ).then((_) => _loadData());
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${date.day}/${date.month}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF9333EA), Color(0xFF6B21A8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF9333EA).withValues(alpha: 0.4),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.security,
                    size: 60,
                    color: Colors.white,
                  ),
                )
                    .animate(onPlay: (controller) => controller.repeat(reverse: true))
                    .scale(
                      begin: const Offset(1.0, 1.0),
                      end: const Offset(1.05, 1.05),
                      duration: 1500.ms,
                    )
                    .then()
                    .scale(
                      begin: const Offset(1.05, 1.05),
                      end: const Offset(1.0, 1.0),
                      duration: 1500.ms,
                    ),
              ),
              const SizedBox(height: 24),
              const Center(
                child: Text(
                  'SafeShare 🛡️',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const Center(
                child: Text(
                  'Think Before You Share',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.white70,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D1B4E),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.analytics, color: Color(0xFF9333EA), size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '$_imagesScanned images scanned',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D1B4E),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'How it works',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildStep(1, '📸', 'Pick Image', 'Choose from gallery or camera'),
                    const SizedBox(height: 12),
                    _buildStep(2, '🔍', 'AI Scans', 'Detects sensitive information'),
                    const SizedBox(height: 12),
                    _buildStep(3, '✅', 'Safe to Share', 'Share with confidence'),
                  ],
                ),
              ),
              if (_recentScans.isNotEmpty) ...[
                const SizedBox(height: 24),
                const Text(
                  'Recent Scans',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                ..._recentScans.map((scan) => _buildHistoryCard(scan)),
              ],
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: () => _pickImage(context, ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text(
                    'Pick from Gallery',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF9333EA),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: () => _pickImage(context, ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text(
                    'Use Camera',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4C1D95),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryCard(ScanHistory scan) {
    final isSafe = scan.findings.toLowerCase().contains('safe') || scan.riskScore == 0;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2D1B4E).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSafe 
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.red.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.grey[800],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: File(scan.imagePath).existsSync()
                  ? Image.file(
                      File(scan.imagePath),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.image,
                        color: Colors.white54,
                      ),
                    )
                  : const Icon(Icons.image, color: Colors.white54),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isSafe ? Icons.check_circle : Icons.warning,
                      size: 16,
                      color: isSafe ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isSafe ? 'SAFE' : 'SENSITIVE (${scan.riskScore}/10)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isSafe ? Colors.green : Colors.red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDate(scan.date),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep(int number, String emoji, String title, String subtitle) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF9333EA).withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              emoji,
              style: const TextStyle(fontSize: 20),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$number. $title',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white54,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
