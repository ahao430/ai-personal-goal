import 'package:http/http.dart' as http;

import '../core/search/page_fetcher.dart';
import '../core/search/search_provider.dart';
import '../domain/settings/app_settings.dart';

/// 联网搜索用例（P8，plan §48）。
///
/// 来源链：用户配置了 Tavily key → Tavily 优先（失败降级）；
/// 否则 DuckDuckGo（免 key，尽力而为）。
class SearchService {
  SearchService(this._settings, {http.Client? client})
      : _client = client ?? http.Client();

  static const String tavilyKeySettingKey = 'search.tavily_key';

  final AppSettingsRepository _settings;
  final http.Client _client;

  Future<String?> tavilyKey() => _settings.read(tavilyKeySettingKey);

  Future<void> setTavilyKey(String? key) async {
    final trimmed = key?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await _settings.delete(tavilyKeySettingKey);
    } else {
      await _settings.write(tavilyKeySettingKey, trimmed);
    }
  }

  /// 搜索：Tavily（如已配置）优先，失败或未配置时用 DuckDuckGo。
  Future<(List<SearchResult>, String providerName)> search(
    String query, {
    int maxResults = 5,
  }) async {
    final key = await tavilyKey();
    if (key != null && key.isNotEmpty) {
      try {
        final results = await TavilySearchProvider(apiKey: key, client: _client)
            .search(query, maxResults: maxResults);
        return (results, 'Tavily');
      } catch (_) {
        // Tavily 失败 → 降级 DDG。
      }
    }
    final results = await DuckDuckGoSearchProvider(client: _client)
        .search(query, maxResults: maxResults);
    return (results, 'DuckDuckGo');
  }

  /// 抓取网页正文（去标签、截断）。
  Future<String> fetchPage(String url, {int maxLength = 4000}) =>
      PageFetcher(client: _client).fetchPlainText(url, maxLength: maxLength);
}
