import 'package:flutter/material.dart';

void main() {
  runApp(const RelinkApp());
}

/// Throwaway placeholder — real screens arrive in Phase 2.
class RelinkApp extends StatelessWidget {
  const RelinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('RELINK')),
      ),
    );
  }
}
