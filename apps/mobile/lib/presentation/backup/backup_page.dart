import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../application/backup_service.dart';
import '../../core/config/app_palette.dart';
import '../../core/motion/motion.dart';
import '../providers.dart';
import '../restart_widget.dart';

/// 备份与同步：本地导入导出 + WebDAV（坚果云模板）。
class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  WebdavConfig _config = const WebdavConfig();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config =
        await ref.read(servicesProvider).backupService.webdavConfig();
    if (!mounted) return;
    setState(() => _config = config);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('操作失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── 本地 ────────────────────────────────────────────────

  Future<void> _export() => _run(() async {
        final path =
            await ref.read(servicesProvider).backupService.exportToTemp();
        if (!mounted) return;
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(path, mimeType: 'application/octet-stream')],
            subject: 'AI Goal 备份',
          ),
        );
      });

  Future<void> _import() => _run(() async {
        final picked = await FilePicker.pickFiles();
        final file = picked.single;
        if (file.path == null) return;
        await _confirmAndApply(
          () async => await ref
              .read(servicesProvider)
              .backupService
              .validate(file.path!),
          '导入将用备份文件覆盖当前全部数据，且不可撤销。继续吗？',
        );
      });

  // ── WebDAV ──────────────────────────────────────────────

  Future<void> _testWebdav() => _run(() async {
        final error = await ref
            .read(servicesProvider)
            .backupService
            .testWebdav(_config);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error ?? '连接成功，探针已写入 ${_config.remoteDir}'),
        ));
      });

  Future<void> _backupNow() => _run(() async {
        await ref.read(servicesProvider).backupService.saveWebdavConfig(_config);
        await ref.read(servicesProvider).backupService.backupToWebdav();
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已备份到 WebDAV')));
      });

  Future<void> _restoreFromWebdav() => _run(() async {
        await _confirmAndApply(
          () async =>
              await ref.read(servicesProvider).backupService.fetchLatestBackup(),
          '将下载云端最新备份并覆盖当前全部数据，且不可撤销。继续吗？',
        );
      });

  /// 确认 → 校验 → 展示清单 → 应用 → 重启。
  Future<void> _confirmAndApply(
    Future<ValidatedBackup> Function() validate,
    String warning,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认导入'),
        content: Text(warning),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final backup = await validate();
    if (!mounted) return;
    // ignore: use_build_context_synchronously（已 mounted 检查）
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('备份信息'),
        content: Text(
          '导出时间：${_fmt(backup.manifest.exportedAt)}\n'
          'schema 版本：${backup.manifest.schemaVersion}\n\n'
          '点击「导入并重启」后应用将重启。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('导入并重启'),
          ),
        ],
      ),
    );

    await ref.read(servicesProvider).backupService.apply(backup);
    if (!mounted) return;
    RestartWidget.restart(context);
  }

  Future<void> _editWebdav() async {
    final config = await _configDialog(_config);
    if (config == null) return;
    await ref.read(servicesProvider).backupService.saveWebdavConfig(config);
    setState(() => _config = config);
  }

  Future<WebdavConfig?> _configDialog(WebdavConfig current) {
    final isJianguoyun = current.baseUrl == WebdavConfig.jianguoyun;
    final url = TextEditingController(text: current.baseUrl);
    final user = TextEditingController(text: current.username);
    final pass = TextEditingController(text: current.password);
    final dir = TextEditingController(text: current.remoteDir);
    var template = isJianguoyun ? 'jianguoyun' : 'custom';

    return showDialog<WebdavConfig>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) => AlertDialog(
          title: const Text('WebDAV 配置'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('坚果云'),
                      selected: template == 'jianguoyun',
                      onSelected: (_) => setDialog(() {
                        template = 'jianguoyun';
                        url.text = WebdavConfig.jianguoyun;
                      }),
                    ),
                    ChoiceChip(
                      label: const Text('自定义'),
                      selected: template == 'custom',
                      onSelected: (_) => setDialog(() => template = 'custom'),
                    ),
                  ],
                ),
                if (template == 'jianguoyun') ...[
                  const SizedBox(height: 8),
                  Text(
                    '坚果云：用户名 = 账户邮箱；密码 = 网页端「账户信息 → 安全选项」'
                    '生成的应用密码（不是登录密码）。',
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: url,
                  decoration: const InputDecoration(
                      labelText: '服务器地址', hintText: 'https://…/dav'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: user,
                  decoration: const InputDecoration(labelText: '用户名 / 邮箱'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: pass,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: '密码 / 应用密码'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: dir,
                  decoration: const InputDecoration(
                    labelText: '备份目录',
                    hintText: '/ai-goal-backup',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                current
                    .copyWith(
                      baseUrl: url.text.trim(),
                      username: user.text.trim(),
                      password: pass.text,
                      remoteDir:
                          dir.text.trim().isEmpty ? '/ai-goal-backup' : dir.text.trim(),
                    ),
              ),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final configured = _config.isComplete;
    return Scaffold(
      appBar: AppBar(title: const Text('备份与同步')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: MotionEffects.staggerIn([
          _group(theme, '本地备份', [
            ListTile(
              leading: const FaIcon(FontAwesomeIcons.fileExport,
                  size: 18, color: AppPalette.sunsetOrange),
              title: const Text('导出数据文件'),
              subtitle: const Text('生成 .aigoal 备份包，分享保存到任意位置'),
              trailing: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const FaIcon(FontAwesomeIcons.chevronRight, size: 14),
              onTap: _busy ? null : _export,
            ),
            ListTile(
              leading: const FaIcon(FontAwesomeIcons.fileImport,
                  size: 18, color: AppPalette.amber),
              title: const Text('导入数据文件'),
              subtitle: const Text('从 .aigoal 备份包恢复（覆盖当前数据）'),
              trailing: const FaIcon(FontAwesomeIcons.chevronRight, size: 14),
              onTap: _busy ? null : _import,
            ),
          ]),
          const SizedBox(height: 8),
          _group(theme, 'WebDAV 云备份', [
            ListTile(
              leading: const FaIcon(FontAwesomeIcons.cloud,
                  size: 18, color: AppPalette.coral),
              title: Text(_config.isComplete
                  ? '已配置（${_config.baseUrl.contains('jianguoyun') ? '坚果云' : '自定义'}）'
                  : '未配置'),
              subtitle: Text(
                configured
                    ? '${_config.username} · ${_config.remoteDir}'
                    : '支持坚果云 / 任意 WebDAV（Nextcloud、InfiniCloud 等）',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const FaIcon(FontAwesomeIcons.penToSquare, size: 15),
              onTap: _editWebdav,
            ),
            SwitchListTile(
              secondary: const FaIcon(FontAwesomeIcons.clockRotateLeft,
                  size: 18, color: AppPalette.peach),
              title: const Text('每日自动备份'),
              subtitle: const Text('每天首次打开 App 时自动上传'),
              value: _config.autoDaily,
              onChanged: (v) async {
                final next = _config.copyWith(autoDaily: v);
                await ref
                    .read(servicesProvider)
                    .backupService
                    .saveWebdavConfig(next);
                setState(() => _config = next);
              },
            ),
            ListTile(
              leading: const FaIcon(FontAwesomeIcons.plugCircleCheck,
                  size: 18, color: AppPalette.sunsetOrange),
              title: const Text('测试连接'),
              enabled: configured && !_busy,
              onTap: _testWebdav,
            ),
            ListTile(
              leading: const FaIcon(FontAwesomeIcons.cloudArrowUp,
                  size: 18, color: AppPalette.amber),
              title: const Text('立即备份'),
              enabled: configured && !_busy,
              onTap: _backupNow,
            ),
            ListTile(
              leading: const FaIcon(FontAwesomeIcons.cloudArrowDown,
                  size: 18, color: AppPalette.coral),
              title: const Text('从云端恢复'),
              subtitle: const Text('下载 latest.aigoal 并覆盖当前数据'),
              enabled: configured && !_busy,
              onTap: _restoreFromWebdav,
            ),
          ]),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '备份包 = manifest + SQLite 完整快照（VACUUM INTO 一致性导出）。'
              '云端保留 latest（每次覆盖）与 history/（按时间追加）两份。'
              '所有数据仍只在本机与你的 WebDAV 网盘，App 不经过任何自有服务器。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppPalette.warmBrown.withValues(alpha: 0.55),
                height: 1.7,
              ),
            ),
          ),
        ]),
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

  static String _fmt(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
