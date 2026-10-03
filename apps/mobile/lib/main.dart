import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/app_services.dart';
import 'presentation/app.dart';
import 'presentation/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final services = await AppServices.bootstrap();

  // 通知平台引导（初始化 / 权限 / 补排 / 动作事件）。失败不阻塞启动。
  unawaited(services.notificationScheduler.bootstrap());

  runApp(
    ProviderScope(
      overrides: [servicesProvider.overrideWithValue(services)],
      child: const AiGoalApp(),
    ),
  );
}
