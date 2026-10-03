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
}
