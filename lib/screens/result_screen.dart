import 'dart:io';
import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'redact_screen.dart';

class ResultScreen extends StatelessWidget {
  final String llmResponse;
  final String imagePath;

  const ResultScreen({
    super.key,
    required this.llmResponse,
    required this.imagePath,
  });

  bool get _isSafe {
    final lower = llmResponse.toLowerCase();
    return lower.contains('safe');
  }

  List<Map<String, String>> _parseSensitiveItems() {
    final items = <Map<String, String>>[];
    final lines = llmResponse.split('\n');

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
            'value': parts.length > 1 ? parts.sublist(1).join(':').trim() : entry.value,
          });
          break;
        }
      }
    }
    return items;
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

  @override
  Widget build(BuildContext context) {
    final sensitiveItems = _parseSensitiveItems();
    final isSafe = _isSafe || sensitiveItems.isEmpty;
    final riskScore = _calculateRiskScore(sensitiveItems);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Result'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(
                  File(imagePath),
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                        style: TextStyle(
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
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
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
                                child: Text(
                                  item['value'] ?? '',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.white70,
                                  ),
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
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => RedactScreen(imagePath: imagePath),
                        ),
                      );
                    },
                    icon: const Icon(Icons.blur_on),
                    label: const Text(
                      '🔴 Redact Sensitive Areas',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => RedactScreen(imagePath: imagePath),
                        ),
                      );
                    },
                    icon: const Icon(Icons.share),
                    label: const Text(
                      'Share Safe Version',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
