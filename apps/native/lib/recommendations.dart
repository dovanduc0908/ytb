import 'dart:math';

typedef Video = Map<String, dynamic>;

/// A small on-device interest model, not a remote identity or analytics profile.
class RecommendationProfile {
  bool enabled = true;
  final Map<String, double> weights = {};
  final Map<String, String> authors = {};
  final Map<String, int> watched = {};
  final Map<String, Video> seeds = {};
  final Set<String> completed = {}, hidden = {};
  final Set<String> finished = {};
  bool excludes(Object? id) => hidden.contains(id) || finished.contains(id);

  bool markFinished(
    Video video,
    num position,
    num duration, {
    bool ended = false,
  }) {
    final id = '${video['id'] ?? ''}';
    if (video['isLive'] == true ||
        duration <= 0 ||
        !RegExp(r'^[\w-]{11}$').hasMatch(id) ||
        (!ended && position < duration * .95)) {
      return false;
    }
    return finished.add(id);
  }

  DateTime updated = DateTime.now();
  static const stop = {
    'the',
    'and',
    'for',
    'with',
    'official',
    'video',
    'music',
    'full',
    'youtube',
    'của',
    'với',
    'những',
    'một',
    'các',
    'trong',
    'này',
    'được',
    'không',
    'tập',
    'phần',
    'nhất',
    'mới',
    'như',
    'đang',
    'hôm',
    'nay',
    'năm',
    'from',
    'this',
    'that',
    'you',
  };
  static final termPattern = RegExp(r'[\p{L}][\p{L}\p{N}]{2,}', unicode: true);
  List<String> terms(Video v) => termPattern
      .allMatches('${v['title'] ?? ''}'.toLowerCase())
      .map((m) => m.group(0)!)
      .where((s) => !stop.contains(s))
      .toSet()
      .take(8)
      .toList();
  void decay(DateTime now) {
    final days = now.difference(updated).inDays;
    if (days > 0) {
      final factor = pow(.96, days);
      weights.updateAll((_, value) => value * factor);
      weights.removeWhere((_, value) => value.abs() < .02);
      updated = now;
    }
  }

  void boost(Video v, double amount) {
    if (!enabled) return;
    final author = '${v['author'] ?? ''}'.trim();
    if (author.isNotEmpty) {
      final key = 'a:${author.toLowerCase()}';
      authors[key] = author;
      weights[key] = ((weights[key] ?? 0) + amount * 2).clamp(-5, 20);
    }
    for (final term in terms(v)) {
      final key = 't:$term';
      weights[key] = ((weights[key] ?? 0) + amount).clamp(-5, 12);
    }
    if (weights.length > 160) {
      final ordered = weights.keys.toList()
        ..sort((a, b) => weights[b]!.abs().compareTo(weights[a]!.abs()));
      weights.removeWhere((key, _) => !ordered.take(160).contains(key));
      authors.removeWhere((key, _) => !weights.containsKey(key));
    }
  }

  /// Returns actual observed viewing time. A seek/speed jump never earns watch time.
  int observe(Video video, Video before, Video after, int elapsedMs) {
    if (!enabled ||
        elapsedMs <= 0 ||
        elapsedMs > 3000 ||
        before['id'] != video['id'] ||
        after['id'] != video['id'] ||
        before['playing'] != true ||
        after['playing'] != true ||
        after['buffering'] == true) {
      return 0;
    }
    final delta =
        (after['position'] as num? ?? 0) - (before['position'] as num? ?? 0);
    final speed = (after['speed'] as num? ?? 1).toDouble();
    if (delta <= 0 || delta > elapsedMs * speed + 750) return 0;
    final id = '${video['id']}';
    final previous = watched[id] ?? 0;
    final credited = min(elapsedMs, max(0, 600000 - previous));
    watched.remove(id);
    watched[id] = previous + credited;
    rememberSeed(video);
    if (watched.length > 250) {
      final oldest = watched.keys.first;
      watched.remove(oldest);
      completed.remove(oldest);
    }
    boost(video, credited / 60000);
    final duration = (after['duration'] as num? ?? 0).toInt();
    if (duration > 0 &&
        (after['position'] as num? ?? 0) >= duration * .85 &&
        watched[id]! >= min(15000, duration ~/ 2) &&
        completed.add(id)) {
      boost(video, 1.5);
    }
    return credited;
  }

  void rememberSeed(Video video) {
    final id = '${video['id'] ?? ''}';
    if (enabled &&
        !hidden.contains(id) &&
        (watched[id] ?? 0) >= 15000 &&
        RegExp(r'^[\w-]{11}$').hasMatch(id)) {
      seeds.remove(id);
      seeds[id] = {
        'id': id,
        'title': '${video['title'] ?? ''}',
        'author': '${video['author'] ?? ''}',
      };
      if (seeds.length > 50) seeds.remove(seeds.keys.first);
    }
  }

  void dismiss(Video video) {
    hidden.add('${video['id']}');
    seeds.remove('${video['id']}');
    if (hidden.length > 1500) hidden.remove(hidden.first);
    boost(video, -1.5);
  }

  /// Recent engaged videos from different creators give discovery a useful mix.
  List<Video> get discoverySeeds {
    if (!enabled) return [];
    final result = <Video>[];
    final creators = <String>{};
    for (final video in seeds.values.toList().reversed) {
      final creator = '${video['author'] ?? ''}'.trim().toLowerCase();
      if (creator.isNotEmpty && !creators.add(creator)) continue;
      result.add(video);
      if (result.length == 3) break;
    }
    return result;
  }

  List<String> get queries {
    if (!enabled) return [];
    final keys = weights.keys.where((k) => weights[k]! > .15).toList()
      ..sort((a, b) => weights[b]!.compareTo(weights[a]!));
    final result = <String>[];
    for (final key in keys.where((k) => k.startsWith('a:')).take(3)) {
      result.add(authors[key] ?? key.substring(2));
    }
    final words = keys
        .where((k) => k.startsWith('t:'))
        .take(4)
        .map((k) => k.substring(2))
        .toList();
    if (words.length >= 2) result.add(words.take(2).join(' '));
    return result;
  }

  double score(Video v, int day) {
    var value = 1 / (1 + (v['rank'] as num? ?? 20) / 10);
    if (enabled) {
      if (v['personalRelated'] == true) value += 3;
      value += weights['a:${'${v['author'] ?? ''}'.toLowerCase()}'] ?? 0;
      for (final term in terms(v)) {
        value += (weights['t:$term'] ?? 0) * .25;
      }
      if ((watched['${v['id']}'] ?? 0) > 20000) value -= 3;
    }
    // Stable daily variety without random reorder during scroll.
    value +=
        (('${v['id']}$day'.codeUnits.fold(
              0,
              (a, b) => (a * 31 + b) & 0x7fffffff,
            )) %
            100) /
        1000;
    return value;
  }

  List<Video> rank(
    Iterable<Video> candidates, {
    int limit = 24,
    DateTime? now,
  }) {
    final day = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 86400000;
    final unique = <String, Video>{};
    for (final v in candidates) {
      if (!excludes(v['id'])) unique.putIfAbsent('${v['id']}', () => v);
    }
    // Tokenize and score each candidate once, rather than at every sort comparison.
    final scores = {for (final v in unique.values) v['id']: score(v, day)};
    final sorted = unique.values.toList()
      ..sort((a, b) {
        final order = scores[b['id']]!.compareTo(scores[a['id']]!);
        return order != 0 ? order : '${a['id']}'.compareTo('${b['id']}');
      });
    final result = <Video>[], deferred = <Video>[];
    final counts = <String, int>{};
    for (final v in sorted) {
      final a = '${v['author']}';
      if ((counts[a] ?? 0) >= 2) {
        deferred.add(v);
        continue;
      }
      result.add(v);
      counts[a] = (counts[a] ?? 0) + 1;
      if (result.length == limit) return result;
    }
    return [...result, ...deferred].take(limit).toList();
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'weights': weights,
    'authors': authors,
    'watched': watched,
    'seeds': seeds.values.toList(),
    'completed': completed.toList(),
    'hidden': hidden.toList(),
    'finished': finished.toList(),
    'updated': updated.toIso8601String(),
  };
  static RecommendationProfile fromJson(Map<String, dynamic> data) {
    final p = RecommendationProfile()..enabled = data['enabled'] != false;
    p.weights.addAll(
      (data['weights'] as Map? ?? {}).map(
        (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
      ),
    );
    p.authors.addAll(Map<String, String>.from(data['authors'] as Map? ?? {}));
    p.watched.addAll(
      (data['watched'] as Map? ?? {}).map(
        (k, v) => MapEntry(k.toString(), (v as num).toInt()),
      ),
    );
    for (final raw in (data['seeds'] as List? ?? [])) {
      if (raw is! Map) continue;
      final video = Map<String, dynamic>.from(raw);
      final id = '${video['id'] ?? ''}';
      if (RegExp(r'^[\w-]{11}$').hasMatch(id)) p.seeds[id] = video;
    }
    p.completed.addAll((data['completed'] as List? ?? []).cast<String>());
    p.hidden.addAll((data['hidden'] as List? ?? []).cast<String>());
    p.finished.addAll((data['finished'] as List? ?? []).cast<String>());
    p.updated = DateTime.tryParse('${data['updated']}') ?? DateTime.now();
    p.decay(DateTime.now());
    return p;
  }
}
