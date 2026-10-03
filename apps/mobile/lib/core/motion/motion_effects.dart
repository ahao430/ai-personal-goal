import 'package:flutter/widgets.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'app_curves.dart';
import 'app_motion.dart';

/// 基于 flutter_animate 的统一动效预设。
///
/// 页面不要手写 `.fadeIn(duration: ...)` 这类零散参数，
/// 一律使用这里的预设，保证全 App 动画语言一致。
abstract final class MotionEffects {
  /// 单元素入场：淡入 + 轻微上移。
  static Widget entrance(Widget child, {Duration? delay}) => child
      .animate(delay: delay ?? Duration.zero)
      .fadeIn(duration: AppMotion.normal, curve: AppCurves.standard)
      .slideY(begin: 0.06, end: 0, duration: AppMotion.normal, curve: AppCurves.standard);

  /// 列表错位入场：逐项淡入 + 上移。
  static List<Widget> staggerIn(
    List<Widget> children, {
    Duration interval = AppMotion.staggerInterval,
  }) =>
      children
          .animate(interval: interval)
          .fadeIn(duration: AppMotion.normal, curve: AppCurves.standard)
          .slideY(begin: 0.1, end: 0, duration: AppMotion.normal, curve: AppCurves.standard)
          .toList();

  /// 完成 / 达成强调：轻微放大回弹（用于勾选、徽章）。
  static Widget popIn(Widget child) => child
      .animate()
      .scale(
        begin: const Offset(0.6, 0.6),
        end: const Offset(1, 1),
        duration: AppMotion.normal,
        curve: AppCurves.emphasized,
      )
      .fadeIn(duration: AppMotion.fast, curve: AppCurves.standard);
}
