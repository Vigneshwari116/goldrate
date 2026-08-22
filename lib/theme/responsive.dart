import 'package:flutter/material.dart';

/// Shop-till layout: use the full window, like a real jewellery POS.
class Responsive {
  Responsive._();

  static const double breakpoint = 800;

  static bool isWide(BuildContext context) =>
      MediaQuery.of(context).size.width >= breakpoint;
}

/// Form on the left, list/history on the right — both stretch to fill
/// the window. Stacks on a narrow pane.
class SplitLayout extends StatelessWidget {
  final Widget primary;
  final Widget secondary;
  final int primaryFlex;
  final int secondaryFlex;
  final double gap;

  const SplitLayout({
    super.key,
    required this.primary,
    required this.secondary,
    this.primaryFlex = 5,
    this.secondaryFlex = 6,
    this.gap = 16,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = !constraints.hasBoundedWidth ||
            constraints.maxWidth < Responsive.breakpoint;
        if (stacked) {
          final column = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              primary,
              SizedBox(height: gap),
              secondary,
            ],
          );
          if (constraints.hasBoundedHeight &&
              constraints.maxHeight.isFinite) {
            return SizedBox(
              width: double.infinity,
              child: SingleChildScrollView(child: column),
            );
          }
          return column;
        }

        final fillHeight =
            constraints.hasBoundedHeight && constraints.maxHeight.isFinite;

        Widget pane(Widget child) {
          if (!fillHeight) return child;
          return SingleChildScrollView(
            child: child,
          );
        }

        return SizedBox(
          width: double.infinity,
          height: fillHeight ? constraints.maxHeight : null,
          child: Row(
            crossAxisAlignment: fillHeight
                ? CrossAxisAlignment.stretch
                : CrossAxisAlignment.start,
            children: [
              Expanded(flex: primaryFlex, child: pane(primary)),
              SizedBox(width: gap),
              Expanded(flex: secondaryFlex, child: pane(secondary)),
            ],
          ),
        );
      },
    );
  }
}
