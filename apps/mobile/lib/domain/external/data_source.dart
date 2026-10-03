import '../time_codec.dart';

/// 外部数据源（plan §49：Health / Weather / Location / Calendar）。
enum ExternalSource {
  health,
  weather,
  location,
  calendar;

  static ExternalSource parse(String value) => values.firstWhere(
        (v) => v.name == value,
        orElse: () => throw ArgumentError('未知的数据源: $value'),
      );

  String get displayName => switch (this) {
        health => '健康数据',
        weather => '天气',
        location => '位置',
        calendar => '日历',
      };

  String get description => switch (this) {
        health => '步数 / 运动完成情况（Apple Health / Health Connect）',
        weather => '户外目标建议：今天适不适合跑步、骑行',
        location => '附近场地 / 通勤时间感知',
        calendar => '空闲时间感知，排日程不撞车',
      };
}

/// 授权状态（App 内的使用许可；系统级权限由各 Provider 自行处理）。
enum PermissionStatus {
  notRequested,
  requested,
  granted,
  denied;

  static PermissionStatus parse(String value) => values.firstWhere(
        (v) => v.name == value,
        orElse: () => throw ArgumentError('未知的授权状态: $value'),
      );

  String get columnName => name;
}

/// 数据源授权记录。
class DataSourcePermission {
  const DataSourcePermission({
    required this.source,
    required this.status,
    required this.updatedAt,
  });

  final ExternalSource source;
  final PermissionStatus status;
  final DateTime updatedAt;

  Map<String, Object?> toMap() => {
        'source': source.name,
        'status': status.columnName,
        'updated_at': encodeTime(updatedAt),
      };

  factory DataSourcePermission.fromMap(Map<String, Object?> map) =>
      DataSourcePermission(
        source: ExternalSource.parse(map['source']! as String),
        status: PermissionStatus.parse(map['status']! as String),
        updatedAt: decodeTime(map['updated_at']! as String),
      );
}

abstract interface class DataSourcePermissionRepository {
  /// 读取授权状态；无记录 = notRequested。
  Future<PermissionStatus> statusOf(ExternalSource source);

  Future<List<DataSourcePermission>> findAll();

  Future<void> setStatus(ExternalSource source, PermissionStatus status);
}
