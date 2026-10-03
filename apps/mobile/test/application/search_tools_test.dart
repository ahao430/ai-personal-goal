import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ai_goal/application/app_services.dart';
import 'package:ai_goal/data/database/app_database.dart';

import '../helpers/test_database.dart';

const kUtf8Json = {'content-type': 'application/json; charset=utf-8'};

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

  group('SearchService', () {
    test('未配置 key：走 DuckDuckGo；配置 key：Tavily 优先', () async {
      final hosts = <String>[];
      final searchClient = MockClient((request) async {
        hosts.add(request.url.host);
        if (request.url.host == 'api.tavily.com') {
          return http.Response(
            jsonEncode({
              'results': [
                {'title': 'T', 'url': 'https://t.com/1', 'content': 'c'}
              ],
            }),
            200, headers: kUtf8Json,
          );
        }
        return http.Response(
          '<a class="result__a" href="https://e.com/1">D</a>',
          200, headers: {'content-type': 'text/html; charset=utf-8'},
        );
      });
      services = AppServices.of(db, searchClient: searchClient);

      // 无 key → DDG
      final (results1, provider1) =
          await services.searchService.search('q');
      expect(hosts.single, 'html.duckduckgo.com');
      expect(provider1, 'DuckDuckGo');
      expect(results1.single.title, 'D');

      // 配置 key → Tavily 优先
      await services.searchService.setTavilyKey('tvly-k');
      hosts.clear();
      final (results2, provider2) =
          await services.searchService.search('q', maxResults: 3);
      expect(hosts.single, 'api.tavily.com');
      expect(provider2, 'Tavily');
      expect(results2.single.url, 'https://t.com/1');

      // 清除 key（空字符串）
      await services.searchService.setTavilyKey('  ');
      expect(await services.searchService.tavilyKey(), isNull);
    });

    test('Tavily 失败自动降级 DuckDuckGo', () async {
      final searchClient = MockClient((request) async {
        if (request.url.host == 'api.tavily.com') {
          return http.Response('{"error":"bad key"}', 401);
        }
        return http.Response(
          '<a class="result__a" href="https://e.com/2">DDG 结果</a>',
          200, headers: {'content-type': 'text/html; charset=utf-8'},
        );
      });
      services = AppServices.of(db, searchClient: searchClient);
      await services.searchService.setTavilyKey('tvly-expired');

      final (results, provider) = await services.searchService.search('q');
      expect(provider, 'DuckDuckGo');
      expect(results.single.title, 'DDG 结果');
    });
  });

  group('web_search / fetch_web_page 工具', () {
    test('web_search：返回结果与引用提示', () async {
      services = AppServices.of(
        db,
        searchClient: MockClient((request) async {
          expect(request.url.queryParameters['q'], '2026 N2 考试时间');
          return http.Response(
            '<a class="result__a" href="https://e.com/n2">N2 时间公布</a>'
            '<a class="result__snippet" href="#">12 月 1 日报名</a>',
            200, headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }),
      );

      final result = await services.agentService.tools.execute(
        'web_search',
        {'query': '2026 N2 考试时间'},
      );
      expect(result['ok'], isTrue);
      final data = result['data'] as Map;
      expect(data['provider'], 'DuckDuckGo');
      expect(
        (data['results'] as List).single['title'],
        'N2 时间公布',
      );
      expect((data['hint'] as String), contains('参考来源'));
    });

    test('fetch_web_page：返回去标签正文', () async {
      services = AppServices.of(
        db,
        searchClient: MockClient((_) async => http.Response(
              '<html><body><p>正文第一段</p><p>正文第二段</p></body></html>',
              200, headers: {'content-type': 'text/html; charset=utf-8'},
            )),
      );

      final result = await services.agentService.tools.execute(
        'fetch_web_page',
        {'url': 'https://example.com/page'},
      );
      expect(result['ok'], isTrue);
      final content = (result['data'] as Map)['content'] as String;
      expect(content, contains('正文第一段'));
      expect(content, contains('正文第二段'));
      expect(content, isNot(contains('<p>')));
    });

    test('fetch_web_page：无效 URL 错误回传给模型', () async {
      final result = await services.agentService.tools.execute(
        'fetch_web_page',
        {'url': 'not-a-url'},
      );
      expect(result['ok'], isFalse);
      expect(result['error'], contains('无效的 URL'));
    });

    test('搜索工具 schema 全部暴露', () {
      final names = services.agentService.tools.specs.map((s) => s.name);
      expect(names, containsAll(['web_search', 'fetch_web_page']));
      // 跨端契约一致性：24 个工具
      expect(services.agentService.tools.specs, hasLength(24));
    });
  });
}
