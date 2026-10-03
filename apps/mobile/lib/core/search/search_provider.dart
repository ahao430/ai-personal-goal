import 'dart:convert';

import 'package:http/http.dart' as http;

/// 一条搜索结果（plan §48：Search → Citation 的最小单元）。
class SearchResult {
  const SearchResult({
    required this.title,
    required this.url,
    this.snippet,
  });

  final String title;
  final String url;
  final String? snippet;

  Map<String, Object?> toJson() =>
      {'title': title, 'url': url, 'snippet': ?snippet};
}

/// 搜索来源抽象。实现方自行处理网络异常 —— 调用方（SearchService）
/// 负责降级链。
abstract interface class SearchProvider {
  String get name;
  Future<List<SearchResult>> search(
    String query, {
    int maxResults = 5,
  });
}

/// DuckDuckGo HTML 端点抓取（免 API key，默认来源；结果为尽力而为）。
class DuckDuckGoSearchProvider implements SearchProvider {
  DuckDuckGoSearchProvider({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const _endpoint = 'https://html.duckduckgo.com/html/?q=';

  @override
  String get name => 'DuckDuckGo';

  @override
  Future<List<SearchResult>> search(
    String query, {
    int maxResults = 5,
  }) async {
    final response = await _client.get(
      Uri.parse('$_endpoint${Uri.encodeQueryComponent(query)}'),
      headers: {
        'user-agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
      },
    );
    if (response.statusCode != 200) {
      throw SearchException('DuckDuckGo 返回 ${response.statusCode}');
    }
    final results = _parseHtml(response.body)
        .take(maxResults)
        .toList();
    if (results.isEmpty) {
      throw SearchException('DuckDuckGo 未解析到结果（可能被限流）');
    }
    return results;
  }

  /// 解析 DDG HTML 结果页：result__a 链接（href 可能是
  /// //duckduckgo.com/l/?uddg 查询参数 重定向）+ result__snippet。
  static List<SearchResult> _parseHtml(String html) {
    final results = <SearchResult>[];
    final linkPattern = RegExp(
      r'<a[^>]+class="[^"]*result__a[^"]*"[^>]+href="([^"]+)"[^>]*>(.*?)</a>',
      dotAll: true,
    );
    final snippetPattern = RegExp(
      r'<a[^>]+class="[^"]*result__snippet[^"]*"[^>]*>(.*?)</a>',
      dotAll: true,
    );
    final snippets =
        snippetPattern.allMatches(html).map((m) => _stripTags(m.group(1)!));

    final snippetList = snippets.toList();
    var index = 0;
    for (final match in linkPattern.allMatches(html)) {
      final rawUrl = _decodeHtmlEntities(match.group(1)!);
      final url = _resolveRedirect(rawUrl);
      if (url == null) continue;
      final title = _stripTags(match.group(2)!);
      if (title.isEmpty) continue;
      results.add(SearchResult(
        title: title,
        url: url,
        snippet: index < snippetList.length ? snippetList[index] : null,
      ));
      index++;
    }
    return results;
  }

  /// duckduckgo.com 域 l 路径的 uddg 查询参数重定向 → 解码出真实链接。
  static String? _resolveRedirect(String url) {
    final uri = Uri.tryParse(url.startsWith('//') ? 'https:$url' : url);
    if (uri == null) return null;
    if (uri.host.endsWith('duckduckgo.com') && uri.queryParameters['uddg'] != null) {
      return uri.queryParameters['uddg'];
    }
    return url;
  }

  static String _stripTags(String html) {
    final withoutTags = html.replaceAll(RegExp(r'<[^>]*>'), '');
    return _decodeHtmlEntities(withoutTags).trim();
  }

  static String _decodeHtmlEntities(String input) => input
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#x27;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ');
}

/// Tavily 搜索 API（用户在设置中配置 key 后启用，结果质量更高）。
class TavilySearchProvider implements SearchProvider {
  TavilySearchProvider({required String apiKey, http.Client? client})
      : _apiKey = apiKey,
        _client = client ?? http.Client();

  static const _endpoint = 'https://api.tavily.com/search';

  final String _apiKey;
  final http.Client _client;

  @override
  String get name => 'Tavily';

  @override
  Future<List<SearchResult>> search(
    String query, {
    int maxResults = 5,
  }) async {
    final response = await _client.post(
      Uri.parse(_endpoint),
      headers: {
        'authorization': 'Bearer $_apiKey',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'query': query,
        'max_results': maxResults,
        'search_depth': 'basic',
      }),
    );
    if (response.statusCode != 200) {
      throw SearchException('Tavily 返回 ${response.statusCode}');
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    final results = (body['results'] as List? ?? const [])
        .cast<Map>()
        .map((r) => SearchResult(
              title: r['title'] as String? ?? '',
              url: r['url'] as String? ?? '',
              snippet: r['content'] as String?,
            ))
        .where((r) => r.url.isNotEmpty)
        .toList();
    if (results.isEmpty) {
      throw SearchException('Tavily 未返回结果');
    }
    return results;
  }
}

class SearchException implements Exception {
  SearchException(this.message);

  final String message;

  @override
  String toString() => message;
}
