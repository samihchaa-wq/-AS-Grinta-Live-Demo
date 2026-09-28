import 'package:flutter/material.dart';

class GrintaProgressIndicator extends StatelessWidget {
  const GrintaProgressIndicator({super.key, this.strokeWidth = 4});

  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return CircularProgressIndicator(strokeWidth: strokeWidth);
  }
}
