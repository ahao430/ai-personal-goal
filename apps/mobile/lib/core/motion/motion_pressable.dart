import 'package:flutter/material.dart';

import 'app_curves.dart';
import 'app_motion.dart';

/// 按压缩放反馈：按下时整体轻微缩小，松手回弹。
///
/// 用于卡片类可点区域（比水波纹更贴合暖色插画风）。
/// 不带 hit-test 特殊语义 —— 需要无障碍语义时外层自行包 Semantics。
class MotionPressable extends StatefulWidget {
  const MotionPressable({
    super.key,
    required this.onTap,
    required this.child,
    this.enabled = true,
  });

  final VoidCallback? onTap;
  final Widget child;
  final bool enabled;

  @override
  State<MotionPressable> createState() => _MotionPressableState();
}

class _MotionPressableState extends State<MotionPressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: active ? (_) => setState(() => _down = true) : null,
      onTapUp: active ? (_) => setState(() => _down = false) : null,
      onTapCancel: active ? () => setState(() => _down = false) : null,
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1.0,
        duration: _down ? AppMotion.instant : AppMotion.fast,
        curve: _down ? AppCurves.standard : AppCurves.emphasized,
        child: widget.child,
      ),
    );
  }
}
