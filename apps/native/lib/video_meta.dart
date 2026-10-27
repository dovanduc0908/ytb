String viewsLabel(Map<String, dynamic> video) {
  final raw = '${video['views'] ?? ''}'.trim();
  if (raw.isEmpty) return 'Chưa có số lượt xem';
  final count = int.tryParse(raw);
  final text = count == null
      ? raw
      : count.toString().replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
          (match) => '${match[1]}.',
        );
  if (count == null) return text;
  return '$text lượt xem${video['chartDate'] != null ? ' trong kỳ BXH' : ''}';
}
