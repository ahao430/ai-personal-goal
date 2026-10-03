import '../time_codec.dart';

/// 模型记录的来源：fetched = 一键从供应商拉取；manual = 用户手动录入
/// （部分中转站 /models 接口不全，手动补录后长期保留）。
enum AiModelSource {
  fetched,
  manual;

  static AiModelSource parse(String value) => values.firstWhere(
        (v) => v.name == value,
        orElse: () => throw ArgumentError('未知的模型来源: $value'),
      );
}

/// 已知模型（某供应商下的模型缓存条目）。
class AiModelInfo {
  const AiModelInfo({
    required this.providerId,
    required this.modelId,
    this.displayName,
    this.source = AiModelSource.fetched,
    required this.updatedAt,
  });

  /// 所属供应商 ID。
  final String providerId;

  /// 模型标识（调用 API 时使用的 model 参数），如 `glm-4.6`、`gpt-4o`。
  final String modelId;

  /// 供应商返回的展示名（如 Claude 的 display_name），可为空。
  final String? displayName;

  final AiModelSource source;

  final DateTime updatedAt;

  /// 展示优先用 displayName，其次 modelId。
  String get label => displayName?.trim().isNotEmpty == true
      ? displayName!.trim()
      : modelId;

  AiModelInfo copyWith({String? displayName, DateTime? updatedAt}) =>
      AiModelInfo(
        providerId: providerId,
        modelId: modelId,
        displayName: displayName ?? this.displayName,
        source: source,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toMap() => {
        'provider_id': providerId,
        'model_id': modelId,
        'display_name': displayName,
        'source': source.name,
        'updated_at': encodeTime(updatedAt),
      };

  factory AiModelInfo.fromMap(Map<String, Object?> map) => AiModelInfo(
        providerId: map['provider_id']! as String,
        modelId: map['model_id']! as String,
        displayName: map['display_name'] as String?,
        source: AiModelSource.parse(map['source']! as String),
        updatedAt: decodeTime(map['updated_at']! as String),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AiModelInfo &&
          other.providerId == providerId &&
          other.modelId == modelId);

  @override
  int get hashCode => Object.hash(providerId, modelId);

  @override
  String toString() => 'AiModelInfo($providerId, $modelId)';
}
