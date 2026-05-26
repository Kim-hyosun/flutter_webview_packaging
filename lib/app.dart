import 'package:flutter/material.dart';

import 'screens/webview_screen.dart';

class MyApp extends StatefulWidget {
  final String serviceUrl;
  final String baseUrl;

  const MyApp({super.key, required this.serviceUrl, required this.baseUrl});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Energyus Monitoring',
      home: WebViewScreen(
        serviceUrl: widget.serviceUrl,
        baseUrl: widget.baseUrl,
      ),
    );
  }
}
