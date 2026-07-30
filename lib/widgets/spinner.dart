import 'package:animated_icon/animated_icon.dart';
import 'package:flutter/material.dart';
import 'package:wiyamusic/widgets/wiya_animated_icon.dart';

class Spinner extends StatelessWidget {
  const Spinner({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: WiyaAnimatedIcon(
        icon: AnimateIcons.loading3,
        size: size,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}
