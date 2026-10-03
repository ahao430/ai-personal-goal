import 'package:flutter/material.dart';

import 'app_curves.dart';
import 'app_motion.dart';

/// 统一页面过渡：淡入 + 轻微上滑（fade-through 风格）。
///
/// 替代默认 MaterialPageRoute；Hero 共享元素过渡在其上正常工作。
class MotionPageRoute<T> extends PageRouteBuilder<T> {
  MotionPageRoute({required WidgetBuilder builder, super.settings})
      : super(
          transitionDuration: AppMotion.page,
          reverseTransitionDuration: AppMotion.fast,
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: AppCurves.standard,
              reverseCurve: AppCurves.exit,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.035),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
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
