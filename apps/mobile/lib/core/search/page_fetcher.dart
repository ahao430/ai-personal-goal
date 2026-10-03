import 'package:http/http.dart' as http;

/// 网页抓取：返回去标签纯文本摘录（供 AI 阅读引用）。
class PageFetcher {
  PageFetcher({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// 抓取 [url] 并返回正文文本。
  ///
  /// 截断到 [maxLength] 字符，防止长页面撑爆上下文；
  /// 非 2xx / 无正文抛 [PageFetchException]。
  Future<String> fetchPlainText(
    String url, {
    int maxLength = 4000,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.isAbsolute || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw PageFetchException('无效的 URL: $url');
    }
    final response = await _client.get(uri, headers: {
      'user-agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
    }).timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PageFetchException('抓取失败：HTTP ${response.statusCode}');
    }

    final html = response.body;
    final text = _htmlToText(html);
    if (text.trim().isEmpty) {
      throw PageFetchException('页面无可读正文');
    }
    return text.length <= maxLength ? text : '${text.substring(0, maxLength)}…';
  }

  static String _htmlToText(String html) {
    var working = html
        .replaceAll(RegExp(r'<(script|style|head|noscript)[^>]*>.*?</\1>',
            dotAll: true, caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), ' ');
    // 块级标签转换行，行内标签直接剥掉。
    working = working.replaceAll(
        RegExp(r'</(p|div|li|h[1-6]|tr|br)\s*>|<br\s*/?>',
            caseSensitive: false),
        '\n');
    working = working.replaceAll(RegExp(r'<[^>]*>'), ' ');
    working = _decodeEntities(working);
    // 折叠空白（保留换行结构）。
    working = working
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((line) => line.isNotEmpty)
        .join('\n');
    return working;
  }

  static String _decodeEntities(String input) => input
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#x27;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ');
}

class PageFetchException implements Exception {
  PageFetchException(this.message);

  final String message;

  @override
  String toString() => message;
}
