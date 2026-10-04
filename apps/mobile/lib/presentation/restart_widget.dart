import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/app_services.dart';
import 'app.dart';
import 'providers.dart';

/// 重启容器：导入备份替换数据库后，重建 AppServices 与整棵树。
///
/// AppServices 在 main 创建并 override 进 ProviderScope；本组件持有
/// 当前实例，[restart] 会重新 bootstrap、以新 key 重建 ProviderScope
/// （Riverpod 全部状态随之重建）。
class RestartWidget extends StatefulWidget {
  const RestartWidget({super.key, required this.initialServices});

  final AppServices initialServices;

  /// 触发应用级重启（重建 services + UI）。
  static void restart(BuildContext context) =>
      context.findAncestorStateOfType<_RestartWidgetState>()?.restart();

  @override
  State<RestartWidget> createState() => _RestartWidgetState();
}

class _RestartWidgetState extends State<RestartWidget> {
  late AppServices _services = widget.initialServices;
  Key _key = UniqueKey();

  @override
  void initState() {
    super.initState();
    // 启动即触发每日自动 WebDAV 备份（未开启/已备份/失败都静默）
    // 与通知平台的引导。
    unawaited(_services.backupService.autoBackupIfDue());
    unawaited(_services.notificationScheduler.bootstrap());
  }

  Future<void> restart() async {
    final services = await AppServices.bootstrap();
    if (!mounted) return;
    setState(() {
      _services = services;
      _key = UniqueKey();
    });
    unawaited(services.backupService.autoBackupIfDue());
    unawaited(services.notificationScheduler.bootstrap());
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      key: _key,
      overrides: [servicesProvider.overrideWithValue(_services)],
      child: const AiGoalApp(),
    );
  }
}
