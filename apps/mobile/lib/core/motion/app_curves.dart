import 'package:flutter/animation.dart';

/// 动效曲线。页面代码不允许自行指定 curve —— 一律从这里取。
abstract final class AppCurves {
  /// 标准：进入 / 增长（快出缓停）。
  static const Cubic standard = Curves.easeOutCubic;

  /// 强调：完成、弹出（轻微过冲）。
  static const Cubic emphasized = Curves.easeOutBack;

  /// 退出 / 收起。
  static const Cubic exit = Curves.easeInCubic;

  /// 数字滚动等长时间插值。
  static const Cubic count = Curves.easeOut;

  /// 切换动效 · 进入段（Material emphasized decelerate）：
  /// 快速启动、长尾缓停，用于页面/Tab 切换的 incoming。
  static const Cubic switchIn = Cubic(0.05, 0.7, 0.1, 1.0);

  /// 切换动效 · 退出段（Material emphasized accelerate）：
  /// 缓慢启动、快速离场，用于切换的 outgoing。
  static const Cubic switchOut = Cubic(0.3, 0.0, 0.8, 0.15);
}
