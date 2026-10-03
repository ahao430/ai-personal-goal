import 'dart:convert';

/// 全局默认模型选择（供应商与模型分开配置后的「选哪个」）。
class DefaultModelSelection {
  const DefaultModelSelection({required this.providerId, required this.modelId});

  final String providerId;
  final String modelId;

  String encode() => jsonEncode({
        'providerId': providerId,
        'modelId': modelId,
      });

  static DefaultModelSelection? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return DefaultModelSelection(
      providerId: map['providerId']! as String,
      modelId: map['modelId']! as String,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DefaultModelSelection &&
          other.providerId == providerId &&
          other.modelId == modelId);

  @override
  int get hashCode => Object.hash(providerId, modelId);

  @override
  String toString() => 'DefaultModelSelection($providerId, $modelId)';
}

/// 默认模型在设置表中的键。
const String kDefaultModelSettingKey = 'ai.default_model';
