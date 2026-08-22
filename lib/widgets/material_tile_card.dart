import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Card that can host [ListTile]s without hiding ink/splash.
class MaterialTileCard extends StatelessWidget {
  const MaterialTileCard({
    super.key,
    required this.child,
    this.margin,
    this.radius = 8,
  });

  final Widget child;
  final EdgeInsetsGeometry? margin;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final card = Material(
      color: AppColors.cardWhite,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: const BorderSide(color: AppColors.border),
      ),
      child: child,
    );
    if (margin == null) return card;
    return Padding(padding: margin!, child: card);
  }
}
