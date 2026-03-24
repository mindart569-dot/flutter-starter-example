import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SafeShareApp());
}

class SafeShareApp extends StatelessWidget {
  const SafeShareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeShare',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.dark(primary: const Color(0xFF9333EA)),
      ),
      home: const HomeScreen(),
    );
  }
}
