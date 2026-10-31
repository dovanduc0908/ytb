import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';

import 'youtube_account.dart';

class YoutubeAccountPage extends StatefulWidget {
  const YoutubeAccountPage({super.key});
  @override
  State<YoutubeAccountPage> createState() => _YoutubeAccountPageState();
}

class _YoutubeAccountPageState extends State<YoutubeAccountPage> {
  GoogleSignInAccount? account;
  YoutubeAccountApi? api;
  List<Map<String, dynamic>> subscriptions = [], playlists = [], likes = [];
  bool busy = false;
  String? error;
  int generation = 0;

  @override
  void dispose() {
    generation++;
    api?.close();
    super.dispose();
  }

  Future<void> connect() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kết nối YouTube'),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Chỉ đọc kênh đăng ký, playlist và video đã thích. Không thay đổi tài khoản YouTube. Dữ liệu chỉ giữ trong bộ nhớ phiên này, không gửi tới máy chủ riêng. Video sẽ mở bằng YouTube. Bạn có thể ngắt kết nối và thu hồi quyền bất cứ lúc nào.',
            ),
            TextButton(
              onPressed: () => open(
                Uri.parse('https://diutup.duckdns.org/privacy.html'),
              ),
              child: const Text('Chính sách quyền riêng tư Diu Túp'),
            ),
            TextButton(
              onPressed: () =>
                  open(Uri.parse('https://www.youtube.com/t/terms')),
              child: const Text('Điều khoản dịch vụ YouTube'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Tiếp tục với Google'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    final switchAccount = account != null;
    final epoch = ++generation;
    setState(() {
      busy = true;
      error = null;
      subscriptions = [];
      playlists = [];
      likes = [];
      account = null;
    });
    api?.close();
    api = null;
    try {
      final user = await YoutubeAccountLogin.authenticate(
        switchAccount: switchAccount,
      );
      if (!mounted || epoch != generation) return;
      final authorization =
          await user.authorizationClient.authorizationForScopes(
            YoutubeAccountLogin.scopes,
          ) ??
          await user.authorizationClient.authorizeScopes(
            YoutubeAccountLogin.scopes,
          );
      if (!mounted || epoch != generation) return;
      api = YoutubeAccountApi(authorization.accessToken);
      account = user;
      await load(epoch);
    } on GoogleSignInException catch (e) {
      if (mounted && epoch == generation) {
        setState(
          () => error = e.code == GoogleSignInExceptionCode.canceled
              ? 'Đã hủy đăng nhập.'
              : 'Google chưa cho phép đăng nhập. Kiểm tra cấu hình OAuth hoặc thử lại.',
        );
      }
    } catch (e) {
      if (mounted && epoch == generation) {
        setState(
          () => error = e is YoutubeAccountError
              ? e.message
              : 'Không kết nối được. Hãy kiểm tra mạng và thử lại.',
        );
      }
    } finally {
      if (mounted && epoch == generation) setState(() => busy = false);
    }
  }

  Future<void> load(int epoch) async {
    final current = api!;
    final channels = await current.list('subscriptions', {
      'part': 'snippet',
      'mine': 'true',
    });
    final lists = await current.list('playlists', {
      'part': 'snippet,contentDetails',
      'mine': 'true',
    });
    final videos = await current.list('videos', {
      'part': 'snippet',
      'myRating': 'like',
    });
    if (!mounted || generation != epoch) return;
    setState(() {
      subscriptions = channels;
      playlists = lists;
      likes = videos;
    });
  }

  Future<void> refresh() async {
    final user = account;
    if (user == null) return;
    final epoch = ++generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final previous = api;
      if (previous != null) {
        await user.authorizationClient.clearAuthorizationToken(
          accessToken: previous.token,
        );
      }
      final authorization =
          await user.authorizationClient.authorizationForScopes(
            YoutubeAccountLogin.scopes,
          ) ??
          await user.authorizationClient.authorizeScopes(
            YoutubeAccountLogin.scopes,
          );
      if (!mounted || epoch != generation) return;
      previous?.close();
      api = YoutubeAccountApi(authorization.accessToken);
      await load(epoch);
    } catch (e) {
      if (mounted && epoch == generation) {
        setState(
          () => error = e is YoutubeAccountError
              ? e.message
              : 'Đồng bộ thất bại. Dữ liệu cũ vẫn được giữ.',
        );
      }
    } finally {
      if (mounted && epoch == generation) setState(() => busy = false);
    }
  }

  Future<void> disconnect() async {
    generation++;
    api?.close();
    api = null;
    setState(() {
      account = null;
      subscriptions = [];
      playlists = [];
      likes = [];
      busy = true;
      error = null;
    });
    try {
      await GoogleSignIn.instance.disconnect();
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Đã xóa dữ liệu trong app. Chưa thu hồi được quyền Google; dùng “Quản lý quyền Google” bên dưới.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> open(Uri uri) async {
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('launch');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Không mở được YouTube.')));
      }
    }
  }

  Widget rows(List<Map<String, dynamic>> items, String type) => items.isEmpty
      ? const Center(child: Text('Không có mục nào.'))
      : ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final snippet = item['snippet'] as Map? ?? {};
            final id = type == 'channel'
                ? (snippet['resourceId'] as Map? ?? {})['channelId']
                : item['id'];
            final valid =
                id is String && RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id);
            return ListTile(
              leading: Icon(
                type == 'channel'
                    ? Icons.subscriptions
                    : type == 'playlist'
                    ? Icons.playlist_play
                    : Icons.thumb_up,
              ),
              title: Text('${snippet['title'] ?? 'Không có tiêu đề'}'),
              subtitle: const Text('Mở bằng YouTube'),
              trailing: const Icon(Icons.open_in_new),
              onTap: valid
                  ? () => open(
                      type == 'channel'
                          ? Uri.https('www.youtube.com', '/channel/$id')
                          : Uri.https(
                              'www.youtube.com',
                              type == 'playlist' ? '/playlist' : '/watch',
                              {type == 'playlist' ? 'list' : 'v': id},
                            ),
                    )
                  : null,
            );
          },
        );

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(title: const Text('Tài khoản YouTube')),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverToBoxAdapter(
            child: Column(
              children: [
                if (busy) const LinearProgressIndicator(),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ListTile(
                  title: Text(account?.email ?? 'Chưa kết nối Google'),
                  subtitle: const Text(
                    'Đồng bộ chỉ đọc · Dữ liệu giữ trong phiên này',
                  ),
                  trailing: TextButton(
                    onPressed: busy ? null : connect,
                    child: Text(
                      account == null ? 'Đăng nhập' : 'Đổi tài khoản',
                    ),
                  ),
                ),
                if (account != null)
                  Wrap(
                    alignment: WrapAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: busy ? null : refresh,
                        icon: const Icon(Icons.sync),
                        label: const Text('Đồng bộ lại'),
                      ),
                      TextButton(
                        onPressed: disconnect,
                        child: const Text('Ngắt kết nối'),
                      ),
                    ],
                  ),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => open(
                        Uri.parse(
                          'https://diutup.duckdns.org/privacy.html',
                        ),
                      ),
                      child: const Text('Quyền riêng tư Diu Túp'),
                    ),
                    TextButton(
                      onPressed: () => open(
                        Uri.parse('https://myaccount.google.com/permissions'),
                      ),
                      child: const Text('Quản lý quyền Google'),
                    ),
                    TextButton(
                      onPressed: () => open(
                        Uri.parse('https://policies.google.com/privacy'),
                      ),
                      child: const Text('Quyền riêng tư Google'),
                    ),
                  ],
                ),
                if (account != null)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      'Để mở playlist riêng tư, hãy chọn cùng tài khoản trong ứng dụng YouTube.',
                    ),
                  ),
              ],
            ),
          ),
        ],
        body: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'Đăng ký'),
                Tab(text: 'Playlist'),
                Tab(text: 'Đã thích'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  rows(subscriptions, 'channel'),
                  rows(playlists, 'playlist'),
                  rows(likes, 'video'),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
