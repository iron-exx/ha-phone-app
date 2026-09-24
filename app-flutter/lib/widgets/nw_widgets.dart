import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Minimum touch target of every tappable element (Nachtwache: ≥ 48 dp).
const kMinTap = 48.0;

/// Card: `surface` fill, 1 px `stroke`, radius 22 (large cards 26), no shadow.
class NwCard extends StatelessWidget {
  const NwCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = 22,
    this.onTap,
    this.onLongPress,
    this.color,
    this.borderColor,
    this.clip = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? color;
  final Color? borderColor;

  /// Clip the child to the rounded shape (image headers).
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final c = context.nw;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: borderColor ?? c.stroke),
    );
    return Material(
      color: color ?? c.surface,
      shape: shape,
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Fully rounded chip, 32 dp high inside a 48 dp touch target. Selected =
/// blue-soft fill with blue border.
class NwChip extends StatelessWidget {
  const NwChip({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
    this.foreground,
    this.semanticLabel,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  /// Text/icon colour override (e.g. green "bereit").
  final Color? foreground;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.nw;
    final fg = selected ? c.blueOnSoft : (foreground ?? c.text);
    final chip = Container(
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: ShapeDecoration(
        color: selected ? c.blueSoft : c.raised,
        shape: StadiumBorder(side: BorderSide(color: selected ? c.blue : c.stroke)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(label, style: NwType.chip.copyWith(color: fg), overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
    return Semantics(
      button: onTap != null,
      selected: onTap != null ? selected : null,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: onTap == null ? 32 : kMinTap),
          child: Center(widthFactor: 1, child: chip),
        ),
      ),
    );
  }
}

/// Horizontal, scrollable row of filter chips.
class NwChipRow extends StatelessWidget {
  const NwChipRow({super.key, required this.children, this.padding = const EdgeInsets.symmetric(horizontal: 16)});

  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            child,
          ],
        ],
      ),
    );
  }
}

/// Section header: 12/800 upper case, +8 % tracking, `faint`.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(20, 18, 20, 6)});

  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.nw;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title.toUpperCase(), style: NwType.section.copyWith(color: c.faint)),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Page title row: Bricolage 32/800 plus optional round actions.
class PageHeader extends StatelessWidget {
  const PageHeader(this.title, {super.key, this.actions = const []});

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.nw;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: NwType.pageTitle.copyWith(color: c.text), overflow: TextOverflow.ellipsis),
            ),
          ),
          for (final a in actions) ...[const SizedBox(width: 8), a],
        ],
      ),
    );
  }
}

/// Square-ish icon button on `raised`, 48 dp, with a TalkBack label.
class NwIconButton extends StatelessWidget {
  const NwIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.size = kMinTap,
    this.radius = 16,
    this.color,
    this.iconColor,
    this.iconSize = 20,
  });

  final IconData icon;

  /// Tooltip and TalkBack label.
  final String label;
  final VoidCallback? onPressed;
  final double size;
  final double radius;
  final Color? color;
  final Color? iconColor;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final c = context.nw;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: color == null ? BorderSide(color: c.stroke) : BorderSide.none,
    );
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: color ?? c.raised,
          shape: shape,
          child: InkWell(
            customBorder: shape,
            onTap: onPressed,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, size: iconSize, color: iconColor ?? (onPressed == null ? c.faint : c.text)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Red count badge ("3", "99+").
class CountBadge extends StatelessWidget {
  const CountBadge(this.count, {super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.nw;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.end, borderRadius: BorderRadius.circular(9)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: MediaQuery.withNoTextScaling(
              child: Text(
                count > 99 ? '99+' : '$count',
                style: TextStyle(
                  fontFamily: NwFonts.ui,
                  color: c.endInk,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wide pill button (door amber, answer green, blue): 52 dp, radius 16.
class NwPillButton extends StatelessWidget {
  const NwPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.background,
    required this.foreground,
    this.icon,
    this.height = 52,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color background;
  final Color foreground;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        minimumSize: Size(kMinTap, height),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: NwType.button,
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
          Flexible(child: Text(label, textAlign: TextAlign.center)),
        ],
      ),
    );
  }
}
