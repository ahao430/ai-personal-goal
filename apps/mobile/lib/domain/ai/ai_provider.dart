/// AI 供应商的 API 协议风格。
///
/// - [openaiCompatible]：`GET {baseURL}/models` + `Authorization: Bearer`，
///   覆盖 OpenAI / 智谱 / DeepSeek / Kimi / 各类中转站等绝大多数服务；
/// - [anthropic]：`GET {baseURL}/v1/models` + `x-api-key` 头。
enum ApiStyle {
  openaiCompatible,
  anthropic;

  static ApiStyle parse(String value) => values.firstWhere(
        (v) => v.name == value,
        orElse: () => throw ArgumentError('未知的 API 风格: $value'),
      );

  String get columnName => this == ApiStyle.openaiCompatible
      ? 'openai_compatible'
      : 'anthropic';

  static ApiStyle fromColumnName(String value) => values.firstWhere(
        (v) => v.columnName == value,
        orElse: () => throw ArgumentError('未知的 API 风格: $value'),
      );
}

/// 用户配置的 AI 供应商。可以同时配置多个。
///
/// API Key 在 V1 以明文存于本地 SQLite（无后端、无同步）；
/// UI 层负责脱敏展示。
class AiProvider {
  const AiProvider({
    required this.id,
    required this.name,
    required this.apiStyle,
    required this.baseUrl,
    this.apiKey,
    this.enabled = true,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// 展示名，如「智谱官方」「我的中转站」。
  final String name;

  final ApiStyle apiStyle;

  /// API 根地址，如 `https://open.bigmodel.cn/api/paas/v4`（不含末尾斜杠）。
  final String baseUrl;

  final String? apiKey;
  final bool enabled;

  final DateTime createdAt;
  final DateTime updatedAt;

  static const _keep = Object();

  AiProvider copyWith({
    String? name,
    ApiStyle? apiStyle,
    String? baseUrl,
    Object? apiKey = _keep,
    bool? enabled,
    DateTime? updatedAt,
  }) {
    return AiProvider(
      id: id,
      name: name ?? this.name,
      apiStyle: apiStyle ?? this.apiStyle,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey == _keep ? this.apiKey : apiKey as String?,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'api_style': apiStyle.columnName,
        'base_url': baseUrl,
        'api_key': apiKey,
        'enabled': enabled ? 1 : 0,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory AiProvider.fromMap(Map<String, Object?> map) => AiProvider(
        id: map['id']! as String,
        name: map['name']! as String,
        apiStyle: ApiStyle.fromColumnName(map['api_style']! as String),
        baseUrl: map['base_url']! as String,
        apiKey: map['api_key'] as String?,
        enabled: (map['enabled']! as int) == 1,
        createdAt: DateTime.parse(map['created_at']! as String).toLocal(),
        updatedAt: DateTime.parse(map['updated_at']! as String).toLocal(),
      );

  /// Key 脱敏展示：只露尾 4 位。
  String? get maskedApiKey {
    final key = apiKey;
    if (key == null || key.isEmpty) return null;
    if (key.length <= 8) return '••••';
    return '••••${key.substring(key.length - 4)}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is AiProvider && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'AiProvider($id, $name, $baseUrl)';
}
