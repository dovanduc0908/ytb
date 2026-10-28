import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'recommendations.dart';
import 'related_repository.dart';
import 'feed_repository.dart';
import 'search_box.dart';

class RelatedPanel extends StatefulWidget {
  const RelatedPanel({
    super.key,
    required this.seed,
    required this.header,
    required this.itemBuilder,
    required this.hidden,
    this.initialQuery = '',
  });
  final Video seed;
  final Widget header;
  final Widget Function(Video) itemBuilder;
  final Set<String> hidden;
  final String initialQuery;
  @override
  State<RelatedPanel> createState() => _RelatedPanelState();
}

class _RelatedPanelState extends State<RelatedPanel> {
  final scroll = ScrollController(), input = TextEditingController();
  late RelatedRepository repo;
  Future<FeedPage>? prepared;
  final items = <Video>[];
  bool loading = false, more = true;
  String? error;
  int generation = 0;
  String mode = 'Liên quan';
  @override
  void initState() {
    super.initState();
    scroll.addListener(scrolled);
    reset(widget.initialQuery);
  }

  @override
  void didUpdateWidget(covariant RelatedPanel old) {
    super.didUpdateWidget(old);
    if (old.seed['id'] != widget.seed['id'] ||
        old.initialQuery != widget.initialQuery) {
      reset(widget.initialQuery);
    }
  }

  void scrolled() {
    if (scroll.hasClients &&
        scroll.position.extentAfter < 900 &&
        !loading &&
        more &&
        error == null) {
      load();
    }
  }

  void reset(String query) {
    generation++;
    repo = RelatedRepository(widget.seed, query: query);
    prepared = null;
    items.clear();
    more = true;
    loading = false;
    error = null;
    if (scroll.hasClients) scroll.jumpTo(0);
    load();
  }

  Future<void> load() async {
    if (loading || !more) return;
    final seq = generation;
    final current = repo;
    setState(() => loading = true);
    final page = await (prepared ?? current.next());
    if (!mounted || seq != generation) return;
    prepared = null;
    setState(() {
      items.addAll(page.videos.where((v) => !widget.hidden.contains(v['id'])));
      more = page.hasMore;
      loading = false;
      error = page.error != null
          ? 'Chưa tải được video. Bấm thử lại.'
          : page.videos.isEmpty && more
          ? 'Chưa có kết quả mới. Bấm tải tiếp.'
          : null;
    });
    if (more && error == null) prepared = current.next();
    if (items.length <= 24) warm(items);
  }

  void warm(List<Video> cards) {
    unawaited(
      const MethodChannel('ytb/source')
          .invokeMethod('prefetch', {
            'ids': cards.take(2).map((v) => v['id']).toList(),
          })
          .catchError((_) => null),
    );
  }

  @override
  void dispose() {
    generation++;
    scroll.dispose();
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visibleItems = items
        .where((v) => !widget.hidden.contains(v['id']))
        .toList();
    return CustomScrollView(
      key: const Key('related-scroll'),
      controller: scroll,
      slivers: [
        SliverToBoxAdapter(child: widget.header),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tìm bài tiếp theo',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                VideoSearchBox(
                  controller: input,
                  onSearch: (q) {
                    mode = 'Tìm kiếm';
                    reset(q);
                  },
                  onPreview: (q) =>
                      const MethodChannel('ytb/source')
                          .invokeMethod('previewSearch', {'query': q}),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children:
                        [
                              'Liên quan',
                              'Karaoke',
                              'Beat',
                              'Tông nam',
                              'Tông nữ',
                              'Song ca',
                            ]
                            .map(
                              (label) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(label),
                                  selected: mode == label,
                                  onSelected: (_) {
                                    setState(() => mode = label);
                                    final base = input.text.trim().isEmpty
                                        ? '${widget.seed['title'] ?? ''}'
                                        : input.text.trim();
                                    reset(
                                      label == 'Liên quan'
                                          ? ''
                                          : '$base ${label == 'Karaoke' ? 'karaoke' : 'karaoke $label'}',
                                    );
                                  },
                                ),
                              ),
                            )
                            .toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverList.builder(
          itemCount: visibleItems.length,
          itemBuilder: (_, i) => widget.itemBuilder(visibleItems[i]),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      if (error != null) Text(error!),
                      if (more)
                        TextButton(
                          onPressed: () {
                            error = null;
                            load();
                          },
                          child: const Text('Tải thêm video'),
                        )
                      else
                        const Text(
                          'Đã hết kết quả phù hợp. Bạn có thể tìm bài khác.',
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
