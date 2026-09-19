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

  /// Very narrow phones (e.g. 320px logical width) need tighter stacking.
  static const double compactBreakpoint = 360;

  static const double minScreenPadding = 12;

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= breakpoint;

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < compactBreakpoint;

  /// Horizontal padding that respects display cutouts / system insets.
  static EdgeInsets screenPadding(BuildContext context) {
    final inset = MediaQuery.paddingOf(context);
    return EdgeInsets.fromLTRB(
      inset.left + minScreenPadding,
      minScreenPadding,
      inset.right + minScreenPadding,
      minScreenPadding,
    );
  }

  /// Max width for login / narrow forms — never wider than the screen.
  static double formMaxWidth(BuildContext context, {double cap = 400}) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = screenPadding(context).horizontal;
    final available = width - horizontal;
    if (available <= 0) return cap;
    return available < cap ? available : cap;
  }
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

/// For screens that are a single column of content (rates, history,
/// opening weight, customer/supplier master) — on desktop this keeps
/// the exact same phone-width content but centers it, instead of
/// stretching form fields and list tiles uncomfortably across a wide
/// monitor. Wrap the existing ListView/body in this and nothing else
/// needs to change.
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
