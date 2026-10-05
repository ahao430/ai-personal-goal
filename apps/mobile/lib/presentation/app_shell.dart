import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../core/config/app_palette.dart';
import '../core/motion/motion.dart';
import '../core/notifications/reminder_platform.dart';
import 'goal_detail/goal_detail_page.dart';
import 'goals/goals_page.dart';
import 'home/home_page.dart';
import 'profile/profile_page.dart';
import 'providers.dart';

/// 底部导航外壳：首页 / 目标 / 我的（plan.md §28）。
/// 不单独设置 Chat Tab —— 对话入口随 P4 分散到各页面的上下文位置。
/// 通知点击（ReminderAction.open）深链到目标详情。
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;
  StreamSubscription<ReminderEvent>? _reminderSub;

  @override
  void initState() {
    super.initState();
    _reminderSub = ref
        .read(servicesProvider)
        .notificationScheduler
        .events
        .where((e) => e.action == ReminderAction.open)
        .listen(_openGoal);
  }

  void _openGoal(ReminderEvent event) {
    final goalId = event.goalId;
    if (goalId == null || !mounted) return;
    pushMotion(context, GoalDetailPage(goalId: goalId));
  }

  @override
  void dispose() {
    unawaited(_reminderSub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MotionTabView(
        index: _index,
        children: const [HomePage(), GoalsPage(), ProfilePage()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: const Color(0xFFFFFBF7),
        indicatorColor: const Color(0xFFFFD1B8),
        destinations: const [
          NavigationDestination(
            icon: FaIcon(FontAwesomeIcons.house, size: 20),
            selectedIcon: FaIcon(FontAwesomeIcons.house, size: 20,
                color: AppPalette.sunsetOrange),
            label: '首页',
          ),
          NavigationDestination(
            icon: FaIcon(FontAwesomeIcons.bullseye, size: 20),
            selectedIcon: FaIcon(FontAwesomeIcons.bullseye, size: 20,
                color: AppPalette.sunsetOrange),
            label: '目标',
          ),
          NavigationDestination(
            icon: FaIcon(FontAwesomeIcons.user, size: 20),
            selectedIcon: FaIcon(FontAwesomeIcons.user, size: 20,
                color: AppPalette.sunsetOrange),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
