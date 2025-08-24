import 'package:flutter/material.dart';
import 'login_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Greenstem Auto',
      theme: ThemeData(
        primarySwatch: Colors.green,
      ),

      home: const LoginPage(),
    );
  }
}