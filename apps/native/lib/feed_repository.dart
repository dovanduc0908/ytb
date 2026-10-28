import 'dart:async';

import 'package:flutter/services.dart';

import 'recommendations.dart';

typedef SourceRequest = Future<Map<String, dynamic>> Function(
  String method,
  Map<String, dynamic> args,
);

class FeedPage {
  const FeedPage(this.videos, this.hasMore, [this.error]);
  final List<Video> videos;
  final bool hasMore;
  final Object? error;
}

class _Cursor {
  _Cursor(this.query, this.region, {this.personal = false});
  final String query, region;
  final bool personal;
  String? token;
  bool started = false, exhausted = false;
}

/// Per-refresh cursor state. No daily page quota; stop only when sources end.
class FeedRepository {
  FeedRepository(this.profile, this.mode, {SourceRequest? request})
    : request = request ?? nativeRequest {
    if (mode == 'forYou') {
      for (final q in profile.queries) {
        _cursors.add(_Cursor(q, 'VN', personal: true));
      }
    }
    const vn = [
      'công nghệ',
      'ẩm thực Việt Nam',
      'du lịch Việt Nam',
      'khoa học',
      'âm nhạc Việt Nam',
      'bóng đá',
      'phim tài liệu',
      'trò chơi',
      'sáng tạo',
      'khám phá thiên nhiên',
      'văn hóa',
      'lập trình',
    ];
    const world = [
      'technology',
      'science documentary',
      'travel',
      'cooking',
      'music',
      'football highlights',
      'gaming',
      'animation',
      'nature documentary',
      'space exploration',
      'art design',
      'programming',
    ];
    final day = DateTime.now().millisecondsSinceEpoch ~/ 86400000;
    if (mode != 'world') {
      for (var i = 0; i < vn.length; i++) {
        _cursors.add(_Cursor(vn[(i + day) % vn.length], 'VN'));
      }
    }
    if (mode != 'vn') {
      for (var i = 0; i < world.length; i++) {
        _cursors.add(
          _Cursor(world[(i + day) % world.length], i.isEven ? 'US' : 'GB'),
        );
      }
    }
  }
  final RecommendationProfile profile;
  final String mode;
  final SourceRequest request;
  final List<_Cursor> _cursors = [];
  final Map<String, Video> pool = {};
  final Set<String> seen = {};
  int cursorIndex = 0;
  bool initialized = false;
  Future<void>? initialLoad;
  Object? lastError;
  static Future<Map<String, dynamic>> nativeRequest(
    String method,
    Map<String, dynamic> args,
  ) async => Map<String, dynamic>.from(
    await const MethodChannel('ytb/source').invokeMethod(method, args),
  );

  void add(
    List<dynamic> items,
    String reason, {
    bool stale = false,
    bool personalRelated = false,
  }) {
    for (final item in items) {
      final v = Map<String, dynamic>.from(item as Map);
      final id = '${v['id']}';
      if (!RegExp(r'^[\w-]{11}$').hasMatch(id) ||
          seen.contains(id) ||
          profile.excludes(id)) {
        continue;
      }
      if (personalRelated && pool.containsKey(id)) {
        pool[id] = {...pool[id]!, 'reason': reason, 'personalRelated': true};
      } else {
        pool.putIfAbsent(
          id,
          () => {
            ...v,
            'reason': reason,
            'stale': stale,
            if (personalRelated) 'personalRelated': true,
          },
        );
      }
    }
  }

  Future<void> _related(Video seed) async {
    try {
      final data = await request('related', {'id': seed['id']});
      final items = (data['videos'] as List? ?? [])
          .where((v) => v is Map && v['id'] != seed['id'])
          .toList();
      add(items, 'Dựa trên video bạn đã xem', personalRelated: true);
    } catch (_) {
      // Related results are optional; search and charts still supply the feed.
    }
  }

  Future<void> chart(String region) async {
    try {
      final data = await request('charts', {'region': region});
      final date = '${data['chartDate'] ?? ''}';
      add(
        data['videos'] as List? ?? [],
        'BXH âm nhạc ${region == 'VN' ? 'Việt Nam' : 'thế giới'} · $date',
        stale: data['stale'] == true,
      );
    } catch (e) {
      lastError = e;
    }
  }

  Future<void> _fill(_Cursor c) async {
    if (c.exhausted) return;
    try {
      final data = await request('discover', {
        'query': c.query,
        'region': c.region,
        'popular': !c.personal,
        if (c.token != null) 'continuation': c.token,
      });
      add(
        data['videos'] as List? ?? [],
        c.personal ? 'Theo nội dung bạn thường xem' : 'Khám phá · ${c.query}',
      );
      final next = data['continuation'] as String?;
      c.exhausted = next == null || next.isEmpty || next == c.token;
      c.token = next;
      c.started = true;
    } catch (e) {
      lastError = e;
    }
  }

  Future<FeedPage> next() async {
    lastError = null;
    pool.removeWhere((id, _) => profile.excludes(id));
    if (!initialized) {
      initialized = true;
      final load = Future.wait([
        if (mode != 'world') chart('VN'),
        if (mode != 'vn') chart('GLOBAL'),
        if (mode == 'forYou') ...profile.discoverySeeds.map(_related),
        ..._cursors.where((c) => c.personal).take(2).map(_fill),
        ..._cursors.where((c) => !c.personal).take(1).map(_fill),
        if (mode == 'forYou')
          ..._cursors.where((c) => c.region == 'US').take(1).map(_fill),
      ]).then((_) {});
      initialLoad = load;
      unawaited(load.whenComplete(() => initialLoad = null));
      // Do not make a usable first page wait for the slowest source.
      try {
        await load.timeout(const Duration(milliseconds: 1200));
      } on TimeoutException {
        if (pool.isEmpty) await load;
      }
    }
    // The initial requests own their cursors until they complete.
    if (pool.isEmpty && initialLoad != null) await initialLoad;
    for (
      var attempt = 0;
      initialLoad == null &&
          (pool.length < 24 ||
              pool.values
                      .where((v) => '${v['reason']}'.startsWith('Khám phá'))
                      .length <
                  6) &&
          attempt < 3;
      attempt++
    ) {
      final candidates = <_Cursor>[];
      for (var i = 0; i < _cursors.length && candidates.length < 2; i++) {
        final c = _cursors[cursorIndex++ % _cursors.length];
        if (!c.exhausted) candidates.add(c);
      }
      if (candidates.isEmpty) break;
      await Future.wait(candidates.map(_fill));
      if (lastError != null && pool.isEmpty) break;
    }
    final explore = profile.rank(
      pool.values.where((v) => '${v['reason']}'.startsWith('Khám phá')),
      limit: 6,
    );
    final exploreIds = explore.map((v) => v['id']).toSet();
    final result = [
      ...profile.rank(
        pool.values.where((v) => !exploreIds.contains(v['id'])),
        limit: 24 - explore.length,
      ),
      ...explore,
    ];
    for (final v in result) {
      seen.add('${v['id']}');
      pool.remove(v['id']);
    }
    // Bound only the dedupe index, never the user's daily viewing quota.
    if (seen.length > 10000) seen.removeAll(seen.take(2000).toList());
    return FeedPage(
      result,
      initialLoad != null ||
          pool.isNotEmpty ||
          _cursors.any((c) => !c.exhausted),
      result.isEmpty ? lastError : null,
    );
  }
}
