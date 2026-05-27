import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear codigo')),
      body: MobileScanner(
        onDetect: (capture) {
          if (_handled) return;

          final code = capture.barcodes.firstOrNull?.rawValue;
          if (code == null || code.isEmpty) return;

          _handled = true;
          Navigator.of(context).pop(code);
        },
      ),
    );
  }
}
