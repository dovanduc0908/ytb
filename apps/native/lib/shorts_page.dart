import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'feed_repository.dart';
import 'recommendations.dart';
import 'player_overlay.dart';
import 'video_meta.dart';

class ShortsPage extends StatefulWidget {
  const ShortsPage({
    super.key,
    required this.open,
    required this.surface,
    required this.activeId,
    required this.ready,
    required this.playing,
    required this.toggle,
    required this.save,
    required this.settings,
    required this.profile,
    this.playbackError,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.activeVideo,
    this.onChannel,
  });
  final Future<void> Function(Video) open;
  final Widget Function() surface;
  final String? activeId;
  final bool ready, playing;
  final VoidCallback toggle, settings;
  final ValueChanged<Video> save;
  final RecommendationProfile profile;
  final String? playbackError;
  final int position, duration;
  final ValueChanged<int> onSeek;
  final Video? activeVideo;
  final ValueChanged<Video>? onChannel;
  @override
  State<ShortsPage> createState() => _ShortsPageState();
}

class _ShortsPageState extends State<ShortsPage> {
  final pages = PageController();
  final items = <Video>[], seen = <String>{};
  String? token, error;
  bool loading = false, more = true;
  int index = 0, branch = 0;
  late final List<String> queries = <String>{
    ...widget.profile.queries.take(3),
    'Việt Nam',
    'hài vui',
    'ẩm thực',
    'du lịch',
    'music',
    'science',
    'animals',
    'football',
    'technology',
  }.toList();
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (loading || !more) return;
    setState(() => loading = true);
    final before = items.length;
    try {
      for (
        var attempt = 0;
        attempt < 3 && items.length == before && branch < queries.length;
        attempt++
      ) {
        final d = await FeedRepository.nativeRequest('shorts', {
          'query': queries[branch],
          if (token != null) 'continuation': token,
        });
        if (!mounted) return;
        for (final raw in d['videos'] as List? ?? []) {
          final v = Map<String, dynamic>.from(raw);
          if (v['isShort'] == true &&
              !widget.profile.excludes(v['id']) &&
              seen.add('${v['id']}')) {
            items.add(v);
          }
        }
        final next = d['continuation'] as String?;
        if (next == null || next == token) {
          branch++;
          token = null;
        } else {
          token = next;
        }
      }
      if (!mounted) return;
      setState(() {
        loading = false;
        more = branch < queries.length;
        error = null;
      });
      if (index >= before && index < items.length) play(index);
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Chưa tải được Shorts. Bấm thử lại.';
        });
      }
    }
  }

  void play(int i) {
    setState(() => index = i);
    if (i >= items.length) {
      load();
      return;
    }
    unawaited(widget.open(items[i]));
    unawaited(
      const MethodChannel('ytb/source')
          .invokeMethod('prefetch', {
            'ids': items.skip(i + 1).take(2).map((v) => v['id']).toList(),
          })
          .catchError((_) => null),
    );
    if (items.length - i < 5) load();
  }

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: loading
            ? const CircularProgressIndicator()
            : TextButton(
                onPressed: load,
                child: Text(error ?? 'Chưa có Shorts phù hợp. Tải lại'),
              ),
      );
    }
    return PageView.builder(
      controller: pages,
      scrollDirection: Axis.vertical,
      onPageChanged: play,
      itemCount: items.length + (more ? 1 : 0),
      itemBuilder: (_, i) {
        if (i >= items.length) {
          return Center(
            child: loading
                ? const CircularProgressIndicator()
                : TextButton(
                    onPressed: load,
                    child: Text(error ?? 'Tải thêm Shorts'),
                  ),
          );
        }
        final v = <String, dynamic>{
          ...items[i],
          if (widget.activeVideo?['id'] == items[i]['id'])
            ...widget.activeVideo!,
        };
        final live = i == index && widget.activeId == v['id'];
        return Stack(
          fit: StackFit.expand,
          children: [
            if (live)
              widget.surface()
            else
              Image.network(
                v['thumbnail'],
                fit: BoxFit.contain,
                errorBuilder: (_, e, s) =>
                    const ColoredBox(color: Colors.black),
              ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.toggle,
              child: const SizedBox.expand(),
            ),
            if (live && !widget.ready && widget.playbackError == null)
              const Center(child: CircularProgressIndicator()),
            if (live && widget.playbackError != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.playbackError!, textAlign: TextAlign.center),
                      TextButton(
                        onPressed: () => play(i),
                        child: const Text('Thử lại'),
                      ),
                    ],
                  ),
                ),
              ),
            if (live && widget.duration > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SizedBox(
                  height: 24,
                  child: SeekSlider(
                    position: widget.position.toDouble(),
                    duration: widget.duration.toDouble(),
                    onSeek: widget.onSeek,
                  ),
                ),
              ),
            if (live && widget.ready && !widget.playing)
              const IgnorePointer(
                child: Center(child: Icon(Icons.play_arrow, size: 70)),
              ),
            Positioned(
              left: 16,
              right: 70,
              bottom: 24,
              child: Text(
                '${v['title']}\n${v['author'] ?? ''}\n${viewsLabel(v)}',
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                ),
              ),
            ),
            Positioned(
              right: 8,
              bottom: 26,
              child: Column(
                children: [
                  IconButton(
                    tooltip: 'Xem kênh người đăng',
                    onPressed: () => widget.onChannel?.call(v),
                    icon: const Icon(Icons.account_circle_outlined),
                  ),
                  IconButton(
                    tooltip: 'Lưu Short',
                    onPressed: () => widget.save(v),
                    icon: const Icon(Icons.bookmark_add_outlined),
                  ),
                  IconButton(
                    tooltip: 'Tùy chọn phát Shorts',
                    onPressed: widget.settings,
                    icon: const Icon(Icons.tune),
                  ),
                  IconButton(
                    tooltip: 'Không quan tâm Short này',
                    onPressed: () {
                      widget.profile.dismiss(v);
                      if (i + 1 < items.length) {
                        pages.nextPage(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                        );
                      } else {
                        load();
                      }
                    },
                    icon: const Icon(Icons.not_interested),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
