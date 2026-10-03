import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/external/data_source.dart';
import '../../domain/settings/app_settings.dart';

/// 外部数据提供者（plan §49 框架核心）。
///
/// 权限模型：[checkPermission] 读 App 内授权状态（PermissionStore），
/// [requestPermission] 由 UI 调用做系统级授权（有系统权限的源）或
/// 直接记录用户选择（如天气这类无系统权限的源）。
/// [readContext] 只在授权后才被 Context Adapter 调用；
/// 数据不可用时返回 null（静默降级，不阻塞 AI 上下文）。
abstract interface class DataProvider {
  ExternalSource get source;

  /// 是否有系统级权限流程（health/location/calendar 有，weather 无）。
  bool get needsSystemPermission;

  Future<PermissionStatus> checkPermission();

  /// 请求授权。返回请求后的状态。
  Future<PermissionStatus> requestPermission();

  /// 读取上下文片段（紧凑 JSON 可序列化）；不可用返回 null。
  Future<Map<String, Object?>?> readContext({DateTime? now});
}

/// 天气：Open-Meteo 免 key API + 手动城市配置。
///
/// 位置配置存 settings（`weather.location`，JSON {name, lat, lon}）；
/// 城市名 → 坐标用 Open-Meteo Geocoding。
class WeatherDataProvider implements DataProvider {
  WeatherDataProvider({
    required AppSettingsRepository settings,
    required DataSourcePermissionRepository permissions,
    http.Client? client,
  })  : _settings = settings,
        _permissions = permissions,
        _client = client ?? http.Client();

  static const String locationSettingKey = 'weather.location';

  final AppSettingsRepository _settings;
  final DataSourcePermissionRepository _permissions;
  final http.Client _client;

  @override
  ExternalSource get source => ExternalSource.weather;

  @override
  bool get needsSystemPermission => false;

  @override
  Future<PermissionStatus> checkPermission() =>
      _permissions.statusOf(source);

  @override
  Future<PermissionStatus> requestPermission() async {
    await _permissions.setStatus(source, PermissionStatus.granted);
    return PermissionStatus.granted;
  }

  Future<void> revoke() =>
      _permissions.setStatus(source, PermissionStatus.notRequested);

  /// 配置城市（geocode 取第一个结果）；失败抛 StateError。
  Future<void> setLocationByName(String cityName) async {
    final uri = Uri.parse(
      'https://geocoding-api.open-meteo.com/v1/search'
      '?name=${Uri.encodeComponent(cityName)}&count=1&language=zh',
    );
    final response = await _client.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw StateError('城市查询失败：HTTP ${response.statusCode}');
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    final results = body['results'] as List? ?? const [];
    if (results.isEmpty) {
      throw StateError('找不到城市「$cityName」');
    }
    final first = results.first as Map;
    await setLocation(
      name: first['name'] as String,
      lat: (first['latitude'] as num).toDouble(),
      lon: (first['longitude'] as num).toDouble(),
    );
  }

  Future<void> setLocation({
    required String name,
    required double lat,
    required double lon,
  }) =>
      _settings.write(
        locationSettingKey,
        jsonEncode({'name': name, 'lat': lat, 'lon': lon}),
      );

  Future<void> clearLocation() => _settings.delete(locationSettingKey);

  Future<({String name, double lat, double lon})?> configuredLocation() async {
    final raw = await _settings.read(locationSettingKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map;
      return (
        name: map['name'] as String,
        lat: (map['lat'] as num).toDouble(),
        lon: (map['lon'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Map<String, Object?>?> readContext({DateTime? now}) async {
    if (await checkPermission() != PermissionStatus.granted) return null;
    final location = await configuredLocation();
    if (location == null) return null;

    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=${location.lat}&longitude=${location.lon}'
        '&current=temperature_2m,weather_code,apparent_temperature'
        '&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max'
        '&forecast_days=2&timezone=auto',
      );
      final response =
          await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map;

      final current = body['current'] as Map? ?? const {};
      final daily = body['daily'] as Map? ?? const {};
      return {
        'location': location.name,
        'current': {
          if (current['temperature_2m'] != null)
            'temperature': current['temperature_2m'],
          if (current['apparent_temperature'] != null)
            'feelsLike': current['apparent_temperature'],
          if (current['weather_code'] != null)
            'condition': _wmoText(current['weather_code'] as num),
        },
        'today': _daySummary(daily, 0),
        'tomorrow': _daySummary(daily, 1),
      };
    } catch (_) {
      return null; // 天气不可用不应影响上下文构建。
    }
  }

  static Map<String, Object?>? _daySummary(Map daily, int index) {
    final times = daily['time'] as List? ?? const [];
    if (times.length <= index) return null;
    final maxes = daily['temperature_2m_max'] as List? ?? const [];
    final mins = daily['temperature_2m_min'] as List? ?? const [];
    final precip =
        daily['precipitation_probability_max'] as List? ?? const [];
    return {
      if (maxes.length > index) 'maxTemp': maxes[index],
      if (mins.length > index) 'minTemp': mins[index],
      if (precip.length > index) 'precipitationChance': precip[index],
    };
  }

  /// WMO weather code → 中文描述（简表）。
  static String _wmoText(num code) {
    final c = code.toInt();
    if (c == 0) return '晴';
    if (c <= 3) return '多云';
    if (c == 45 || c == 48) return '雾';
    if (c >= 51 && c <= 67) return '雨';
    if (c >= 71 && c <= 77) return '雪';
    if (c >= 80 && c <= 82) return '阵雨';
    if (c >= 85 && c <= 86) return '阵雪';
    if (c >= 95) return '雷雨';
    return '未知';
  }
}

/// 占位源（health / location / calendar）：框架就绪，真实接入随版本开放。
/// readContext 恒为 null —— 只参与权限状态展示与未来扩展。
class PlaceholderDataProvider implements DataProvider {
  PlaceholderDataProvider({
    required this.source,
    required DataSourcePermissionRepository permissions,
  }) : _permissions = permissions;

  final DataSourcePermissionRepository _permissions;

  @override
  final ExternalSource source;

  @override
  bool get needsSystemPermission => true;

  @override
  Future<PermissionStatus> checkPermission() =>
      _permissions.statusOf(source);

  @override
  Future<PermissionStatus> requestPermission() async {
    // 系统权限未接入：记录 requested，等待版本开放后走真实弹窗。
    await _permissions.setStatus(source, PermissionStatus.requested);
    return PermissionStatus.requested;
  }

  @override
  Future<Map<String, Object?>?> readContext({DateTime? now}) async => null;
}
