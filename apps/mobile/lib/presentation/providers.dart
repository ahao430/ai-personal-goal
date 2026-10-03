import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/app_services.dart';
import '../../application/overview_service.dart';
import '../../domain/goal/goal.dart';
/// AppServices 在 main() 中创建并 override 注入。
final servicesProvider = Provider<AppServices>(
  (ref) => throw UnimplementedError('servicesProvider 必须在 main 中 override'),
);

/// 首页聚合视图。
final homeViewProvider = FutureProvider<HomeView>(
  (ref) => ref.watch(servicesProvider).overview.homeView(),
);

/// 目标列表（全部，按更新时间倒序；UI 侧做状态过滤）。
final goalsListProvider = FutureProvider<List<Goal>>(
  (ref) => ref.watch(servicesProvider).goals.findAll(),
);

/// 目标详情。
final goalDetailProvider =
    FutureProvider.autoDispose.family<GoalDetailData, String>(
  (ref, goalId) => ref.watch(servicesProvider).overview.goalDetail(goalId),
);

/// 每日 AI 回顾（null = 未开启 / 未配置 / 生成失败；每天缓存一次）。
final dailyReviewProvider = FutureProvider<String?>(
  (ref) => ref.watch(servicesProvider).dailyReviewService.review(),
);

/// 日历月视图（goalId 为空 = 全部目标）。
final calendarProvider = FutureProvider.autoDispose
    .family<CalendarViewData, ({DateTime month, String? goalId})>(
  (ref, arg) =>
      ref.watch(servicesProvider).overview.calendarView(arg.month, goalId: arg.goalId),
);

/// 任何写操作后调用：让列表 / 首页 / 详情全部重新拉取。
void invalidateAll(WidgetRef ref) {
  ref.invalidate(homeViewProvider);
  ref.invalidate(goalsListProvider);
  // 详情按 family 全量失效
  ref.invalidate(goalDetailProvider);
}
