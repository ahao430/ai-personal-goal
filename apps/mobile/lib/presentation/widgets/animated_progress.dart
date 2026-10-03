import 'package:flutter/material.dart';

import '../../core/config/app_palette.dart';
import '../../core/motion/motion.dart';

/// 动画进度条：值变化时平滑增长（含首次入场的从 0 生长）。
class AnimatedProgressBar extends StatelessWidget {
  const AnimatedProgressBar({
    super.key,
    required this.value,
    this.height = 8,
    this.color = AppPalette.sunsetOrange,
    this.trackColor,
  }) : assert(value >= 0 && value <= 100);

  /// 0 ~ 100。
  final double value;
  final double height;
  final Color color;
  final Color? trackColor;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value / 100),
        duration: AppMotion.slow,
        curve: AppCurves.standard,
        builder: (context, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: height,
          backgroundColor:
              trackColor ?? Colors.white.withValues(alpha: 0.6),
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ),
    );
  }
}

/// 数字滚动百分比：72 → 73 时数字连续滚动，与进度条同步使用。
class AnimatedPercent extends StatelessWidget {
  const AnimatedPercent({
    super.key,
    required this.value,
    this.style,
    this.color = AppPalette.sunsetOrange,
  }) : assert(value >= 0 && value <= 100);

  final double value;
  final TextStyle? style;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.titleMedium;
    return TweenAnimationBuilder<int>(
      tween: Tween(begin: 0, end: value.round()),
      duration: AppMotion.slow,
      curve: AppCurves.count,
      builder: (context, v, _) => Text(
        '$v%',
        style: (base ?? const TextStyle()).copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
