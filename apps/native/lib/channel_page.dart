import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'recommendations.dart';
import 'video_meta.dart';

class ChannelPage extends StatefulWidget {
  const ChannelPage({super.key, required this.video, required this.onPlay});
  final Video video;
  final ValueChanged<Video> onPlay;
  @override
  State<ChannelPage> createState() => _ChannelPageState();
}

class _ChannelPageState extends State<ChannelPage> {
  static const source = MethodChannel('ytb/source');
  final scroll = ScrollController();
  final items = <Video>[];
  final ids = <String>{}, tokens = <String>{};
  String? channelId, continuation, error;
  String title = '', description = '', avatar = '';
  bool loading = false, more = true, loaded = false;
  @override
  void initState() {
    super.initState();
    title = '${widget.video['author'] ?? 'Kênh'}';
    channelId = widget.video['channelId'] as String?;
    scroll.addListener(() {
      if (scroll.position.extentAfter < 500 && error == null) load();
    });
    load();
  }

  Future<void> load() async {
    if (loading || !more) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (channelId == null || channelId!.isEmpty) {
        final data = await source.invokeMapMethod<String, dynamic>('resolve', {
          'id': widget.video['id'],
        });
        channelId = data?['channelId'] as String?;
      }
      if (channelId == null || channelId!.isEmpty) {
        throw StateError('No channel');
      }
      final data = await source.invokeMapMethod<String, dynamic>('channel', {
        'id': channelId,
        if (continuation != null) 'continuation': continuation,
      });
      if (!mounted) return;
      setState(() {
        if (!loaded) {
          title = data?['title'] as String? ?? title;
          description = data?['description'] as String? ?? '';
          avatar = data?['avatar'] as String? ?? '';
        }
        for (final raw in data?['videos'] as List? ?? []) {
          final video = Video.from(raw);
          if (ids.add('${video['id']}')) {
            items.add({...video, 'author': title, 'channelId': channelId});
          }
        }
        continuation = data?['continuation'] as String?;
        more = continuation != null && tokens.add(continuation!);
        loaded = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Chưa mở được kênh. Kiểm tra mạng và thử lại.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: ListView(
      controller: scroll,
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (avatar.isNotEmpty)
                CircleAvatar(radius: 32, backgroundImage: NetworkImage(avatar)),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              if (description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    description,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const SizedBox(height: 20),
              const Text(
                'Video của kênh',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        for (final video in items)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: SizedBox(
              width: 100,
              height: 60,
              child: Image.network(
                '${video['thumbnail']}',
                fit: BoxFit.cover,
                errorBuilder: (_, error, stack) =>
                    const Icon(Icons.play_circle_outline),
              ),
            ),
            title: Text(
              '${video['title']}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(viewsLabel(video), maxLines: 1),
            onTap: () {
              Navigator.pop(context);
              widget.onPlay(video);
            },
          ),
        if (loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(error!),
                TextButton(onPressed: load, child: const Text('Thử lại')),
              ],
            ),
          ),
        if (!loading && error == null && more)
          TextButton(onPressed: load, child: const Text('Tải thêm video')),
        if (loaded && items.isEmpty && !loading && error == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Kênh chưa có video công khai trong mục này.'),
          ),
      ],
    ),
  );
}
