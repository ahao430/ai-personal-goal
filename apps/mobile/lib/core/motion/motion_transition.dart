import 'package:flutter/material.dart';

import 'app_curves.dart';
import 'app_motion.dart';

/// 统一页面过渡：分段淡入 + 轻微上滑 + 轻微缩放（emphasized 组合）。
///
/// 替代默认 MaterialPageRoute；Hero 共享元素过渡在其上正常工作。
/// 观感：新页从前方 4% 处带缩放「浮上来」，淡入先行完成（前 70%），
/// 位移与缩放用强调曲线收尾；退出反向快速离场。
class MotionPageRoute<T> extends PageRouteBuilder<T> {
  MotionPageRoute({required WidgetBuilder builder, super.settings})
      : super(
          transitionDuration: AppMotion.page,
          reverseTransitionDuration: AppMotion.fast,
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final move = CurvedAnimation(
              parent: animation,
              curve: AppCurves.switchIn,
              reverseCurve: AppCurves.switchOut,
            );
            // 淡入在时间轴前段完成，避免与新页内容滑动叠加显得拖沓。
            final fade = CurvedAnimation(
              parent: animation,
              curve: const Interval(0, 0.7, curve: AppCurves.standard),
              reverseCurve: const Interval(0.3, 1, curve: AppCurves.exit),
            );
            return FadeTransition(
              opacity: fade,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.04),
                  end: Offset.zero,
                ).animate(move),
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.96, end: 1).animate(move),
                  child: child,
                ),
              ),
            );
          },
        );
}

/// push 便捷方法：所有页面跳转统一入口。
Future<T?> pushMotion<T>(BuildContext context, Widget page) {
  return Navigator.of(context).push<T>(
    MotionPageRoute<T>(builder: (_) => page),
  );
}
