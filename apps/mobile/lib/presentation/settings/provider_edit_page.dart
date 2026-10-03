import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../application/ai_provider_service.dart';
import '../../domain/ai/ai_provider.dart';
import '../../domain/ai/ai_provider_template.dart';
import '../../domain/entity_ids.dart';
import 'provider_icons.dart';

/// 新增 / 编辑 AI 供应商。
///
/// 新增时提供模板快速选择（智谱 / OpenAI / Claude / DeepSeek / Kimi / 通义 / 自定义），
/// 选中即预填名称、API 风格与 Base URL；所有字段均可继续修改（完全自定义）。
class ProviderEditPage extends StatefulWidget {
  const ProviderEditPage({super.key, required this.service, this.existing});

  final AiProviderService service;

  /// 为空 = 新增；非空 = 编辑。
  final AiProvider? existing;

  @override
  State<ProviderEditPage> createState() => _ProviderEditPageState();
}

class _ProviderEditPageState extends State<ProviderEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _baseUrl;
  late final TextEditingController _apiKey;
  late ApiStyle _apiStyle;
  String? _selectedTemplateId;
  bool _obscureKey = true;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _baseUrl = TextEditingController(text: e?.baseUrl ?? '');
    _apiKey = TextEditingController(); // 编辑时留空 = 保留已保存的 Key
    _apiStyle = e?.apiStyle ?? ApiStyle.openaiCompatible;
    _selectedTemplateId = _isEdit ? 'custom' : null;
  }

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  void _applyTemplate(AiProviderTemplate template) {
    setState(() {
      _selectedTemplateId = template.id;
      _apiStyle = template.apiStyle;
      if (template.baseUrl != null) {
        _baseUrl.text = template.baseUrl!;
      }
      // 已填过名称且与模板名不同时不覆盖，避免覆盖用户输入。
      if (_name.text.trim().isEmpty || _name.text.trim() != template.name) {
        _name.text = template.id == 'custom' ? '' : template.name;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final key = _apiKey.text.trim();
      final existing = widget.existing;
      if (existing == null) {
        await widget.service.addProvider(
          AiProvider(
            id: EntityIds.newProviderId(),
            name: _name.text.trim(),
            apiStyle: _apiStyle,
            baseUrl: _baseUrl.text.trim(),
            apiKey: key.isEmpty ? null : key,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
      } else {
        var updated = existing.copyWith(
          name: _name.text.trim(),
          apiStyle: _apiStyle,
          baseUrl: _baseUrl.text.trim(),
        );
        if (key.isNotEmpty) {
          updated = updated.copyWith(apiKey: key);
        }
        await widget.service.updateProvider(updated);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑供应商' : '添加供应商'),
        actions: [
          IconButton.filledTonal(
            onPressed: _saving ? null : _save,
            icon: const FaIcon(FontAwesomeIcons.check, size: 16),
            tooltip: '保存',
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!_isEdit) ...[
              Text('快速选择模板', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final template in kAiProviderTemplates)
                    ChoiceChip(
                      avatar: FaIcon(
                        providerTemplateIcon(template.id),
                        size: 13,
                        color: providerTemplateColor(template.id),
                      ),
                      showCheckmark: false,
                      label: Text(template.name),
                      selected: _selectedTemplateId == template.id,
                      onSelected: (_) => _applyTemplate(template),
                    ),
                ],
              ),
              if (_selectedTemplateId != null && _selectedTemplateId != 'custom')
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _templateDescription(_selectedTemplateId!),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '名称',
                hintText: '如：智谱官方、我的中转站',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? '请填写名称' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _baseUrl,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                hintText: 'https://example.com/v1',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              validator: (v) {
                final s = v?.trim() ?? '';
                if (s.isEmpty) return '请填写 Base URL';
                if (!s.startsWith('http://') && !s.startsWith('https://')) {
                  return '需要以 http(s):// 开头';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ApiStyle>(
              initialValue: _apiStyle,
              decoration: const InputDecoration(
                labelText: 'API 风格',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: ApiStyle.openaiCompatible,
                  child: Text('OpenAI 兼容（绝大多数服务）'),
                ),
                DropdownMenuItem(
                  value: ApiStyle.anthropic,
                  child: Text('Anthropic（Claude 官方协议）'),
                ),
              ],
              onChanged: (v) => setState(() => _apiStyle = v!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _apiKey,
              obscureText: _obscureKey,
              decoration: InputDecoration(
                labelText: 'API Key',
                hintText: _isEdit ? '留空则保留已保存的 Key' : 'sk-...',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: FaIcon(
                    _obscureKey
                        ? FontAwesomeIcons.eye
                        : FontAwesomeIcons.eyeSlash,
                    size: 16,
                  ),
                  onPressed: () => setState(() => _obscureKey = !_obscureKey),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isEdit
                  ? '当前 Key：${widget.existing!.maskedApiKey ?? '未设置'}'
                  : 'Key 仅保存在本机 SQLite，不会上传到任何服务器。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _templateDescription(String id) {
    final template =
        kAiProviderTemplates.firstWhere((t) => t.id == id);
    return template.description;
  }
}
