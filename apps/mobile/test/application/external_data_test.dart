import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ai_goal/application/app_services.dart';
import 'package:ai_goal/core/external/data_provider.dart';
import 'package:ai_goal/data/database/app_database.dart';
import 'package:ai_goal/domain/external/data_source.dart';

import '../helpers/test_database.dart';

const kUtf8Json = {'content-type': 'application/json; charset=utf-8'};

WeatherDataProvider _weather(
  AppServices services, {
  required http.Client client,
}) =>
    WeatherDataProvider(
      settings: services.settings,
      permissions: services.dataSourcePermissions,
      client: client,
    );

void main() {
  late AppDatabase db;
  late AppServices services;

  setUp(() async {
    db = await openTestDatabase();
    services = AppServices.of(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('PermissionStore（schema v5）', () {
    test('默认 notRequested；setStatus 覆盖；findAll', () async {
      final repo = services.dataSourcePermissions;

      expect(
        await repo.statusOf(ExternalSource.health),
        PermissionStatus.notRequested,
      );
      await repo.setStatus(ExternalSource.weather, PermissionStatus.granted);
      await repo.setStatus(ExternalSource.weather, PermissionStatus.denied);

      expect(
        await repo.statusOf(ExternalSource.weather),
        PermissionStatus.denied,
      );
      expect(await repo.findAll(), hasLength(1)); // 主键覆盖不产生新行
    });
  });

  group('WeatherDataProvider', () {
    test('geocode + forecast：配置城市并解析上下文', () async {
      final requests = <Uri>[];
      final weather = _weather(
        services,
        client: MockClient((request) async {
          requests.add(request.url);
          if (request.url.host == 'geocoding-api.open-meteo.com') {
            return http.Response(
              jsonEncode({
                'results': [
                  {'name': '上海', 'latitude': 31.23, 'longitude': 121.47}
                ],
              }),
              200, headers: kUtf8Json,
            );
          }
          return http.Response(
            jsonEncode({
              'current': {
                'temperature_2m': 22.5,
                'apparent_temperature': 23.1,
                'weather_code': 3,
              },
              'daily': {
                'time': ['2026-10-03', '2026-10-04'],
                'temperature_2m_max': [25.0, 24.0],
                'temperature_2m_min': [18.0, 17.5],
                'precipitation_probability_max': [10, 60],
              },
            }),
            200, headers: kUtf8Json,
          );
        }),
      );

      await weather.setLocationByName('上海');
      await weather.requestPermission();

      final context = await weather.readContext();
      expect(context, isNotNull);
      expect(context!['location'], '上海');
      expect(((context['current'] as Map)['condition']), '多云');
      expect(((context['today'] as Map)['maxTemp']), 25.0);
      expect(((context['tomorrow'] as Map)['precipitationChance']), 60);

      // 两次请求：geocoding + forecast
      expect(requests, hasLength(2));
      expect(
        requests.first.queryParameters['name'],
        '上海',
      );
      expect(
        requests.last.queryParameters['latitude'],
        '31.23',
      );
      expect(
        requests.last.queryParameters['daily'],
        contains('precipitation_probability_max'),
      );
    });

    test('未授权 / 未配城市 / 请求失败 → readContext 返回 null', () async {
      var calls = 0;
      final weather = _weather(
        services,
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 200, headers: kUtf8Json);
        }),
      );

      // 未授权
      expect(await weather.readContext(), isNull);
      expect(calls, 0);

      // 已授权但未配城市
      await weather.requestPermission();
      expect(await weather.readContext(), isNull);
      expect(calls, 0);

      // 配了城市但 forecast 挂了（500）
      await weather.setLocation(name: 'X', lat: 1, lon: 2);
      services.dataSourcePermissions
          .setStatus(ExternalSource.weather, PermissionStatus.denied);
      final broken = _weather(
        services,
        client: MockClient((_) async => http.Response('err', 500)),
      );
      await services.dataSourcePermissions
          .setStatus(ExternalSource.weather, PermissionStatus.granted);
      expect(await broken.readContext(), isNull);
    });

    test('找不到城市抛 StateError', () async {
      final weather = _weather(
        services,
        client: MockClient((_) async =>
            http.Response(jsonEncode({'results': []}), 200, headers: kUtf8Json)),
      );
      expect(() => weather.setLocationByName('不存在城市XYZ'),
          throwsStateError);
    });
  });

  group('ExternalDataService（Context Adapter）', () {
    test('已授权源进上下文，未授权/失败源跳过', () async {
      final weather = _weather(
        services,
        client: MockClient((request) async {
          if (request.url.host == 'geocoding-api.open-meteo.com') {
            return http.Response(
              jsonEncode({
                'results': [
                  {'name': '北京', 'latitude': 39.9, 'longitude': 116.4}
                ],
              }),
              200, headers: kUtf8Json,
            );
          }
          return http.Response(
            jsonEncode({
              'current': {'temperature_2m': 15.0, 'weather_code': 0},
              'daily': {'time': ['2026-10-03']},
            }),
            200, headers: kUtf8Json,
          );
        }),
      );
      await weather.setLocationByName('北京');
      await weather.requestPermission();

      final external = await services.externalService.buildExternalContext();
      expect(external, isNotNull);
      expect((external!)['weather'], isNotNull);
      expect(external.containsKey('health'), isFalse,
          reason: '占位源未授权，不进上下文');
    });

    test('全部未授权 → null（ContextBuilder 不写 external 键）', () async {
      final external = await services.externalService.buildExternalContext();
      expect(external, isNull);

      final context = await services.contextBuilder.build();
      expect(context, isNot(contains('"external"')));
    });

    test('ContextBuilder 正向集成：授权后上下文含 external.weather', () async {
      final client = MockClient((request) async {
        if (request.url.host == 'geocoding-api.open-meteo.com') {
          return http.Response(
            jsonEncode({
              'results': [
                {'name': '上海', 'latitude': 31.23, 'longitude': 121.47}
              ],
            }),
            200, headers: kUtf8Json,
          );
        }
        return http.Response(
          jsonEncode({
            'current': {'temperature_2m': 22.0, 'weather_code': 0},
            'daily': {'time': ['2026-10-03']},
          }),
          200, headers: kUtf8Json,
        );
      });
      services = AppServices.of(db, searchClient: client);

      final weather = services.externalService
          .providerOf(ExternalSource.weather)! as WeatherDataProvider;
      await weather.requestPermission();
      await weather.setLocationByName('上海');

      final context = await services.contextBuilder.build();
      expect(context, contains('"external"'));
      expect(context, contains('"weather"'));
      expect(context, contains('"上海"'));
      expect(context, contains('"晴"'));
    });
  });
}
