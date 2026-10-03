import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../../core/config/app_palette.dart';
import '../../domain/ai/ai_provider_template.dart';

/// 供应商模板的图标与暖色（展示层映射，domain 不依赖图标库）。

IconData providerTemplateIcon(String templateId) {
  switch (templateId) {
    case 'zhipu':
      return FontAwesomeIcons.bolt;
    case 'openai':
      return FontAwesomeIcons.circleNodes;
    case 'anthropic':
      return FontAwesomeIcons.crow;
    case 'deepseek':
      return FontAwesomeIcons.fish;
    case 'moonshot':
      return FontAwesomeIcons.moon;
    case 'qwen':
      return FontAwesomeIcons.sun;
    default:
      return FontAwesomeIcons.wandMagicSparkles;
  }
}

Color providerTemplateColor(String templateId) {
  switch (templateId) {
    case 'zhipu':
      return AppPalette.sunsetOrange;
    case 'openai':
      return AppPalette.amber;
    case 'anthropic':
      return AppPalette.coral;
    case 'deepseek':
      return AppPalette.peach;
    case 'moonshot':
      return const Color(0xFFE8756A);
    case 'qwen':
      return const Color(0xFFE8A33D);
    default:
      return AppPalette.warmBrown;
  }
}

/// 按 Base URL 反推模板图标（用于已保存的供应商行）。
IconData providerIconOf(String? baseUrl) {
  if (baseUrl == null) return FontAwesomeIcons.robot;
  final match = kAiProviderTemplates
      .where((t) => t.baseUrl != null && baseUrl.startsWith(t.baseUrl!))
      .toList();
  if (match.isEmpty) return FontAwesomeIcons.robot;
  return providerTemplateIcon(match.first.id);
}

/// 已配置供应商列表行的循环暖色。
Color providerRowColor(int index) {
  const colors = [
    AppPalette.sunsetOrange,
    AppPalette.coral,
    AppPalette.amber,
    AppPalette.peach,
  ];
  return colors[index % colors.length];
}
