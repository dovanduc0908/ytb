import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Autocomplete is independent of video extraction and never submits while typing.
class VideoSearchBox extends StatefulWidget {
  const VideoSearchBox({
    super.key,
    required this.controller,
    required this.onSearch,
    this.onFocusChanged,
    this.onPreview,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSearch;
  final ValueChanged<bool>? onFocusChanged;
  final ValueChanged<String>? onPreview;

  @override
  State<VideoSearchBox> createState() => _VideoSearchBoxState();
}

class _VideoSearchBoxState extends State<VideoSearchBox> {
  static const channel = MethodChannel('ytb/source');
  final focus = FocusNode();
  Timer? debounce, preview;
  int generation = 0;
  List<String> recent = [], suggestions = [];
  bool waiting = false, failed = false;
  String? lastInput;
  SharedPreferences? prefs;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(changed);
    focus.addListener(focusChanged);
    loadRecent();
  }

  Future<void> loadRecent() async {
    final storage = await SharedPreferences.getInstance();
    if (!mounted) return;
    prefs = storage;
    setState(() => recent = storage.getStringList('recentSearches') ?? []);
  }

  void focusChanged() {
    widget.onFocusChanged?.call(focus.hasFocus);
    if (focus.hasFocus) {
      lastInput = null;
      changed();
    } else {
      debounce?.cancel();
      preview?.cancel();
      generation++;
      setState(() => waiting = false);
    }
  }

  void changed() {
    final query = widget.controller.text.trim();
    if (lastInput == query) return;
    lastInput = query;
    debounce?.cancel();
    preview?.cancel();
    final seq = ++generation;
    setState(() {
      suggestions = [];
      failed = false;
      waiting = focus.hasFocus && query.isNotEmpty;
    });
    // Observe the displayed text without changing IME composition; skip URLs.
    if (!focus.hasFocus || query.isEmpty || query.startsWith('http')) {
      waiting = false;
      return;
    }
    preview = Timer(const Duration(milliseconds: 400), () {
      if (mounted && focus.hasFocus && seq == generation && query.length >= 3) {
        widget.onPreview?.call(query);
      }
    });
    debounce = Timer(const Duration(milliseconds: 120), () async {
      try {
        final data = await channel
            .invokeMapMethod<String, dynamic>('suggest', {'query': query})
            .timeout(const Duration(seconds: 5));
        if (!mounted || seq != generation || !focus.hasFocus) return;
        setState(() {
          suggestions = (data?['suggestions'] as List? ?? []).cast<String>();
          waiting = false;
        });
      } catch (_) {
        if (!mounted || seq != generation || !focus.hasFocus) return;
        setState(() {
          failed = true;
          waiting = false;
        });
      }
    });
  }

  void submit(String raw) {
    final query = raw.trim();
    if (query.isEmpty) return;
    debounce?.cancel();
    preview?.cancel();
    generation++;
    focus.unfocus();
    widget.controller.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    if (!query.startsWith('http')) {
      recent = [
        query,
        ...recent.where((s) => s.toLowerCase() != query.toLowerCase()),
      ].take(20).toList();
      prefs?.setStringList('recentSearches', recent);
    }
    setState(() {
      suggestions = [];
      waiting = false;
    });
    widget.onSearch(query);
  }

  @override
  void dispose() {
    debounce?.cancel();
    preview?.cancel();
    generation++;
    widget.controller.removeListener(changed);
    focus.removeListener(focusChanged);
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = widget.controller.text.trim().toLowerCase();
    final local = recent
        .where((s) => s.toLowerCase().startsWith(query))
        .take(3);
    final options = <String>{...local, ...suggestions}.take(8).toList();
    return TextFieldTapRegion(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('video-search-input'),
            controller: widget.controller,
            focusNode: focus,
            textInputAction: TextInputAction.search,
            maxLength: 200,
            onSubmitted: submit,
            onTapOutside: (_) => focus.unfocus(),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'Tìm video hoặc dán link YouTube',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.controller.text.isNotEmpty)
                    IconButton(
                      tooltip: 'Xóa từ khóa',
                      onPressed: () {
                        widget.controller.clear();
                        focus.requestFocus();
                      },
                      icon: const Icon(Icons.close, size: 20),
                    ),
                  IconButton(
                    tooltip: 'Tìm kiếm',
                    onPressed: () => submit(widget.controller.text),
                    icon: const Icon(Icons.arrow_forward),
                  ),
                ],
              ),
            ),
          ),
          if (focus.hasFocus) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      query.isEmpty ? 'Tìm kiếm gần đây' : 'Gợi ý tìm kiếm',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  if (waiting)
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                  if (query.isEmpty && recent.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        setState(() => recent = []);
                        prefs?.remove('recentSearches');
                      },
                      child: const Text('Xóa lịch sử tìm kiếm'),
                    ),
                ],
              ),
            ),
            if (options.isNotEmpty)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .32,
                ),
                child: ListView.builder(
                  key: const Key('search-suggestions'),
                  shrinkWrap: true,
                  primary: false,
                  padding: EdgeInsets.zero,
                  itemCount: options.length,
                  itemBuilder: (context, i) => ListTile(
                    dense: true,
                    leading: Icon(
                      recent.contains(options[i])
                          ? Icons.history
                          : Icons.search,
                      size: 20,
                    ),
                    title: Text(
                      options[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => submit(options[i]),
                    trailing: IconButton(
                      tooltip: 'Điền ${options[i]}',
                      onPressed: () {
                        widget.controller.value = TextEditingValue(
                          text: options[i],
                          selection: TextSelection.collapsed(
                            offset: options[i].length,
                          ),
                        );
                        focus.requestFocus();
                      },
                      icon: const Icon(Icons.north_west, size: 18),
                    ),
                  ),
                ),
              )
            else if (!waiting)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  failed
                      ? 'Chưa tải được gợi ý. Bạn vẫn có thể bấm tìm kiếm.'
                      : query.isEmpty
                      ? 'Gõ tên video, bài hát hoặc kênh.'
                      : 'Bấm tìm kiếm để xem video.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
