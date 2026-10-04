import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/config/app_palette.dart';
import '../../domain/goal/goal.dart';
import '../../domain/goal/goal_metric.dart';
import '../providers.dart';

/// 创建 / 编辑目标。创建时可选配一个初始 Metric（如体重）。
class GoalEditPage extends ConsumerStatefulWidget {
  const GoalEditPage({super.key, this.existing});

  final Goal? existing;

  @override
  ConsumerState<GoalEditPage> createState() => _GoalEditPageState();
}

class _GoalEditPageState extends ConsumerState<GoalEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _reward;
  DateTime? _targetDate;

  // 可选 Metric
  final _metricName = TextEditingController();
  final _metricCurrent = TextEditingController();
  final _metricTarget = TextEditingController();
  final _metricUnit = TextEditingController(text: 'kg');
  MetricDirection _metricDirection = MetricDirection.decrease;
  bool _showMetric = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _reward = TextEditingController(text: e?.reward ?? '');
    _targetDate = e?.targetDate;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _reward.dispose();
    _metricName.dispose();
    _metricCurrent.dispose();
    _metricTarget.dispose();
    super.dispose();
  }

  Future<void> _pickTargetDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate ?? now.add(const Duration(days: 30)),
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (picked != null) setState(() => _targetDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final services = ref.read(servicesProvider);
    try {
      final existing = widget.existing;
      final rewardText = _reward.text.trim();
      if (existing == null) {
        final goal = await services.goalService.createGoal(
          title: _title.text.trim(),
          description: _description.text.trim().isEmpty ? null : _description.text.trim(),
          targetDate: _targetDate,
          reward: rewardText.isEmpty ? null : rewardText,
        );
        if (_showMetric && _metricName.text.trim().isNotEmpty) {
          await services.goalService.addMetric(
            goal.id,
            name: _metricName.text.trim(),
            unit: _metricUnit.text.trim().isEmpty ? null : _metricUnit.text.trim(),
            direction: _metricDirection,
            initialValue: double.tryParse(_metricCurrent.text.trim()),
            targetValue: double.tryParse(_metricTarget.text.trim()),
          );
        }
      } else {
        await services.goalService.updateGoal(
          existing.id,
          (g) => g.copyWith(
            title: _title.text.trim(),
            description:
                _description.text.trim().isEmpty ? null : _description.text.trim(),
            targetDate: _targetDate,
            reward: rewardText.isEmpty ? null : rewardText,
          ),
        );
      }
      invalidateAll(ref);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑目标' : '新建目标'),
        actions: [
          IconButton.filledTonal(
            tooltip: '保存',
            onPressed: _save,
            icon: const FaIcon(FontAwesomeIcons.check, size: 16),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: '想完成什么？',
                hintText: '如：三个月减掉 5kg',
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? '写个标题吧' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '补充描述（可选）',
                hintText: '背景、动机、约束…',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _reward,
              decoration: const InputDecoration(
                labelText: '达成奖励（可选）',
                hintText: '达成后送自己什么？如：一双跑鞋',
                prefixIcon: FaIcon(FontAwesomeIcons.gift, size: 16),
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickTargetDate,
              borderRadius: BorderRadius.circular(14),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: '目标日期（可选）',
                  suffixIcon: FaIcon(FontAwesomeIcons.calendarDay, size: 16),
                ),
                child: Text(
                  _targetDate == null
                      ? '选择日期'
                      : '${_targetDate!.year}/${_targetDate!.month}/${_targetDate!.day}',
                ),
              ),
            ),
            if (!_isEdit) ...[
              const SizedBox(height: 20),
              _metricSection(theme),
            ],
            const SizedBox(height: 12),
            Text(
              _isEdit ? '阶段与任务在目标详情页管理' : '保存后可在详情页添加阶段与任务；P5 起 AI 可以代劳',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppPalette.warmBrown.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricSection(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const FaIcon(FontAwesomeIcons.chartLine,
                    size: 15, color: AppPalette.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('量化这个目标（可选）',
                      style: theme.textTheme.titleSmall),
                ),
                Switch(
                  value: _showMetric,
                  activeThumbColor: AppPalette.sunsetOrange,
                  onChanged: (v) => setState(() => _showMetric = v),
                ),
              ],
            ),
            if (_showMetric) ...[
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _metricName,
                      decoration: const InputDecoration(labelText: '指标名'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _metricUnit,
                      decoration: const InputDecoration(labelText: '单位'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _metricCurrent,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '当前值'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _metricTarget,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '目标值'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<MetricDirection>(
                    value: _metricDirection,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(
                        value: MetricDirection.decrease,
                        child: Text('↓'),
                      ),
                      DropdownMenuItem(
                        value: MetricDirection.increase,
                        child: Text('↑'),
                      ),
                    ],
                    onChanged: (v) =>
                        setState(() => _metricDirection = v!),
                  ),
                ],
              ),
              Text(
                '↓ 越小越好（体重）；↑ 越大越好（存款）',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppPalette.warmBrown.withValues(alpha: 0.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
