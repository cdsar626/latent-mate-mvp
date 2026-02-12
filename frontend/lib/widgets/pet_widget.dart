import 'package:flutter/material.dart';

class PetWidget extends StatelessWidget {
  final double size;

  const PetWidget({super.key, this.size = 100});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Icon(Icons.pets, size: size * 0.6, color: Colors.grey[600]),
      ),
    );
  }
}
