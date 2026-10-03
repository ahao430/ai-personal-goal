/// 动效时长。页面代码不允许自行定义 duration —— 一律从这里取。
abstract final class AppMotion {
  /// 微反馈（勾选、高亮变化）。
  static const Duration instant = Duration(milliseconds: 100);

  /// 快速过渡（小元素、退出）。
  static const Duration fast = Duration(milliseconds: 160);

  /// 常规动效（入场、进度、展开）。
  static const Duration normal = Duration(milliseconds: 240);

  /// 强调动效（大卡片、页面级）。
  static const Duration slow = Duration(milliseconds: 360);

  /// 页面路由切换。
  static const Duration page = Duration(milliseconds: 300);

  /// 列表 stagger 的默认间隔。
  static const Duration staggerInterval = Duration(milliseconds: 56);
}
