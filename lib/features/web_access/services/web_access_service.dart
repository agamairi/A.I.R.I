/// Web access service — abstract provider-agnostic web access.
library;

import 'dart:async';

import 'package:http/http.dart' as http;

// ---------------------------------------------------------------------------
// Abstractions
// ---------------------------------------------------------------------------

/// Policy for web access behavior.
class WebToolPolicy {
  final bool enabled;
  final bool askBeforeSearch;
  final Duration requestTimeout;
  final Set<String> allowedHosts;

  const WebToolPolicy({
    this.enabled = false,
    this.askBeforeSearch = true,
    this.requestTimeout = const Duration(seconds: 10),
    this.allowedHosts = const <String>{},
  });
}

/// Abstract search provider interface.
abstract class SearchProvider {
  Future<List<SearchResult>> search(String query, {int maxResults = 5});
  bool get isConfigured;
}

/// Abstract page fetch provider interface.
abstract class PageFetchProvider {
  Future<String> fetchPageText(String url, {Duration? timeout});
}

class SearchResult {
  final String title;
  final String url;
  final String snippet;

  const SearchResult({
    required this.title,
    required this.url,
    this.snippet = '',
  });
}

// ---------------------------------------------------------------------------
// Default implementations
// ---------------------------------------------------------------------------

/// Simple HTTP-based page fetcher (no JS rendering).
class HttpPageFetchProvider implements PageFetchProvider {
  @override
  Future<String> fetchPageText(String url, {Duration? timeout}) async {
    final response = await http
        .get(Uri.parse(url))
        .timeout(timeout ?? const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch page: ${response.statusCode}');
    }

    // Strip HTML tags for basic text extraction
    return response.body
        .replaceAll(RegExp(r'<script[^>]*>[\s\S]*?</script>'), '')
        .replaceAll(RegExp(r'<style[^>]*>[\s\S]*?</style>'), '')
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

/// Placeholder search provider — returns empty results.
/// Users can swap this for a real search API provider.
class NoOpSearchProvider implements SearchProvider {
  @override
  bool get isConfigured => false;

  @override
  Future<List<SearchResult>> search(String query, {int maxResults = 5}) async {
    return [];
  }
}

// ---------------------------------------------------------------------------
// Main service
// ---------------------------------------------------------------------------

class WebAccessService {
  WebToolPolicy policy;
  SearchProvider searchProvider;
  PageFetchProvider pageFetchProvider;

  WebAccessService({
    this.policy = const WebToolPolicy(),
    SearchProvider? searchProvider,
    PageFetchProvider? pageFetchProvider,
  })  : searchProvider = searchProvider ?? NoOpSearchProvider(),
        pageFetchProvider = pageFetchProvider ?? HttpPageFetchProvider();

  /// Whether web access is enabled and a search provider is configured.
  bool get isAvailable => policy.enabled && searchProvider.isConfigured;

  /// Performs a web search if policy allows.
  Future<List<SearchResult>> search(
    String query, {
    int maxResults = 5,
    bool userApproved = false,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) return [];
    if (!policy.enabled) return [];
    if (policy.askBeforeSearch && !userApproved) return [];
    if (!searchProvider.isConfigured) return [];
    return searchProvider.search(normalizedQuery, maxResults: maxResults);
  }

  /// Fetches text content from a URL if policy allows.
  Future<String?> fetchPage(
    String url, {
    bool userApproved = false,
    Duration? timeout,
  }) async {
    if (!policy.enabled) return null;
    if (policy.askBeforeSearch && !userApproved) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    if (policy.allowedHosts.isNotEmpty &&
        !policy.allowedHosts.contains(uri.host)) {
      return null;
    }

    try {
      return await pageFetchProvider.fetchPageText(
        uri.toString(),
        timeout: timeout ?? policy.requestTimeout,
      );
    } catch (e) {
      return null;
    }
  }
}
