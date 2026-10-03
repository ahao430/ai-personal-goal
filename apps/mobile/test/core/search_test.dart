import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ai_goal/core/search/page_fetcher.dart';
import 'package:ai_goal/core/search/search_provider.dart';

const kUtf8Json = {'content-type': 'application/json; charset=utf-8'};

void main() {
  group('DuckDuckGoSearchProvider', () {
    test('解析结果页：标题 / 链接 / 摘要，uddg 重定向解码', () async {
      final html = '''
      <html><body>
      <div class="result">
        <a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fn2&amp;rut=abc">2026 年 N2 考试时间</a>
        <a class="result__snippet" href="#">报名 <b>12 月</b> 上旬开始…</a>
      </div>
      <div class="result">
        <a class="result__a" href="https://direct.example.com/page">直接链接结果</a>
        <a class="result__snippet" href="#">摘要二</a>
      </div>
      </body></html>
      ''';
      var requested = false;
      final provider = DuckDuckGoSearchProvider(
        client: MockClient((request) async {
          requested = true;
          expect(request.url.host, 'html.duckduckgo.com');
          expect(request.url.queryParameters['q'], 'N2 考试时间');
          expect(request.headers['user-agent'], isNotEmpty);
          return http.Response(html, 200, headers: {'content-type': 'text/html; charset=utf-8'});
        }),
      );

      final results = await provider.search('N2 考试时间');
      expect(requested, isTrue);
      expect(results, hasLength(2));
      expect(results.first.title, '2026 年 N2 考试时间');
      expect(results.first.url, 'https://example.com/n2');
      expect(results.first.snippet, '报名 12 月 上旬开始…');
      expect(results[1].url, 'https://direct.example.com/page');
      expect(results[1].snippet, '摘要二');
    });

    test('非 200 抛 SearchException', () async {
      final provider = DuckDuckGoSearchProvider(
        client: MockClient((_) async => http.Response('blocked', 403)),
      );
      expect(
        () => provider.search('q'),
        throwsA(isA<SearchException>()),
      );
    });

    test('maxResults 截断', () async {
      final html = List.generate(5, (i) =>
        '<a class="result__a" href="https://e.com/$i">结果 $i</a>').join();
      final provider = DuckDuckGoSearchProvider(
        client: MockClient((_) async => http.Response(
          html, 200, headers: {'content-type': 'text/html; charset=utf-8'})),
      );
      final results = await provider.search('q', maxResults: 2);
      expect(results, hasLength(2));
    });
  });

  group('TavilySearchProvider', () {
    test('请求形态：Bearer + JSON body；解析 results', () async {
      final provider = TavilySearchProvider(
        apiKey: 'tvly-test',
        client: MockClient((request) async {
          expect(request.url.toString(), 'https://api.tavily.com/search');
          expect(request.headers['authorization'], 'Bearer tvly-test');
          final body = jsonDecode(request.body) as Map;
          expect(body['query'], '东京 5 天行程');
          expect(body['max_results'], 3);
          return http.Response(
            jsonEncode({
              'results': [
                {
                  'title': '东京攻略',
                  'url': 'https://example.com/tokyo',
                  'content': '五天四夜…',
                }
              ],
            }),
            200, headers: kUtf8Json,
          );
        }),
      );

      final results = await provider.search('东京 5 天行程', maxResults: 3);
      expect(results.single.title, '东京攻略');
      expect(results.single.url, 'https://example.com/tokyo');
    });
  });

  group('PageFetcher', () {
    test('去 script/style、剥标签、转实体、折叠空白', () async {
      final fetcher = PageFetcher(
        client: MockClient((request) async {
          expect(request.url.toString(), 'https://example.com/guide');
          return http.Response('''
          <html>
            <head><title>t</title><script>var x = 1;</script></head>
            <body>
              <style>.a { color: red; }</style>
              <h1>考试安排</h1>
              <p>报名：&amp;nbsp;12月1日起 &lt;仅限新考生&gt;</p>
              <p>第二段</p>
            </body>
          </html>
          ''', 200, headers: {'content-type': 'text/html; charset=utf-8'});
        }),
      );

      final text = await fetcher.fetchPlainText('https://example.com/guide');
      expect(text, isNot(contains('var x')));
      expect(text, isNot(contains('color')));
      expect(text, contains('考试安排'));
      expect(text, contains('12月1日起 <仅限新考生>'));
      expect(text.split('\n'), everyElement(isNot(contains('  '))));
    });

    test('超长正文截断到 maxLength', () async {
      final fetcher = PageFetcher(
        client: MockClient((_) async =>
            http.Response('<p>${'x' * 10000}</p>', 200,
                headers: {'content-type': 'text/html; charset=utf-8'})),
      );
      final text =
          await fetcher.fetchPlainText('https://e.com/x', maxLength: 100);
      expect(text.length, 101); // 100 + 省略号
      expect(text.endsWith('…'), isTrue);
    });

    test('无效 URL 与非 2xx 抛 PageFetchException', () async {
      final fetcher = PageFetcher(
        client: MockClient((_) async => http.Response('no', 404)),
      );
      expect(() => fetcher.fetchPlainText('ftp://bad'),
          throwsA(isA<PageFetchException>()));
      expect(() => fetcher.fetchPlainText('https://e.com/404'),
          throwsA(isA<PageFetchException>()));
    });
  });
}
