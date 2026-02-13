import 'package:flutter/material.dart';

class PetWidget extends StatelessWidget {
  final double size;
  final Color color;

  const PetWidget({super.key, this.size = 100, this.color = Colors.grey});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.3),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 4),
      ),
      child: Center(
        child: Icon(Icons.pets, size: size * 0.6, color: color),
      ),
    );
  }
}
