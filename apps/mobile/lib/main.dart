import 'package:flutter/material.dart';

import 'application/app_services.dart';
import 'presentation/restart_widget.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final services = await AppServices.bootstrap();

  // 启动副作用（通知引导 / 每日自动备份）由 RestartWidget 统一触发，
  // 导入备份重启后也会重新执行。
  runApp(RestartWidget(initialServices: services));
}
