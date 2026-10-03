import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../application/ai_provider_service.dart';
import '../../application/app_services.dart';
import '../../core/config/app_palette.dart';
import '../../core/motion/motion.dart';
import '../../domain/ai/ai_model_info.dart';
import '../../domain/ai/ai_provider.dart';
import '../../domain/ai/default_model.dart';
import 'provider_edit_page.dart';
import 'provider_icons.dart';

/// 设置页：AI 供应商管理 与 默认模型 选择（两块分开配置）。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.services});

  final AppServices services;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  List<AiProvider> _providers = [];
  DefaultModelSelection? _defaultModel;
  String? _selectedProviderId;
  List<AiModelInfo> _models = [];
  bool _loading = true;
  bool _fetchingModels = false;
  bool _testingModel = false;

  /// 上次测试结果：null = 未测；(ok, 文本, 耗时ms)
  (bool, String, int)? _testResult;

  AiProviderService get _service => widget.services.aiProviderService;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final providers = await _service.allProviders();
    final defaultModel = await _service.defaultModelSelection();
    if (!mounted) return;
    setState(() {
      _providers = providers;
      _defaultModel = defaultModel;
      _loading = false;
      // 默认选中：默认模型所在供应商 → 第一个可用供应商。
      if (_selectedProviderId == null ||
          !providers.any((p) => p.id == _selectedProviderId)) {
        _selectedProviderId = defaultModel?.providerId ??
            (providers.isNotEmpty ? providers.first.id : null);
      }
    });
    if (_selectedProviderId != null) {
      await _reloadModels();
    } else {
      setState(() => _models = []);
    }
  }

  Future<void> _reloadModels() async {
    final providerId = _selectedProviderId;
    if (providerId == null) return;
    final models = await _service.cachedModels(providerId);
    if (!mounted) return;
    setState(() => _models = models);
  }

  Future<void> _fetchModels() async {
    final providerId = _selectedProviderId;
    if (providerId == null || _fetchingModels) return;
    setState(() => _fetchingModels = true);
    try {
      final models = await _service.fetchAndCacheModels(providerId);
      if (mounted) setState(() => _models = models);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _fetchingModels = false);
    }
  }

  Future<void> _openProviderEdit([AiProvider? existing]) async {
    final changed = await pushMotion<bool>(
      context,
      ProviderEditPage(service: _service, existing: existing),
    );
    if (changed == true) await _reload();
  }

  Future<void> _confirmDeleteProvider(AiProvider provider) async {
    final isDefault = _defaultModel?.providerId == provider.id;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除「${provider.name}」？'),
        content: Text(
          isDefault ? '该供应商是当前默认模型的提供方，删除后默认模型设置也会被清除。' : '其缓存的模型列表将一并删除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _service.deleteProvider(provider.id);
    if (!mounted) return;
    setState(() => _selectedProviderId = null);
    await _reload();
  }

  Future<void> _addManualModel() async {
    final providerId = _selectedProviderId;
    if (providerId == null) return;
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('手动添加模型'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '模型 ID',
            hintText: '如 glm-4.6 / gpt-4o / claude-sonnet-4-20250514',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    final modelId = controller.text.trim();
    controller.dispose();
    if (confirmed != true || modelId.isEmpty) return;
    await _service.addManualModel(providerId, modelId);
    await _reloadModels();
  }

  Future<void> _onProviderChanged(String? providerId) async {
    if (providerId == null) return;
    setState(() => _selectedProviderId = providerId);
    await _reloadModels();
  }

  Future<void> _onModelChanged(String? modelId) async {
    final providerId = _selectedProviderId;
    if (providerId == null || modelId == null) return;
    await _service.setDefaultModel(providerId, modelId);
    if (!mounted) return;
    setState(() {
      _defaultModel = DefaultModelSelection(providerId: providerId, modelId: modelId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _providersHeader(theme),
          const SizedBox(height: 8),
          if (_providers.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '尚未配置 AI 供应商。点击右上角 + 从模板快速添加（智谱 / OpenAI / Claude / DeepSeek / Kimi…），或完全自定义 Base URL 与 Key。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            for (final provider in _providers)
              _providerTile(theme, provider),
          const SizedBox(height: 24),
          _defaultModelSection(theme),
        ],
      ),
    );
  }

  Widget _providersHeader(ThemeData theme) {
    return Row(
      children: [
        const FaIcon(
          FontAwesomeIcons.robot,
          size: 18,
          color: AppPalette.sunsetOrange,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text('AI 供应商', style: theme.textTheme.titleMedium)),
        IconButton.filledTonal(
          onPressed: () => _openProviderEdit(),
          icon: const FaIcon(FontAwesomeIcons.plus, size: 16),
          tooltip: '添加供应商',
        ),
      ],
    );
  }

  Widget _providerTile(ThemeData theme, AiProvider provider) {
    final isDefault = _defaultModel?.providerId == provider.id;
    final index = _providers.indexOf(provider);
    final tint = providerRowColor(index < 0 ? 0 : index);
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: tint.withValues(alpha: 0.15),
          child: FaIcon(providerIconOf(provider.baseUrl), color: tint, size: 18),
        ),
        title: Row(
          children: [
            Flexible(child: Text(provider.name, overflow: TextOverflow.ellipsis)),
            if (isDefault) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '默认',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          '${provider.baseUrl}\n'
          '${provider.maskedApiKey == null ? '未设置 Key' : 'Key ${provider.maskedApiKey}'} · '
          '${provider.apiStyle == ApiStyle.openaiCompatible ? 'OpenAI 兼容' : 'Anthropic'}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: provider.enabled,
              onChanged: (v) async {
                await _service.setProviderEnabled(provider.id, v);
                await _reload();
              },
            ),
            PopupMenuButton<String>(
              onSelected: (action) {
                if (action == 'edit') {
                  _openProviderEdit(provider);
                } else if (action == 'delete') {
                  _confirmDeleteProvider(provider);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('编辑')),
                PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
          ],
        ),
        onTap: () => _openProviderEdit(provider),
      ),
    );
  }

  Future<void> _testModel(String? modelId) async {
    if (modelId == null || _testingModel) return;
    setState(() {
      _testingModel = true;
      _testResult = null;
    });
    try {
      final (text, elapsed) =
          await _service.testModel(_selectedProviderId!, modelId);
      if (!mounted) return;
      setState(() => _testResult = (true, text, elapsed));
    } catch (e) {
      if (!mounted) return;
      setState(() => _testResult = (false, e.toString(), 0));
    } finally {
      if (mounted) setState(() => _testingModel = false);
    }
  }

  Widget _defaultModelSection(ThemeData theme) {
    final enabledProviders =
        _providers.where((p) => p.enabled).toList(growable: false);
    final selectedProvider = enabledProviders
        .where((p) => p.id == _selectedProviderId)
        .firstOrNull;
    final selectedModelId =
        (_defaultModel?.providerId == _selectedProviderId && _models.any(
              (m) => m.modelId == _defaultModel!.modelId,
            ))
        ? _defaultModel!.modelId
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const FaIcon(
              FontAwesomeIcons.wandMagicSparkles,
              size: 18,
              color: AppPalette.amber,
            ),
            const SizedBox(width: 8),
            Text('默认模型', style: theme.textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'AI 规划与分析将默认使用该模型；可与供应商分开随时切换。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        if (enabledProviders.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '先在上方添加并启用一个供应商，再选择默认模型。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else ...[
          DropdownButtonFormField<String>(
            key: ValueKey('provider-${selectedProvider?.id}'),
            initialValue: selectedProvider?.id,
            decoration: const InputDecoration(
              labelText: '供应商',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final p in enabledProviders)
                DropdownMenuItem(value: p.id, child: Text(p.name)),
            ],
            onChanged: _onProviderChanged,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('model-$_selectedProviderId-$selectedModelId'),
            initialValue: selectedModelId,
            decoration: InputDecoration(
              labelText: '模型',
              border: const OutlineInputBorder(),
              helperText: _models.isEmpty ? '暂无模型，点击「获取模型列表」拉取' : null,
            ),
            items: [
              for (final m in _models)
                DropdownMenuItem(value: m.modelId, child: Text(m.label)),
            ],
            onChanged: _onModelChanged,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: _fetchingModels ? null : _fetchModels,
                icon: _fetchingModels
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const FaIcon(FontAwesomeIcons.cloudArrowDown, size: 16),
                label: Text(_fetchingModels ? '获取中…' : '获取模型列表'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _addManualModel,
                icon: const FaIcon(FontAwesomeIcons.penToSquare, size: 14),
                label: const Text('手动添加'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: selectedModelId == null || _testingModel
                    ? null
                    : () => _testModel(selectedModelId),
                icon: _testingModel
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const FaIcon(FontAwesomeIcons.towerBroadcast, size: 15),
                label: Text(_testingModel ? '测试中…' : '测试对话'),
              ),
            ],
          ),
          if (_testResult case final result?) ...[
            const SizedBox(height: 8),
            _testResultCard(theme, result),
          ],
        ],
      ],
    );
  }

  /// 测试结果内联卡片：成功绿色（回复摘要 + 耗时），失败红色（错误原因）。
  Widget _testResultCard(ThemeData theme, (bool, String, int) result) {
    final (ok, text, elapsed) = result;
    final color = ok ? const Color(0xFF3E8E5A) : AppPalette.coral;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FaIcon(
            ok
                ? FontAwesomeIcons.circleCheck
                : FontAwesomeIcons.circleExclamation,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              ok ? '连接成功（${elapsed}ms）：$text' : '连接失败：$text',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
