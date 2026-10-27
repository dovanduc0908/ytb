import 'feed_repository.dart';
import 'recommendations.dart';

/// One cursor per video/query; fetching future pages never mutates the home feed.
class RelatedRepository {
  RelatedRepository(this.seed, {this.query = '', SourceRequest? request})
    : request = request ?? FeedRepository.nativeRequest;
  final Video seed;
  final String query;
  final SourceRequest request;
  final seen = <String>{};
  final pool = <Video>[];
  String? token;
  bool ended = false, primary = true;
  int branch = 0;
  final tokens = <String>{};
  List<String> get fallbacks {
    final title = '${seed['title'] ?? ''}'
        .replaceAll(RegExp(r'\[[^\]]*\]|\([^)]*\)'), '')
        .trim();
    final author = '${seed['author'] ?? ''}'.trim();
    final base = query.isNotEmpty ? query : title;
    return <String>{
          base,
          '$base $author'.trim(),
          if (query.isEmpty && author.isNotEmpty) author,
          if (base.toLowerCase().contains('karaoke')) ...[
            '$base beat',
            '$base song ca',
            '$base tông nam',
            '$base tông nữ',
          ],
        }
        .where((q) => q.isNotEmpty)
        .map((q) => q.length > 200 ? q.substring(0, 200) : q)
        .toList();
  }

  Future<FeedPage> next() async {
    Object? error;
    for (
      var attempt = 0;
      pool.length < 24 && !ended && attempt < 3;
      attempt++
    ) {
      try {
        final related = query.isEmpty && primary;
        final queries = fallbacks;
        if (!related && branch >= queries.length) {
          ended = true;
          break;
        }
        final data = await request(related ? 'related' : 'search', {
          if (related) 'id': seed['id'] else 'query': queries[branch],
          if (token != null) 'continuation': token,
        });
        for (final raw in data['videos'] as List? ?? []) {
          final v = Map<String, dynamic>.from(raw);
          final id = '${v['id']}';
          if (id != seed['id'] && seen.add(id)) pool.add(v);
        }
        final next = data['continuation'] as String?;
        if (next == null || next.isEmpty || !tokens.add(next)) {
          token = null;
          tokens.clear();
          if (related) {
            primary = false;
          } else {
            branch++;
          }
          if (!primary && branch >= queries.length) ended = true;
        } else {
          token = next;
        }
      } catch (e) {
        error = e;
        // Related discovery is optional; continue via contextual search.
        if (query.isEmpty && primary) {
          primary = false;
          token = null;
          tokens.clear();
          continue;
        }
        break;
      }
    }
    final result = pool.take(24).toList();
    pool.removeRange(0, result.length);
    return FeedPage(
      result,
      !ended || pool.isNotEmpty,
      result.isEmpty ? error : null,
    );
  }
}
