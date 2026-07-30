import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:wiyamusic/theme/design_tokens.dart';

class HomeNeonPlayButton extends StatelessWidget {
  const HomeNeonPlayButton({
    super.key,
    required this.onPressed,
    this.size = 36,
    this.iconSize = 18,
  });

  final VoidCallback onPressed;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Ink(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                WiyaDesign.primaryBright,
                colorScheme.primary,
                WiyaDesign.primaryDeep,
              ],
            ),
            boxShadow: WiyaDesign.softGlow(
              color: colorScheme.primary,
              blur: 16,
              opacity: 0.45,
            ),
          ),
          child: Icon(
            FluentIcons.play_24_filled,
            size: iconSize,
            color: WiyaDesign.onPrimary,
          ),
        ),
      ),
    );
  }
}
