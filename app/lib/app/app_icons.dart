import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Paths for custom SVG icons that supplement Phosphor.
/// Drop SVG files into assets/icons/ and add a constant here.
///
/// Example:
///   static const pickleball = 'assets/icons/pickleball.svg';
class AppIcons {
  AppIcons._();

  static const String pickleballPaddle = 'assets/icons/pickleball-paddle-fill.svg';
  static const String pickleballCourt = 'assets/icons/pickleball-court-fill.svg';
}

/// Drop-in replacement for [Icon] that renders an SVG asset.
/// Inherits size and color from [IconTheme] automatically.
///
/// Usage:
///   AppIcon(AppIcons.pickleball)
///   AppIcon(AppIcons.pickleball, size: 28, color: scheme.primary)
///
/// Works anywhere [Icon] works, including [FloatingNavDestination].
class AppIcon extends StatelessWidget {
  const AppIcon(this.asset, {super.key, this.size, this.color});

  final String asset;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final resolvedSize = size ?? theme.size ?? 24;
    final resolvedColor = color ?? theme.color;
    return SvgPicture.asset(
      asset,
      width: resolvedSize,
      height: resolvedSize,
      colorFilter: resolvedColor != null
          ? ColorFilter.mode(resolvedColor, BlendMode.srcIn)
          : null,
    );
  }
}
