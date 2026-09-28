import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/demo/live_demo_page.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const AsGrintaLiveDemoApp());
}

class AsGrintaLiveDemoApp extends StatelessWidget {
  const AsGrintaLiveDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AS Grinta · Tableau Blanc',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const LiveDemoPage(),
    );
  }
}
