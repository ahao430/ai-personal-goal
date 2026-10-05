import 'package:flutter/material.dart';

import 'app_curves.dart';
import 'app_motion.dart';

/// 底部导航 Tab 切换动效：新页「从下方浮起」进入。
///
/// 动画作用在 [IndexedStack] 外层的 transform 上 —— 子树 element 不重建，
/// 各 Tab 的滚动位置与页面状态完整保留（这是不用 AnimatedSwitcher 的原因）。
///
/// 观感（Material fade-through 变体）：淡入在前 60% 时间轴完成，
/// 位移（上浮 18px）与缩放（0.97 → 1，底部对齐）用 switchIn 强调曲线收尾。
class MotionTabView extends StatefulWidget {
  const MotionTabView({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  State<MotionTabView> createState() => _MotionTabViewState();
}

class _MotionTabViewState extends State<MotionTabView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.slow,
  );

  late final CurvedAnimation _move = CurvedAnimation(
    parent: _controller,
    curve: AppCurves.switchIn,
  );

  /// 淡入分段：前 60% 完成，避免与位移全程叠加显得拖沓。
  static const Interval _fade = Interval(0, 0.6, curve: AppCurves.standard);

  @override
  void initState() {
    super.initState();
    _controller.value = 1; // 首帧不播（页面有自己的 stagger 入场）
  }

  @override
  void didUpdateWidget(MotionTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _move.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: IndexedStack(index: widget.index, children: widget.children),
      builder: (context, child) {
        final t = _move.value;
        if (_controller.isCompleted) return child!;
        return Opacity(
          opacity: _fade.transform(_controller.value),
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - t)),
            child: Transform.scale(
              scale: 0.97 + 0.03 * t,
              alignment: Alignment.bottomCenter,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
