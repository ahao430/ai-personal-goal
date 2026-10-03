import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/config/app_palette.dart';
import '../../core/motion/motion.dart';
import '../../domain/external/data_source.dart';
import '../providers.dart';
import '../settings/settings_page.dart';

/// 我的：设置入口、应用信息。数据源权限（P9）预留展示。
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 52,
                      height: 52,
                      errorBuilder: (_, _, _) => const SizedBox(
                        width: 52,
                        height: 52,
                        child: ColoredBox(color: AppPalette.sunsetOrange),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('AI Goal',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      Text(
                        'AI 驱动的个人目标管理 · Local-first',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppPalette.warmBrown.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _group(theme, '设置', [
            ListTile(
              leading: const FaIcon(FontAwesomeIcons.robot,
                  size: 18, color: AppPalette.sunsetOrange),
              title: const Text('AI 供应商与模型'),
              subtitle: const Text('供应商、API Key、默认模型'),
              trailing: const FaIcon(FontAwesomeIcons.chevronRight, size: 14),
              onTap: () => pushMotion(
                context,
                SettingsPage(services: ref.read(servicesProvider)),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          _group(theme, 'AI 功能', [
            const _DailyReviewTile(),
            const _ReminderTile(),
            const _SearchKeyTile(),
          ]),
          const SizedBox(height: 8),
          _DataSourceGroup(),
          const SizedBox(height: 8),
          _group(theme, '关于', [
            const ListTile(
              leading: FaIcon(FontAwesomeIcons.circleInfo, size: 18),
              title: Text('版本'),
              trailing: Text('0.7.0'),
            ),
            const ListTile(
              leading: FaIcon(FontAwesomeIcons.shieldHalved, size: 18),
              title: Text('隐私'),
              subtitle: Text('所有数据仅存本机 SQLite，不上传任何服务器'),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _group(ThemeData theme, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(title, style: theme.textTheme.titleSmall),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Column(children: children),
        ),
      ],
    );
  }
}

/// 搜索 API 配置（P8）：可选配 Tavily key 提升搜索质量；
/// 未配置时用免 key 的 DuckDuckGo。
class _SearchKeyTile extends ConsumerStatefulWidget {
  const _SearchKeyTile();

  @override
  ConsumerState<_SearchKeyTile> createState() => _SearchKeyTileState();
}

class _SearchKeyTileState extends ConsumerState<_SearchKeyTile> {
  bool _configured = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = await ref
        .read(servicesProvider)
        .searchService
        .tavilyKey();
    if (!mounted) return;
    setState(() => _configured = key != null && key.isNotEmpty);
  }

  Future<void> _edit() async {
    final services = ref.read(servicesProvider);
    final current = await services.searchService.tavilyKey();
    if (!mounted) return;
    final controller = TextEditingController(text: current ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('联网搜索'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '默认使用免 key 的 DuckDuckGo。如需更高质量结果，'
              '可配置 Tavily API Key（tavily.com）。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Tavily API Key（留空则清除）',
                hintText: 'tvly-…',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    await services.searchService.setTavilyKey(controller.text);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const FaIcon(FontAwesomeIcons.globe,
          size: 18, color: AppPalette.sunsetOrange),
      title: const Text('联网搜索'),
      subtitle: Text(_configured
          ? 'Tavily 已配置（失败自动回退 DuckDuckGo）'
          : '使用 DuckDuckGo（可配置 Tavily Key 提升）'),
      trailing: const FaIcon(FontAwesomeIcons.chevronRight, size: 14),
      onTap: _edit,
    );
  }
}

/// 任务提醒开关（P7）：关闭即取消全部已排通知。
class _ReminderTile extends ConsumerStatefulWidget {
  const _ReminderTile();

  @override
  ConsumerState<_ReminderTile> createState() => _ReminderTileState();
}

class _ReminderTileState extends ConsumerState<_ReminderTile> {
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final scheduler = ref.read(servicesProvider).notificationScheduler;
    final value = await scheduler.enabled();
    if (!mounted) return;
    setState(() => _enabled = value);
  }

  Future<void> _toggle(bool value) async {
    setState(() => _enabled = value);
    await ref.read(servicesProvider).notificationScheduler.setEnabled(value);
    if (value) {
      // 重新开启：全量补排。
      await ref.read(servicesProvider).notificationScheduler.syncAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled ?? true;
    return SwitchListTile(
      secondary: const FaIcon(FontAwesomeIcons.bell,
          size: 18, color: AppPalette.coral),
      title: const Text('任务提醒'),
      subtitle: const Text('按计划时间提前 10 分钟通知，可从通知直接完成/延后'),
      value: enabled,
      onChanged: _enabled == null ? null : _toggle,
    );
  }
}

/// 数据与权限（P9）：从 ExternalDataService 注册表动态渲染。
/// 天气可开启 + 配置城市；health/location/calendar 框架就绪、随版本接入。
class _DataSourceGroup extends ConsumerStatefulWidget {
  const _DataSourceGroup();

  @override
  ConsumerState<_DataSourceGroup> createState() => _DataSourceGroupState();
}

class _DataSourceGroupState extends ConsumerState<_DataSourceGroup> {
  final Map<ExternalSource, PermissionStatus> _statuses = {};
  String? _weatherCity;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final services = ref.read(servicesProvider);
    for (final provider in services.externalService.providers) {
      _statuses[provider.source] = await provider.checkPermission();
    }
    final weather = services.externalService.providerOf(ExternalSource.weather)
        as dynamic;
    try {
      final location = await weather.configuredLocation();
      _weatherCity = location?.name as String?;
    } catch (_) {
      _weatherCity = null;
    }
    if (!mounted) return;
    setState(() {});
  }

  IconData _iconOf(ExternalSource source) => switch (source) {
        ExternalSource.health => FontAwesomeIcons.heartPulse,
        ExternalSource.weather => FontAwesomeIcons.cloudSun,
        ExternalSource.location => FontAwesomeIcons.locationDot,
        ExternalSource.calendar => FontAwesomeIcons.calendarDays,
      };

  Color _colorOf(ExternalSource source) => switch (source) {
        ExternalSource.health => AppPalette.coral,
        ExternalSource.weather => AppPalette.amber,
        ExternalSource.location => AppPalette.peach,
        ExternalSource.calendar => AppPalette.sunsetOrange,
      };

  (String, PermissionStatus) _statusLabel(PermissionStatus status) =>
      switch (status) {
        PermissionStatus.granted => ('已授权', PermissionStatus.granted),
        PermissionStatus.requested => ('待版本开放', PermissionStatus.requested),
        PermissionStatus.notRequested => ('未开启', PermissionStatus.notRequested),
        PermissionStatus.denied => ('已拒绝', PermissionStatus.denied),
      };

  Future<void> _onTap(dynamic provider) async {
    final services = ref.read(servicesProvider);
    final source = provider.source;

    if (source == ExternalSource.weather) {
      final status = _statuses[source] ?? PermissionStatus.notRequested;
      if (status == PermissionStatus.granted) {
        await _editWeatherCity();
        return;
      }
      final city = await _askCity(initial: '');
      if (city == null || city.trim().isEmpty) return;
      final weather = services.externalService.providerOf(source) as dynamic;
      try {
        await weather.setLocationByName(city.trim());
        await services.externalService.requestPermission(source);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('配置失败：$e')),
          );
        }
      }
      await _load();
      return;
    }

    // 占位源：记录授权意向（真实系统权限随版本开放）。
    await services.externalService.requestPermission(source);
    await _load();
  }

  Future<void> _editWeatherCity() async {
    final services = ref.read(servicesProvider);
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('天气（${_weatherCity ?? '未配置城市'}）'),
        content: const Text('输入新城市可切换；选择「关闭」停止使用天气数据。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'off'),
            child: const Text('关闭'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'city'),
            child: const Text('换城市'),
          ),
        ],
      ),
    );
    if (action == 'off') {
      await services.externalService.revoke(ExternalSource.weather);
      await _load();
      return;
    }
    if (action == 'city') {
      final city = await _askCity(initial: _weatherCity ?? '');
      if (city == null || city.trim().isEmpty) return;
      final weather =
          services.externalService.providerOf(ExternalSource.weather) as dynamic;
      try {
        await weather.setLocationByName(city.trim());
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('配置失败：$e')),
          );
        }
      }
      await _load();
    }
  }

  Future<String?> _askCity({required String initial}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('配置城市'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '城市名',
            hintText: '如：上海',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final providers = ref.read(servicesProvider).externalService.providers;
    final theme = Theme.of(context);
    return _wrapGroup(
      theme,
      '数据与权限',
      [
        for (final provider in providers)
          ListTile(
            leading: FaIcon(_iconOf(provider.source),
                size: 18, color: _colorOf(provider.source)),
            title: Text(provider.source.displayName),
            subtitle: Text(
              provider.source.description +
                  (provider.source == ExternalSource.weather
                      ? (_weatherCity == null ? '' : ' · $_weatherCity')
                      : ''),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: _statusChip(theme, _statuses[provider.source]),
            onTap: () => _onTap(provider),
          ),
      ],
    );
  }

  Widget _wrapGroup(ThemeData theme, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(title, style: theme.textTheme.titleSmall),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _statusChip(ThemeData theme, PermissionStatus? status) {
    final (label, kind) = _statusLabel(status ?? PermissionStatus.notRequested);
    final color = switch (kind) {
      PermissionStatus.granted => const Color(0xFF3E8E5A),
      PermissionStatus.requested => AppPalette.amber,
      PermissionStatus.denied => AppPalette.coral,
      PermissionStatus.notRequested =>
        AppPalette.warmBrown.withValues(alpha: 0.4),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// 每日 AI 回顾开关（读设置 + 本地状态，切换即生效）。
class _DailyReviewTile extends ConsumerStatefulWidget {
  const _DailyReviewTile();

  @override
  ConsumerState<_DailyReviewTile> createState() => _DailyReviewTileState();
}

class _DailyReviewTileState extends ConsumerState<_DailyReviewTile> {
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final value = await ref.read(servicesProvider).dailyReviewService.enabled();
    if (!mounted) return;
    setState(() => _enabled = value);
  }

  Future<void> _toggle(bool value) async {
    setState(() => _enabled = value);
    await ref.read(servicesProvider).dailyReviewService.setEnabled(value);
    // 开启后立即失效缓存的 null 结果，下次进首页重新生成。
    ref.invalidate(dailyReviewProvider);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled ?? true;
    return SwitchListTile(
      secondary: const FaIcon(FontAwesomeIcons.sun,
          size: 18, color: AppPalette.amber),
      title: const Text('每日 AI 回顾'),
      subtitle: const Text('打开 App 时给一句今日行动指引'),
      value: enabled,
      onChanged: _enabled == null ? null : _toggle,
    );
  }
}
