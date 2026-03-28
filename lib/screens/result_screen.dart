import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';
import 'redact_screen.dart';

class ResultScreen extends StatefulWidget {
  final String llmResponse;
  final String imagePath;
  final List<Map<String, dynamic>> detectedRegions;

  const ResultScreen({
    super.key,
    required this.llmResponse,
    required this.imagePath,
    this.detectedRegions = const [],
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  @override
  void initState() {
    super.initState();
    _updateHistory();
    _triggerVibrationFeedback();
  }

  Future<void> _triggerVibrationFeedback() async {
    // Vibration feedback based on risk level
    final sensitiveItems = _parseSensitiveItems();
    if (sensitiveItems.isEmpty) return;

    final riskScore = _calculateRiskScore(sensitiveItems);

    if (riskScore >= 7) {
      // High risk: Long vibration
      HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 200));
      HapticFeedback.heavyImpact();
    } else if (riskScore >= 4) {
      // Medium risk: Short pulses
      HapticFeedback.mediumImpact();
      await Future.delayed(const Duration(milliseconds: 100));
      HapticFeedback.mediumImpact();
      await Future.delayed(const Duration(milliseconds: 100));
      HapticFeedback.mediumImpact();
    }
  }

  Future<void> _updateHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getStringList('scanHistory') ?? [];

    if (historyJson.isNotEmpty) {
      final latestScan = jsonDecode(historyJson.first);
      if (latestScan['imagePath'] == widget.imagePath &&
          (latestScan['findings'] == '' || latestScan['findings'].isEmpty)) {
        latestScan['findings'] = widget.llmResponse;
        latestScan['riskScore'] = _calculateRiskScore(_parseSensitiveItems());
        historyJson[0] = jsonEncode(latestScan);
        await prefs.setStringList('scanHistory', historyJson);
      }
    }
  }

  bool get _isSafe {
    final lower = widget.llmResponse.toLowerCase();
    return lower.contains('safe');
  }

  List<Map<String, String>> _parseSensitiveItems() {
    // First check if we have detected regions with full metadata
    if (widget.detectedRegions.isNotEmpty) {
      return widget.detectedRegions.map((region) {
        return {
          'type': region['type'] as String,
          'value': region['value'] as String,
          'description': region['description'] as String,
          'confidence': (region['confidence'] as double).toString(),
          'icon': region['icon'] as String? ?? '',
        };
      }).toList();
    }

    // Fallback to parsing from llmResponse
    final items = <Map<String, String>>[];
    final lines = widget.llmResponse.split('\n');

    final typePatterns = {
      'AADHAAR': 'aadhaar',
      'PAN': 'pan',
      'PHONE': 'phone',
      'EMAIL': 'email',
      'BANK': 'bank',
      'PASSPORT': 'passport',
      'VEHICLE': 'vehicle',
      'DOB': 'dob',
      'ADDRESS': 'address',
    };

    for (final line in lines) {
      final lower = line.toLowerCase();
      for (final entry in typePatterns.entries) {
        if (lower.contains(entry.value)) {
          final parts = line.split(':');
          items.add({
            'type': entry.key,
            'value': parts.length > 1
                ? parts.sublist(1).join(':').trim()
                : entry.value,
            'confidence': '0.85',
            'icon': _getEmojiForType(entry.key),
          });
          break;
        }
      }
    }
    return items;
  }

  String _getEmojiForType(String type) {
    switch (type) {
      case 'PHONE':
        return '📱';
      case 'AADHAAR':
      case 'PAN':
        return '🪪';
      case 'EMAIL':
        return '📧';
      case 'VEHICLE':
        return '🚗';
      case 'DOB':
        return '📅';
      case 'ADDRESS':
        return '🏠';
      case 'BANK':
        return '💳';
      default:
        return '⚠️';
    }
  }

  int _calculateRiskScore(List<Map<String, String>> items) {
    int score = 0;
    for (final item in items) {
      final type = item['type'] ?? '';
      switch (type) {
        case 'AADHAAR':
        case 'PAN':
        case 'BANK':
          score += 3;
          break;
        case 'PHONE':
          score += 2;
          break;
        case 'EMAIL':
        case 'PASSPORT':
        case 'VEHICLE':
        case 'DOB':
        case 'ADDRESS':
          score += 1;
          break;
      }
    }
    return score.clamp(0, 10);
  }

  Color _getChipColor(String type) {
    switch (type) {
      case 'AADHAAR':
      case 'BANK':
        return Colors.red;
      case 'PAN':
        return Colors.orange;
      case 'PHONE':
        return Colors.yellow;
      case 'EMAIL':
        return Colors.blue;
      case 'PASSPORT':
      case 'VEHICLE':
      case 'DOB':
      case 'ADDRESS':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  Future<void> _showDeleteConfirmation(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D1B4E),
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('Secure Delete?', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'This will permanently delete the image and all cached versions from your device. This action cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _secureDeleteImage();
    }
  }

  Future<void> _secureDeleteImage() async {
    try {
      // Delete the original image
      final file = File(widget.imagePath);
      if (await file.exists()) {
        await file.delete();
      }

      // Provide haptic feedback
      HapticFeedback.heavyImpact();

      if (!mounted) return;

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text('Image securely deleted'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );

      // Navigate back to home after a brief delay
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sensitiveItems = _parseSensitiveItems();
    final isSafe = _isSafe || sensitiveItems.isEmpty;
    final riskScore = _calculateRiskScore(sensitiveItems);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Result'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => const HomeScreen()),
              (route) => false,
            );
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(
                  File(widget.imagePath),
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      height: 200,
                      color: Colors.grey[800],
                      child: const Center(
                        child:
                            Icon(Icons.image, size: 64, color: Colors.white54),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: isSafe
                      ? Colors.green.withValues(alpha: 0.2)
                      : Colors.red.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSafe ? Colors.green : Colors.red,
                    width: 4,
                  ),
                ),
                child: Icon(
                  isSafe ? Icons.check : Icons.warning,
                  size: 50,
                  color: isSafe ? Colors.green : Colors.red,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isSafe ? 'SAFE ✅' : 'SENSITIVE ⚠️',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: isSafe ? Colors.green : Colors.red,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: riskScore >= 7
                      ? Colors.red.withValues(alpha: 0.2)
                      : riskScore >= 4
                          ? Colors.orange.withValues(alpha: 0.2)
                          : Colors.yellow.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: riskScore >= 7
                        ? Colors.red
                        : riskScore >= 4
                            ? Colors.orange
                            : Colors.yellow,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Risk Score: $riskScore/10',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: riskScore >= 7
                            ? Colors.red
                            : riskScore >= 4
                                ? Colors.orange
                                : Colors.yellow,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      riskScore >= 7
                          ? '🔴'
                          : riskScore >= 4
                              ? '🟠'
                              : '🟡',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (!isSafe && sensitiveItems.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: sensitiveItems.map((item) {
                    final chipColor = _getChipColor(item['type'] ?? '');
                    return Chip(
                      label: Text(
                        item['type'] ?? 'UNKNOWN',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      backgroundColor: chipColor.withValues(alpha: 0.3),
                      side: BorderSide(color: chipColor),
                      avatar: Icon(
                        _getIconForType(item['type'] ?? ''),
                        size: 16,
                        color: chipColor,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D1B4E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.shield, color: Colors.orange, size: 24),
                          SizedBox(width: 8),
                          Text(
                            'Detected Items',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white24, height: 24),
                      ...sensitiveItems.map((item) {
                        final chipColor = _getChipColor(item['type'] ?? '');
                        final confidence = item['confidence'] ?? '0.85';
                        final confidencePercent =
                            (double.parse(confidence) * 100).toInt();
                        final icon = item['icon'] ??
                            _getEmojiForType(item['type'] ?? '');

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Text(
                                icon,
                                style: const TextStyle(fontSize: 20),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: chipColor.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  item['type'] ?? 'UNKNOWN',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: chipColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item['value'] ?? '',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.white70,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$confidencePercent% confidence',
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
                      }),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (!isSafe) ...[
                // One-Tap Safe Share Button (Primary Action)
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => RedactScreen(
                            imagePath: widget.imagePath,
                            detectedRegions: widget.detectedRegions,
                            autoRedact: true, // Auto-apply detected regions
                            autoShare: true, // Share after redaction
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.share_rounded),
                    label: const Text(
                      '✅ One-Tap Safe Share',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Manual Redact Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => RedactScreen(
                            imagePath: widget.imagePath,
                            detectedRegions: widget.detectedRegions,
                            autoRedact: false, // Manual mode
                            autoShare: false,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.edit),
                    label: const Text(
                      'Manual Redaction',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Secure Delete Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: () => _showDeleteConfirmation(context),
                    icon: const Icon(Icons.delete_forever),
                    label: const Text(
                      '🗑️ Secure Delete',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const HomeScreen(),
                      ),
                      (route) => false,
                    );
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text(
                    'Scan Another',
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
            ],
          ),
        ),
      ),
    );
  }

  IconData _getIconForType(String type) {
    switch (type) {
      case 'AADHAAR':
        return Icons.badge;
      case 'PAN':
        return Icons.credit_card;
      case 'PHONE':
        return Icons.phone;
      case 'EMAIL':
        return Icons.email;
      case 'BANK':
        return Icons.account_balance;
      case 'PASSPORT':
        return Icons.flight;
      case 'VEHICLE':
        return Icons.directions_car;
      case 'DOB':
        return Icons.cake;
      case 'ADDRESS':
        return Icons.home;
      default:
        return Icons.warning;
    }
  }
}
