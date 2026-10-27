import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const tvBridge = MethodChannel('ytb/tv');

class TvSheet extends StatefulWidget {
  const TvSheet({super.key, required this.connected, required this.name});
  final bool connected;
  final String name;
  @override
  State<TvSheet> createState() => _TvSheetState();
}

class _TvSheetState extends State<TvSheet> {
  List<Map<String, dynamic>> devices = [];
  bool scanning = false, pairing = false;
  String? error;
  @override
  void initState() {
    super.initState();
    if (!widget.connected) scan();
  }

  Future<void> scan() async {
    setState(() {
      scanning = true;
      error = null;
    });
    try {
      final raw = await tvBridge.invokeListMethod('scan');
      if (mounted) {
        setState(
          () => devices = (raw ?? [])
              .map((v) => Map<String, dynamic>.from(v))
              .toList(),
        );
      }
    } on PlatformException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => scanning = false);
    }
  }

  Future<void> pair([Map<String, dynamic>? device]) async {
    final host = TextEditingController(
      text: device == null ? '' : '${device['address']}:${device['port']}',
    );
    final pin = TextEditingController();
    final input = await showDialog<Map<String, String>>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(device?['name'] ?? 'Nhập địa chỉ trên TV'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (device == null)
              TextField(
                controller: host,
                decoration: const InputDecoration(
                  labelText: 'Địa chỉ IP:cổng trên TV',
                ),
                keyboardType: TextInputType.url,
              ),
            const SizedBox(height: 12),
            TextField(
              controller: pin,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(labelText: 'Mã 6 số trên TV'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, {
              'host': host.text.trim(),
              'pin': pin.text.trim(),
            }),
            child: const Text('Kết nối'),
          ),
        ],
      ),
    );
    Future.delayed(const Duration(seconds: 1), () {
      host.dispose();
      pin.dispose();
    });
    if (input == null || !mounted) return;
    final parts = input['host']!.split(':');
    if (parts.length != 2 || int.tryParse(parts.last) == null) {
      setState(() => error = 'Nhập đúng địa chỉ IP:cổng hiện trên TV.');
      return;
    }
    setState(() {
      pairing = true;
      error = null;
    });
    try {
      final result = await tvBridge.invokeMapMethod<String, dynamic>('pair', {
        'address': parts.first,
        'port': int.parse(parts.last),
        'pin': input['pin'],
        'name': device?['name'] ?? 'Diu Túp TV',
      });
      if (mounted) Navigator.pop(context, result);
    } on PlatformException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => pairing = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Kết nối TV',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          if (widget.connected) ...[
            Text('Đang phát trên ${widget.name}'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                final result = await tvBridge.invokeMapMethod<String, dynamic>(
                  'disconnect',
                );
                if (context.mounted) Navigator.pop(context, result);
              },
              child: const Text('Ngắt TV và trở về điện thoại'),
            ),
          ] else ...[
            const Text(
              'Android TV / Google TV / Fire TV chạy Fire OS: cài APK Diu Túp lên TV, mở ứng dụng và dùng cùng mạng Wi-Fi. TV tự tải video; điện thoại là điều khiển.',
            ),
            const SizedBox(height: 12),
            if (scanning || pairing) const LinearProgressIndicator(),
            ...devices.map(
              (d) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.tv),
                title: Text(d['name']),
                subtitle: Text('${d['address']}'),
                onTap: pairing ? null : () => pair(d),
              ),
            ),
            if (!scanning && devices.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Chưa thấy TV đã mở Diu Túp. Bạn có thể nhập địa chỉ hiện trên TV.',
                ),
              ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: scanning ? null : scan,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tìm lại'),
                ),
                TextButton(
                  onPressed: pairing ? null : () => pair(),
                  child: const Text('Nhập địa chỉ TV'),
                ),
              ],
            ),
            const Divider(),
            const Text(
              'TV khác: dùng tính năng phản chiếu của điện thoại nếu TV hỗ trợ. Cách này cần điện thoại tiếp tục phát.',
            ),
            TextButton.icon(
              onPressed: () async {
                try {
                  await tvBridge.invokeMethod('mirror');
                } on PlatformException catch (e) {
                  if (mounted) setState(() => error = e.message);
                }
              },
              icon: const Icon(Icons.screen_share_outlined),
              label: const Text('Mở kết nối màn hình hệ thống'),
            ),
          ],
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(error!, style: const TextStyle(color: Colors.orange)),
            ),
        ],
      ),
    ),
  );
}
