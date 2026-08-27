import 'package:flutter/material.dart';

/// Practical desktop/mobile layout for a shop till app.
///
/// Nothing here changes font sizes, icon sizes, or paddings — every
/// value already set in a screen file (fontSize: 14, Icon(size: 20),
/// EdgeInsets.all(12), etc.) stays pixel-identical on both platforms.
/// This only decides how content is ARRANGED when there's extra
/// horizontal room (a desktop window), so a shop counter PC puts its
/// screen to use instead of stretching a phone-shaped column across
/// it, or floating it centered in empty space.
class Responsive {
  Responsive._();

  /// Below this width: mobile behavior (single column, full width).
  /// At or above: desktop behavior (side-by-side panels).
  static const double breakpoint = 900;

  static bool isWide(BuildContext context) =>
      MediaQuery.of(context).size.width >= breakpoint;
}

/// Puts `primary` (usually the entry form / main actions) and
/// `secondary` (usually the history/list) side by side on a wide
/// desktop window. On a phone-width screen it falls back to stacking
/// them exactly as before this wrapper existed: primary, then
/// secondary below.
class SplitLayout extends StatelessWidget {
  final Widget primary;
  final Widget secondary;
  final double primaryWidth;
  final double gap;

  const SplitLayout({
    super.key,
    required this.primary,
    required this.secondary,
    this.primaryWidth = 380,
    this.gap = 20,
  });

  @override
  Widget build(BuildContext context) {
    if (!Responsive.isWide(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [primary, const SizedBox(height: 16), secondary],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: primaryWidth, child: primary),
        SizedBox(width: gap),
        Expanded(child: secondary),
      ],
    );
  }
}

/// Form stays pinned on the left (desktop); only the list pane scrolls.
/// On a phone the two panes still stack inside one scroll view.
class WorkbenchLayout extends StatelessWidget {
  final Widget primary;
  final Widget secondary;
  final double primaryWidth;
  final double gap;
  final bool equalSplit;
  final bool disableScroll;

  const WorkbenchLayout({
    super.key,
    required this.primary,
    required this.secondary,
    this.primaryWidth = 380,
    this.gap = 16,
    this.equalSplit = false,
    this.disableScroll = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!Responsive.isWide(context)) {
      if (disableScroll) {
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [primary, const SizedBox(height: 12), secondary],
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [primary, const SizedBox(height: 16), secondary],
      );
    }

    if (equalSplit) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: disableScroll
                  ? primary
                  : SingleChildScrollView(child: primary),
            ),
            SizedBox(width: gap),
            Expanded(
              flex: 2,
              child: SingleChildScrollView(child: secondary),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: primaryWidth,
            child: SingleChildScrollView(child: primary),
          ),
          SizedBox(width: gap),
          Expanded(
            child: SingleChildScrollView(child: secondary),
          ),
        ],
      ),
    );
  }
}

/// For screens that are a single column of content (rates, history,
/// opening weight) — on desktop this keeps the same phone-width column.
class CenteredMaxWidth extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const CenteredMaxWidth({
    super.key,
    required this.child,
    this.maxWidth = 480,
  });

  @override
  Widget build(BuildContext context) {
    if (!Responsive.isWide(context)) return child;
    return Center(
      child: SizedBox(width: maxWidth, child: child),
    );
  }
}
