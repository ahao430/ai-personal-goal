import 'package:flutter/material.dart';

/// 全局暖色调调色板。
///
/// 以日落橙为主色，珊瑚红 / 琥珀金 / 蜜桃粉为辅助色，
/// 不同功能区块使用不同的暖色，避免整屏一个颜色。
abstract final class AppPalette {
  /// 主色：日落橙（目标 / 主操作）。
  static const Color sunsetOrange = Color(0xFFFF6B35);

  /// 珊瑚红（进行中 / 强调）。
  static const Color coral = Color(0xFFFF5A5F);

  /// 琥珀金（成就 / 指标）。
  static const Color amber = Color(0xFFFFB020);

  /// 蜜桃粉（柔和信息）。
  static const Color peach = Color(0xFFFFA07A);

  /// 暖棕（正文 / 深色文字）。
  static const Color warmBrown = Color(0xFF4A2C2A);

  /// 奶油底（浅背景）。
  static const Color cream = Color(0xFFFFF4EC);

  /// 供 Material 3 使用的种子色（生成整套暖色 scheme）。
  static const Color seed = Color(0xFFFF6B35);

  /// 卡片底图资源（不同暖色）。
  static const String cardBgOrange = 'assets/images/card_bg_orange.png';
  static const String cardBgCoral = 'assets/images/card_bg_coral.png';
  static const String cardBgAmber = 'assets/images/card_bg_amber.png';
}
