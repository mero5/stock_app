import 'package:flutter/material.dart';

class ApiErrorBanner extends StatelessWidget {
  final String message;
  const ApiErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.red.shade50,
      child: Row(
        children: [
          const Icon(Icons.cloud_off, color: Colors.red, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$message\n株価取得・AI分析などの機能が制限されています。',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.red,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
