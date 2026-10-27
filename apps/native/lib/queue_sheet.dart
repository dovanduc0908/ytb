import 'package:flutter/material.dart';

import 'recommendations.dart';

class QueueSheet extends StatefulWidget {
  const QueueSheet({
    super.key,
    required this.initial,
    required this.repeat,
    required this.onChanged,
    required this.onPlay,
    required this.onSave,
  });
  final List<Video> initial;
  final int repeat;
  final Future<void> Function(List<Video>, int) onChanged;
  final ValueChanged<Video> onPlay;
  final ValueChanged<List<Video>> onSave;
  @override
  State<QueueSheet> createState() => _QueueSheetState();
}

class _QueueSheetState extends State<QueueSheet> {
  late List<Video> items = List.of(widget.initial);
  late int repeat = widget.repeat;
  bool busy = false;
  Future<bool> update() async {
    setState(() => busy = true);
    try {
      await widget.onChanged(List.of(items), repeat);
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Hàng đợi đã đổi hoặc TV mất kết nối. Đóng và mở lại hàng đợi để cập nhật.',
            ),
          ),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Hàng đợi',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: 'Trộn hàng đợi',
                  onPressed: busy || items.length < 2
                      ? null
                      : () async {
                          final previous = List<Video>.of(items);
                          setState(() => items.shuffle());
                          if (!await update() && mounted) {
                            setState(() => items = previous);
                          }
                        },
                  icon: const Icon(Icons.shuffle),
                ),
                IconButton(
                  tooltip: 'Lưu danh sách',
                  onPressed: items.isEmpty
                      ? null
                      : () => widget.onSave(List.of(items)),
                  icon: const Icon(Icons.playlist_add),
                ),
                DropdownButton<int>(
                  value: repeat,
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Không lặp')),
                    DropdownMenuItem(value: 1, child: Text('Lặp bài')),
                    DropdownMenuItem(value: 2, child: Text('Lặp danh sách')),
                  ],
                  onChanged: busy
                      ? null
                      : (v) {
                          setState(() => repeat = v!);
                          update();
                        },
                ),
              ],
            ),
          ),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Chọn “Phát tiếp” hoặc “Thêm cuối” ở một video.'),
            ),
          Expanded(
            child: ReorderableListView.builder(
              itemCount: items.length,
              onReorderItem: (old, next) {
                if (busy) return;
                setState(() {
                  items.insert(next, items.removeAt(old));
                });
                update();
              },
              itemBuilder: (_, i) => ListTile(
                key: ValueKey(items[i]['id']),
                leading: ReorderableDragStartListener(
                  index: i,
                  child: const Icon(Icons.drag_handle),
                ),
                title: Text(
                  '${items[i]['title']}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${items[i]['autoMusic'] == true ? 'Gợi ý cho bạn · ' : ''}${items[i]['author'] ?? ''}',
                  maxLines: 1,
                ),
                onTap: busy
                    ? null
                    : () async {
                        final v = items.removeAt(i);
                        if (await update() && context.mounted) {
                          Navigator.pop(context);
                          widget.onPlay(v);
                        }
                      },
                trailing: IconButton(
                  tooltip: 'Xóa khỏi hàng đợi',
                  onPressed: busy
                      ? null
                      : () {
                          setState(() => items.removeAt(i));
                          update();
                        },
                  icon: const Icon(Icons.close),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
