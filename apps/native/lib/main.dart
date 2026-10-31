import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'search_box.dart';
import 'player_overlay.dart';
import 'recommendations.dart';
import 'feed_repository.dart';
import 'related_panel.dart';
import 'queue_sheet.dart';
import 'channel_page.dart';
import 'video_meta.dart';
import 'shorts_page.dart';
import 'tv_sheet.dart';
import 'resume_policy.dart';

const ink = Color(0xff0f0f0f);
const panel = Color(0xff272727);
const accent = Color(0xffff0033);
const muted = Color(0xffaaaaaa);
const player = MethodChannel('ytb/player');
const source = MethodChannel('ytb/source');
const speeds = [
  .25,
  .5,
  .75,
  1.0,
  1.25,
  1.5,
  1.75,
  2.0,
  2.25,
  2.5,
  2.75,
  3.0,
  3.25,
  3.5,
  3.75,
  4.0,
];
String clock(num ms) {
  final s = (ms / 1000).floor().clamp(0, 999999);
  return s >= 3600
      ? '${s ~/ 3600}:${((s % 3600) ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}'
      : '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

String? videoId(String input) {
  final t = input.trim();
  if (RegExp(r'^[\w-]{11}$').hasMatch(t)) return t;
  final u = Uri.tryParse(t);
  if (u == null) return null;
  String? id;
  if (u.host == 'youtu.be') {
    id = u.pathSegments.firstOrNull;
  }
  if (['youtube.com', 'www.youtube.com', 'm.youtube.com'].contains(u.host)) {
    id = u.queryParameters['v'];
    if (id == null &&
        u.pathSegments.length > 1 &&
        ['shorts', 'live', 'embed'].contains(u.pathSegments.first)) {
      id = u.pathSegments[1];
    }
  }
  return id != null && RegExp(r'^[\w-]{11}$').hasMatch(id) ? id : null;
}

bool isFacebookLink(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort)
    return false;
  final host = uri.host.toLowerCase();
  return host == 'fb.watch' ||
      host == 'facebook.com' ||
      host.endsWith('.facebook.com');
}

String canonicalMediaId(String raw) {
  if (!isFacebookLink(raw)) return raw;
  final uri = Uri.parse(raw);
  final match = RegExp(r'(?:reel|videos)/(\d+)').firstMatch(uri.path);
  final id = match?.group(1) ?? uri.queryParameters['v'];
  return id != null && RegExp(r'^\d+$').hasMatch(id)
      ? 'https://www.facebook.com/watch/?v=$id'
      : raw;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSizeBytes = 16 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 100;
  runApp(const YtbApp());
}

class YtbApp extends StatelessWidget {
  const YtbApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Diu Túp',
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: ink,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
        surface: panel,
        primary: Colors.white,
        onPrimary: Colors.black,
        onSurface: Colors.white,
        onSurfaceVariant: muted,
        secondary: Colors.white,
        onSecondaryContainer: Colors.white,
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: accent,
        thumbColor: accent,
      ),
      useMaterial3: true,
      appBarTheme: const AppBarTheme(backgroundColor: ink),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: panel,
        indicatorColor: Color(0xff373737),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: panel,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: panel,
        side: BorderSide.none,
        selectedColor: Colors.white,
        labelStyle: WidgetStateTextStyle.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? Colors.black
                : Colors.white,
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    home: const Home(),
  );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  RecommendationProfile profile = RecommendationProfile();
  RecommendationProfile shortsProfile = RecommendationProfile();
  bool tvConnected = false;
  String tvName = '';
  Future<void> showTv() async {
    await persistProgress();
    if (!mounted) return;
    final current = active == null ? null : Map<String, dynamic>.from(active!);
    final playing = state['playing'] == true;
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SingleChildScrollView(
        child: TvSheet(connected: tvConnected, name: tvName),
      ),
    );
    if (!mounted || result == null) return;
    final localQueue = List<Video>.of(queueItems);
    setState(() {
      tvConnected = result['connected'] == true;
      tvName = result['name'] ?? '';
    });
    if (tvConnected && localQueue.isNotEmpty) {
      await setQueue(localQueue, repeatMode);
    }
    if (current != null) {
      await open(current);
      if (!playing) await command('pause');
    }
    await syncQueue();
  }

  List<Video> queueItems = [];
  List<Map<String, dynamic>> playlists = [];
  int queueRevision = -1, repeatMode = 0;
  Video? beforeShorts;
  bool beforeShortsPlaying = false;
  Future<void> syncQueue() async {
    try {
      final data = Map<String, dynamic>.from(
        await player.invokeMethod('queue'),
      );
      if (!mounted) return;
      setState(() {
        queueItems = (data['items'] as List)
            .map((v) => Map<String, dynamic>.from(v))
            .toList();
        repeatMode = data['repeat'];
        queueRevision = data['revision'];
      });
    } catch (_) {}
  }

  Future<void> setQueue(
    List<Video> items,
    int repeat, {
    int? expectedRevision,
  }) async {
    final data = Map<String, dynamic>.from(
      await player.invokeMethod('queue', {
        'items': items,
        'repeat': repeat,
        'revision': ?expectedRevision,
      }),
    );
    if (mounted) {
      setState(() {
        queueItems = (data['items'] as List)
            .map((v) => Map<String, dynamic>.from(v))
            .toList();
        repeatMode = data['repeat'];
        queueRevision = data['revision'];
      });
    }
  }

  Future<void> queueWork = Future.value();
  Future<void> enqueue(Video v, {bool next = false}) {
    queueWork = queueWork
        .catchError((_) {})
        .then((_) => addQueued(v, next: next));
    return queueWork;
  }

  Future<void> addQueued(Video v, {bool next = false}) async {
    await syncQueue();
    final list = queueItems.where((x) => x['id'] != v['id']).toList();
    next ? list.insert(0, v) : list.add(v);
    await setQueue(list, repeatMode);
    toast(next ? 'Đã chọn phát tiếp' : 'Đã thêm cuối hàng đợi');
  }

  Future<void> changeRepeat() async {
    final mode = (repeatMode + 1) % 3;
    try {
      if (tvConnected) {
        await syncQueue();
        await setQueue(queueItems, mode, expectedRevision: queueRevision);
      } else {
        await player.invokeMethod('repeat', {'mode': mode});
        await syncQueue();
      }
      if (mounted) {
        toast(['Đã tắt lặp', 'Lặp video này', 'Lặp danh sách'][mode]);
      }
    } on PlatformException catch (e) {
      if (mounted) toast(e.message ?? 'Không đổi được chế độ lặp');
    }
  }

  Future<void> showQueue() async {
    await syncQueue();
    if (!mounted) return;
    var revision = queueRevision;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => QueueSheet(
        initial: queueItems,
        repeat: repeatMode,
        onChanged: (items, repeat) async {
          await setQueue(items, repeat, expectedRevision: revision);
          revision = queueRevision;
        },
        onPlay: (v) => open(v, fromStart: true),
        onSave: savePlaylist,
      ),
    );
  }

  Future<void> savePlaylist(List<Video> list) async {
    final controller = TextEditingController(
      text: 'Danh sách ${playlists.length + 1}',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Lưu danh sách'),
        content: TextField(
          controller: controller,
          maxLength: 80,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text.trim()),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    // The dialog's route disposes after its exit animation.
    Future.delayed(const Duration(seconds: 1), controller.dispose);
    if (name == null || name.isEmpty) return;
    playlists.add({'name': name, 'videos': list});
    await prefs?.setString('playlists', jsonEncode(playlists));
    if (mounted) setState(() {});
    toast('Đã lưu danh sách');
  }

  Widget queuedRow(Video v) => Row(
    children: [
      Expanded(child: videoRow(v)),
      PopupMenuButton<String>(
        tooltip: 'Tùy chọn bài hát',
        onSelected: (choice) {
          if (choice == 'now') {
            open(v, fromStart: true);
          } else if (choice == 'next') {
            enqueue(v, next: true);
          } else {
            enqueue(v);
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'now', child: Text('Phát ngay')),
          PopupMenuItem(value: 'next', child: Text('Phát tiếp')),
          PopupMenuItem(value: 'last', child: Text('Thêm cuối')),
        ],
      ),
    ],
  );
  Future<void> selectTab(int i) async {
    if (tab == 1 && i != 1) {
      ++loadGeneration;
      await command('pause');
      await prefs?.setString(
        'shortsProfile',
        jsonEncode(shortsProfile.toJson()),
      );
      final restore = beforeShorts;
      beforeShorts = null;
      if (restore != null) {
        await open(restore);
        if (!beforeShortsPlaying) await command('pause');
      } else {
        active = null;
      }
    }
    if (i == 1 && tab != 1) {
      beforeShorts = active == null ? null : Map.from(active!);
      beforeShortsPlaying = state['playing'] == true;
      await persistProgress();
      await command('pause');
    }
    if (!mounted) return;
    setState(() {
      tab = i;
      watch = false;
    });
    if (i == 0) loadFeed(mode: 'forYou');
  }

  Widget karaokePage() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Karaoke',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            TextButton.icon(
              onPressed: showQueue,
              icon: const Icon(Icons.queue_music),
              label: Text('Hàng đợi (${queueItems.length})'),
            ),
          ],
        ),
      ),
      if (playlists.isNotEmpty)
        SizedBox(
          height: 60,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: playlists
                .map(
                  (p) => Padding(
                    padding: const EdgeInsets.all(6),
                    child: InputChip(
                      label: Text(p['name']),
                      onPressed: () async {
                        final list = (p['videos'] as List)
                            .map((v) => Map<String, dynamic>.from(v))
                            .toList();
                        if (list.isNotEmpty) {
                          await setQueue(list.skip(1).toList(), repeatMode);
                          open(list.first, fromStart: true);
                        }
                      },
                      onDeleted: () {
                        setState(() => playlists.remove(p));
                        prefs?.setString('playlists', jsonEncode(playlists));
                      },
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      Expanded(
        child: RelatedPanel(
          key: const ValueKey('karaoke'),
          seed: const {'id': '', 'title': 'karaoke Việt Nam'},
          header: const SizedBox.shrink(),
          hidden: {...profile.hidden, ...profile.finished},
          initialQuery: 'karaoke Việt Nam',
          itemBuilder: queuedRow,
        ),
      ),
    ],
  );
  Widget libraryPage() => DefaultTabController(
    length: 3,
    child: Column(
      children: [
        const TabBar(
          tabs: [
            Tab(text: 'Lịch sử'),
            Tab(text: 'Xem sau'),
            Tab(text: 'Danh sách'),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [library(false), library(true), personalPlaylists()],
          ),
        ),
      ],
    ),
  );

  Widget personalPlaylists() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text(
        'Danh sách trên thiết bị',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      const Text(
        'Sắp xếp hàng đợi rồi bấm nút lưu để tạo danh sách.',
        style: TextStyle(color: muted),
      ),
      if (playlists.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Chưa có danh sách.'),
        ),
      for (final list in playlists)
        ListTile(
          leading: const Icon(Icons.playlist_play),
          title: Text('${list['name']}'),
          subtitle: Text('${(list['videos'] as List? ?? []).length} video'),
          onTap: () async {
            final videos = (list['videos'] as List)
                .map((v) => Map<String, dynamic>.from(v))
                .toList();
            if (videos.isEmpty) return;
            await setQueue(videos.skip(1).toList(), repeatMode);
            await open(videos.first, fromStart: true);
          },
          trailing: IconButton(
            tooltip: 'Xóa danh sách',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              setState(() => playlists.remove(list));
              await prefs?.setString('playlists', jsonEncode(playlists));
            },
          ),
        ),
    ],
  );

  final feedScroll = ScrollController();
  FeedRepository? feed;
  Future<FeedPage>? preparedPage;
  bool isFeed = true, moreLoading = false, hasMore = true;
  String feedMode = 'forYou';
  String? searchContinuation, pageError;
  DateTime lastPoll = DateTime.now();
  String feedDay = '';
  int sessionWatchMs = 0, lastPrefetchIndex = -1;
  Future<void> saveProfile() async {
    await prefs?.setString(
      'recommendationProfile',
      jsonEncode(profile.toJson()),
    );
    await prefs?.setString('shortsProfile', jsonEncode(shortsProfile.toJson()));
  }

  void warmCards(List<Video> cards) {
    if (!mounted) return;
    unawaited(
      source
          .invokeMethod('prefetch', {
            'ids': cards.take(1).map((v) => v['id']).toList(),
          })
          .catchError((_) => null),
    );
    for (final v in cards.take(3)) {
      unawaited(
        precacheImage(
          ResizeImage(
            NetworkImage(
              v['thumbnail'] ??
                  'https://i.ytimg.com/vi/${v['id']}/hqdefault.jpg',
            ),
            width: 480,
          ),
          context,
        ),
      );
    }
  }

  void onFeedScroll() {
    if (!feedScroll.hasClients || watch || searchFocused || videos.isEmpty) {
      return;
    }
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1100
        ? 4
        : width >= 800
        ? 3
        : width >= 550
        ? 2
        : 1;
    final rowHeight =
        width / columns * 9 / 16 +
        140 * MediaQuery.textScalerOf(context).scale(1);
    final index =
        (((feedScroll.offset - 220).clamp(0, double.infinity) / rowHeight)
                    .floor() *
                columns)
            .clamp(0, videos.length - 1);
    if (index != lastPrefetchIndex) {
      lastPrefetchIndex = index;
      warmCards(videos.skip(index).take(6).toList());
    }
    if (feedScroll.position.extentAfter < 1000 &&
        hasMore &&
        !moreLoading &&
        !loading &&
        pageError == null) {
      unawaited(loadMore());
    }
  }

  Future<void> loadFeed({String? mode}) async {
    final seq = ++searchGeneration;
    final selected = mode ?? feedMode;
    final repo = FeedRepository(profile, selected);
    feed = repo;
    preparedPage = null;
    feedDay = DateTime.now().toIso8601String().substring(0, 10);
    List<Video> cached = [];
    try {
      final data =
          jsonDecode(prefs?.getString('feedCache_$selected') ?? '{}') as Map;
      if (DateTime.now().millisecondsSinceEpoch - (data['time'] as num? ?? 0) <
          36 * 3600000) {
        cached = (data['videos'] as List? ?? [])
            .map((v) => Map<String, dynamic>.from(v))
            .where((v) => !profile.excludes(v['id']))
            .toList();
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      isFeed = true;
      feedMode = selected;
      submittedQuery = '';
      searchController.clear();
      topic = selected == 'vn'
          ? 'Việt Nam'
          : selected == 'world'
          ? 'Thế giới'
          : 'Dành cho bạn';
      watch = false;
      tab = 0;
      videos = cached;
      loading = true;
      moreLoading = false;
      hasMore = true;
      error = null;
      pageError = null;
      lastPrefetchIndex = -1;
    });
    if (feedScroll.hasClients) feedScroll.jumpTo(0);
    final page = await repo.next();
    if (!mounted || seq != searchGeneration || !isFeed) return;
    setState(() {
      if (page.videos.isNotEmpty) videos = page.videos;
      loading = false;
      hasMore = page.hasMore;
      if (page.error != null) {
        pageError = 'Chưa cập nhật được đề xuất. Bạn có thể thử lại.';
      }
    });
    if (page.videos.isNotEmpty) {
      await prefs?.setString(
        'feedCache_$selected',
        jsonEncode({
          'time': DateTime.now().millisecondsSinceEpoch,
          'videos': page.videos,
        }),
      );
      if (!mounted || seq != searchGeneration) return;
      warmCards(page.videos);
      if (hasMore) preparedPage = repo.next();
    }
  }

  Future<void> loadMore() async {
    if (moreLoading || loading || !hasMore) return;
    final seq = searchGeneration;
    setState(() {
      moreLoading = true;
      pageError = null;
    });
    try {
      List<Video> extra;
      if (isFeed) {
        final current = feed!;
        final page = await (preparedPage ?? current.next());
        if (!mounted || seq != searchGeneration) return;
        preparedPage = null;
        if (page.error != null) throw page.error!;
        extra = page.videos.where((v) => !profile.excludes(v['id'])).toList();
        hasMore = page.hasMore;
        if (hasMore) preparedPage = current.next();
      } else {
        if (searchContinuation == null) {
          hasMore = false;
          return;
        }
        final old = searchContinuation;
        final data = Map<String, dynamic>.from(
          await source.invokeMethod('search', {
            'query': submittedQuery,
            'upload': searchDate,
            'durationFilter': searchDuration,
            'continuation': old,
          }),
        );
        if (!mounted || seq != searchGeneration) return;
        searchContinuation = data['continuation'] as String?;
        hasMore = searchContinuation != null && searchContinuation != old;
        extra = (data['videos'] as List)
            .map((v) => Map<String, dynamic>.from(v))
            .toList();
      }
      final ids = videos.map((v) => v['id']).toSet();
      extra = extra.where((v) => ids.add(v['id'])).toList();
      setState(() {
        videos.addAll(extra);
        if (extra.isEmpty && hasMore) pageError = 'Chưa có video mới trong trang này. Bấm tải tiếp để thử nguồn khác.';
      });
    } catch (_) {
      if (mounted && seq == searchGeneration) {
        setState(() => pageError = 'Mạng đang chậm. Bấm tải tiếp để thử lại.');
      }
    } finally {
      if (mounted && seq == searchGeneration) {
        setState(() => moreLoading = false);
      }
    }
  }

  void backToBrowse() {
    setState(() => watch = false);
    if (isFeed && profile.enabled && sessionWatchMs >= 15000) {
      unawaited(loadFeed());
    }
  }

  void dismissVideo(Video video) {
    profile.dismiss(video);
    unawaited(command('musicAuto', {'hideId': video['id']}));
    setState(() => videos.removeWhere((v) => v['id'] == video['id']));
    unawaited(saveProfile());
  }

  Future<void> clearViewingData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Xóa dữ liệu trên máy?'),
        content: const Text(
          'Lịch sử xem, sở thích và video bị ẩn sẽ bị xóa. Danh sách xem sau được giữ lại.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Xóa dữ liệu'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final enabled = profile.enabled;
    setState(() {
      profile = RecommendationProfile()..enabled = enabled;
      shortsProfile = RecommendationProfile()..enabled = enabled;
      history.clear();
      sessionWatchMs = 0;
    });
    await prefs?.remove('history');
    await command('clearProgress');
    await command('musicAuto', {'clear': true});
    await saveProfile();
    await invalidateFeedCache();
    if (mounted) toast('Đã xóa dữ liệu xem và đề xuất trên máy.');
  }

  Future<void> invalidateFeedCache() async {
    searchGeneration++;
    preparedPage = null;
    feed = null;
    moreLoading = false;
    for (final mode in ['forYou', 'vn', 'world']) {
      await prefs?.remove('feedCache_$mode');
    }
  }

  final searchController = TextEditingController();
  final historyController = TextEditingController(),
      savedController = TextEditingController();
  final videoKey = GlobalKey();
  Timer? controlsTimer;
  bool controlsVisible = true, changingFull = false, screenLocked = false;
  bool loadingQualities = false;
  final fallbackIds = <String>{};
  SharedPreferences? prefs;
  List<Map<String, dynamic>> videos = [], history = [], saved = [];
  Map<String, dynamic>? active;
  String? loadedId;
  Map<String, dynamic> state = {};
  bool loading = true,
      resolving = false,
      watch = false,
      polling = false,
      full = false,
      inPip = false;
  String? error;
  int tab = 0, searchGeneration = 0, loadGeneration = 0, quality = 0;
  double preferredSpeed = 1;
  String topic = 'Khám phá';
  String submittedQuery = '';
  int searchDate = 0, searchDuration = 0;
  bool searchFocused = false;
  Timer? ticker;
  int ticks = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    feedScroll.addListener(onFeedScroll);
    player.setMethodCallHandler((call) async {
      if (call.method == 'pipChanged' && mounted) {
        setState(() => inPip = call.arguments == true);
        if (!inPip) unawaited(poll());
      }
    });
    init();
    ticker = Timer.periodic(const Duration(milliseconds: 500), (_) => poll());
  }

  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    try {
      playlists = (jsonDecode(prefs?.getString('playlists') ?? '[]') as List)
          .map((v) => Map<String, dynamic>.from(v))
          .toList();
      for (final list in playlists) {
        list['items'] = (list['items'] as List? ?? [])
            .map(
              (v) => {
                ...Map<String, dynamic>.from(v),
                'id': canonicalMediaId('${v['id']}'),
              },
            )
            .toList();
      }
    } catch (_) {}
    try {
      shortsProfile = RecommendationProfile.fromJson(
        jsonDecode(prefs?.getString('shortsProfile') ?? '{}'),
      );
    } catch (_) {}
    syncQueue();
    preferredSpeed = 1;
    await prefs!.remove('speed');
    await command('speed', {'value': 1.0});
    try {
      profile = RecommendationProfile.fromJson(
        Map<String, dynamic>.from(
          jsonDecode(prefs!.getString('recommendationProfile') ?? '{}'),
        ),
      );
    } catch (_) {}
    shortsProfile.enabled = profile.enabled;
    if (!profile.enabled) await command('musicAuto', {'enabled': false});
    for (final key in ['history', 'saved']) {
      try {
        final data = (jsonDecode(prefs!.getString(key) ?? '[]') as List)
            .map(
              (e) => {
                ...Map<String, dynamic>.from(e),
                'id': canonicalMediaId('${e['id']}'),
              },
            )
            .toList();
        if (key == 'history') {
          for (final video in data) {
            if (profile.markFinished(
              video,
              (video['position'] as num?) ?? 0,
              ((video['duration'] as num?) ?? 0) * 1000,
            )) {
              unawaited(
                player.invokeMethod('markCompletedVideo', {'id': video['id']}),
              );
            }
            video['position'] = resumePosition(
              duration:
                  (video['duration'] is num
                      ? (video['duration'] as num).toInt()
                      : 0) *
                  1000,
              position: (video['position'] as num?)?.toInt() ?? 0,
              isLive: video['isLive'] == true,
              isShort: video['isShort'] == true,
            );
          }
          history = data;
          if (profile.seeds.isEmpty) {
            for (final video in history.reversed) {
              if (video['isShort'] != true) profile.rememberSeed(video);
            }
          }
        } else {
          saved = data;
        }
        final seen = <String>{};
        data.removeWhere((v) => !seen.add('${v['id']}'));
        await prefs!.setString(key, jsonEncode(data));
      } catch (_) {}
    }
    try {
      final discarded = await player.invokeMethod<String>('discardedVideo');
      if (discarded != null) {
        for (final video in history.where((v) => v['id'] == discarded)) {
          video['position'] = 0;
        }
        await prefs?.setString('history', jsonEncode(history));
        await player.invokeMethod('clearDiscardedVideo', {'id': discarded});
      }
    } on PlatformException catch (_) {}
    await syncFinishedVideos();
    if (mounted) setState(() {});
    if (mounted && submittedQuery.isEmpty) await loadFeed();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ticker?.cancel();
    controlsTimer?.cancel();
    player.setMethodCallHandler(null);
    searchController.dispose();
    historyController.dispose();
    savedController.dispose();
    feedScroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s != AppLifecycleState.resumed) {
      persistProgress();
      saveProfile();
    } else {
      unawaited(syncFinishedVideos());
      if (isFeed &&
          !watch &&
          feedDay != DateTime.now().toIso8601String().substring(0, 10)) {
        loadFeed();
      }
    }
  }

  Future<void> syncFinishedVideos() async {
    try {
      final ids =
          await player.invokeListMethod<String>('completedVideos') ?? [];
      profile.finished.addAll(ids);
      shortsProfile.finished.addAll(profile.finished);
      if (mounted && isFeed) {
        setState(() => videos.removeWhere((v) => profile.excludes(v['id'])));
      }
      await saveProfile();
    } on PlatformException catch (_) {}
  }

  Future<Map<String, dynamic>> api(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final args = path.startsWith('/search')
          ? {
              'query': Uri.parse(path).queryParameters['q'] ?? '',
              'upload': searchDate,
              'durationFilter': searchDuration,
            }
          : body;
      return Map<String, dynamic>.from(
        await source
            .invokeMethod(
              path.startsWith('/search')
                  ? 'search'
                  : path == '/resolveFacebook'
                  ? 'resolveFacebook'
                  : path == '/resolveFull'
                  ? 'resolveFull'
                  : 'resolve',
              args,
            )
            .timeout(const Duration(seconds: 90)),
      );
    } on TimeoutException {
      throw Exception('YouTube phản hồi chậm. Hãy thử lại.');
    } on PlatformException catch (e) {
      throw Exception(
        e.message ?? 'Không kết nối được YouTube. Kiểm tra Internet.',
      );
    }
  }

  Future<void> search(String q) async {
    q = q.trim();
    if (q.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final newQuery = submittedQuery != q;
    submittedQuery = q;
    final id = videoId(q);
    if (id != null) {
      await open({'id': id, 'title': 'Đang lấy thông tin video', 'author': ''});
      return;
    }
    if (isFacebookLink(q)) {
      await open({'id': q, 'title': 'Đang lấy thông tin video', 'author': ''});
      return;
    }
    if (newQuery && profile.enabled) {
      profile.boost({'title': q}, .35);
      unawaited(saveProfile());
    }
    final seq = ++searchGeneration;
    if (mounted) {
      setState(() {
        isFeed = false;
        preparedPage = null;
        searchContinuation = null;
        hasMore = false;
        pageError = null;
        moreLoading = false;
        loading = true;
        error = null;
        tab = 0;
        watch = false;
      });
    }
    try {
      final d = await api('/search?q=${Uri.encodeQueryComponent(q)}');
      if (mounted && seq == searchGeneration) {
        setState(() {
          videos = (d['videos'] as List)
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          loading = false;
          searchContinuation = d['continuation'] as String?;
          hasMore = searchContinuation != null;
        });
        unawaited(
          source
              .invokeMethod('prefetch', {
                'ids': videos.take(2).map((v) => v['id']).toList(),
              })
              .catchError((_) => null),
        );
      }
    } catch (e) {
      if (mounted && seq == searchGeneration) {
        setState(() {
          error = clean(e);
          loading = false;
        });
      }
    }
  }

  String clean(Object e) => e.toString().replaceFirst('Exception: ', '');
  Future<void> command(String method, [Map<String, dynamic>? args]) async {
    if (method == 'play' &&
        active != null &&
        (state['id'] == null || state['id'] != active!['id'])) {
      await open(active!);
      return;
    }
    try {
      await player.invokeMethod(method, args);
    } on PlatformException catch (e) {
      toast(e.message ?? 'Player chưa sẵn sàng');
    }
  }

  Future<void> open(
    Map<String, dynamic> v, {
    bool forceFull = false,
    bool fromStart = false,
    bool asShort = false,
  }) async {
    v = {...v, 'id': canonicalMediaId('${v['id']}')};
    final seq = ++loadGeneration;
    unawaited(source.invokeMethod<void>('cancelPrefetch').catchError((_) {}));
    await persistProgress();
    if (!mounted || seq != loadGeneration) return;
    if (!forceFull &&
        active != null &&
        sessionWatchMs >= 1000 &&
        sessionWatchMs < 8000) {
      (active?['isShort'] == true ? shortsProfile : profile).boost(
        active!,
        -.3,
      );
    }
    if (!forceFull) sessionWatchMs = 0;
    if (mounted) {
      setState(() {
        resolving = true;
        error = null;
        watch = !asShort;
        active = Map.from(v);
        state = {};
      });
    }
    try {
      // Resolve the new source while stopping playback and reading saved progress.
      final results = await Future.wait<dynamic>([
        tvConnected
            ? Future.value(Map<String, dynamic>.from(v))
            : api(
                isFacebookLink('${v['id']}')
                    ? '/resolveFacebook'
                    : forceFull
                    ? '/resolveFull'
                    : '/resolve',
                body: isFacebookLink('${v['id']}')
                    ? {'url': v['id']}
                    : {'id': v['id']},
              ),
        command('pause'),
        if (!tvConnected)
          player
              .invokeMethod<int>('savedProgress', {'id': v['id']})
              .catchError((_) => null),
      ]);
      final data = results[0] as Map<String, dynamic>;
      if (!mounted || seq != loadGeneration) return;
      final previous = history.where((x) => x['id'] == v['id']).firstOrNull;
      final legacyPosition = (previous?['position'] as num?)?.toInt() ?? 0;
      final nativePosition = results.length > 2 ? results[2] as int? : null;
      final duration = (data['duration'] as num?)?.toInt() ?? 0;
      final resume = resumePosition(
        duration: duration * 1000,
        position: nativePosition ?? legacyPosition,
        isLive: data['isLive'] == true,
        isShort: asShort,
      );
      if (!mounted || seq != loadGeneration) return;
      await player.invokeMethod('load', {
        'id': data['id'],
        'tracks': data['tracks'],
        'title': data['title'],
        'author': data['author'],
        'position': fromStart ? 0 : resume,
        'isShort': asShort,
        'metadata': data,
      });
      if (!mounted || seq != loadGeneration) return;
      await command('speed', {'value': preferredSpeed});
      if (!mounted || seq != loadGeneration) return;
      showControls();
      loadedId = data['id'];
      data.remove('tracks');
      active = {...data, 'isShort': asShort};
      quality = 0;
      history.removeWhere((x) => canonicalMediaId('${x['id']}') == data['id']);
      history.insert(0, {...data, 'position': fromStart ? 0 : resume});
      if (history.length > 150) history.removeLast();
      await prefs?.setString('history', jsonEncode(history));
      if (mounted) {
        setState(() {
          resolving = false;
        });
      }
    } catch (e) {
      if (mounted && seq == loadGeneration) {
        setState(() {
          resolving = false;
          error = clean(e);
        });
      }
    }
  }

  Future<void> poll() async {
    if (polling) return;
    polling = true;
    try {
      final d = await player.invokeMapMethod<String, dynamic>('state');
      final now = DateTime.now();
      if (mounted &&
          isFeed &&
          !watch &&
          tab == 0 &&
          !loading &&
          !searchFocused &&
          feedDay.isNotEmpty &&
          feedDay != now.toIso8601String().substring(0, 10)) {
        profile.decay(now);
        unawaited(loadFeed());
      }
      if (active != null && d != null && !resolving) {
        if (d['id'] == active!['id'] &&
            profile.markFinished(
              active!,
              (d['position'] as num?) ?? 0,
              (d['duration'] as num?) ?? 0,
              ended: d['ended'] == true,
            )) {
          shortsProfile.finished.add('${active!['id']}');
          unawaited(
            player.invokeMethod('markCompletedVideo', {'id': active!['id']}),
          );
          unawaited(saveProfile());
        }
        sessionWatchMs += (tab == 1 ? shortsProfile : profile).observe(
          active!,
          state,
          d,
          now.difference(lastPoll).inMilliseconds,
        );
      }
      lastPoll = now;
      if (d != null && d['queueRevision'] != queueRevision) await syncQueue();
      if (mounted && d != null && jsonEncode(d) != jsonEncode(state)) {
        if (d['captionStatus'] == 'error' &&
            state['captionStatus'] != 'error') {
          toast('Không tải được phụ đề. Hãy thử ngôn ngữ khác.');
        }
        setState(() {
          state = d;
          if (!changingFull && d['orientationLocked'] is bool)
            screenLocked = d['orientationLocked'] == true;
          if (!resolving &&
              d['id'] != null &&
              d['id'] != '' &&
              active?['id'] != d['id']) {
            active =
                (d['metadata'] is Map
                    ? Map<String, dynamic>.from(d['metadata'])
                    : null) ??
                history.where((v) => v['id'] == d['id']).firstOrNull ??
                {'id': d['id'], 'title': d['title'], 'author': d['author']};
            loadedId = d['id'] as String;
            if (!history.any((v) => v['id'] == d['id'])) {
              history.insert(0, Map.from(active!));
              if (history.length > 150) history.removeLast();
            }
            sessionWatchMs = 0;
          }
        });
        if (d['error'] != null &&
            active?['engine'] == 'direct-player' &&
            !resolving &&
            fallbackIds.add(active!['id'])) {
          unawaited(open(active!, forceFull: true, asShort: tab == 1));
        }
        if (++ticks % 32 == 0) {
          await persistProgress();
          await saveProfile();
        }
      }
    } catch (_) {
    } finally {
      polling = false;
    }
  }

  Future<void> persistProgress() async {
    if (active == null ||
        active!['id'] != loadedId ||
        resolving ||
        state['duration'] == null ||
        state['duration'] == 0) {
      return;
    }
    final index = history.indexWhere((v) => v['id'] == active!['id']);
    if (index < 0) return;
    history[index]['position'] = resumePosition(
      duration: (state['duration'] as num?)?.toInt() ?? 0,
      position: (state['position'] as num?)?.toInt() ?? 0,
      isLive: active!['isLive'] == true,
      isShort: active!['isShort'] == true,
    );
    await prefs?.setString('history', jsonEncode(history));
  }

  void toast(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void toggleSave(Map<String, dynamic> v) async {
    setState(() {
      if (saved.any((x) => x['id'] == v['id'])) {
        saved.removeWhere((x) => x['id'] == v['id']);
      } else {
        saved.insert(0, Map.from(v)..remove('tracks'));
        (v['isShort'] == true ? shortsProfile : profile).boost(v, 2);
      }
    });
    await prefs?.setString('saved', jsonEncode(saved));
    await saveProfile();
  }

  Future<void> sheet(String title, Widget content) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: panel,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(c).height * .85,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 20),
                  content,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void speedSheet() {
    double selected = (state['speed'] as num? ?? preferredSpeed)
        .toDouble()
        .clamp(.25, 4.0);
    sheet(
      'Tốc độ phát',
      StatefulBuilder(
        builder: (context, update) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${selected.toStringAsFixed(2)}×',
              style: const TextStyle(fontSize: 24),
            ),
            Slider(
              value: selected,
              min: .25,
              max: 4,
              divisions: 75,
              label: '${selected.toStringAsFixed(2)}×',
              onChanged: (value) => update(() => selected = value),
              onChangeEnd: (value) async {
                preferredSpeed = value;
                await command('speed', {'value': value});
              },
            ),
            Wrap(
              spacing: 8,
              children: [0.5, 1.0, 1.5, 2.0, 3.0, 4.0]
                  .map(
                    (value) => ActionChip(
                      label: Text('$value×'),
                      onPressed: () async {
                        update(() => selected = value);
                        preferredSpeed = value;
                        await command('speed', {'value': value});
                      },
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  void qualitySheet() {
    final items = (state['qualities'] as List? ?? [])
        .cast<num>()
        .map((x) => x.toInt())
        .toList()
        .reversed;
    sheet(
      'Chất lượng video',
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Chỉ hiển thị các mức nguồn và máy hỗ trợ.',
            style: TextStyle(color: muted),
          ),
          if (active?['extendedQualities'] != true &&
              !isFacebookLink('${active?['id']}'))
            TextButton.icon(
              icon: const Icon(Icons.hd_outlined),
              label: Text(
                loadingQualities
                    ? 'Đang tải thêm chất lượng…'
                    : 'Tải thêm chất lượng 2K / 4K',
              ),
              onPressed: loadingQualities
                  ? null
                  : () async {
                      Navigator.pop(context);
                      setState(() => loadingQualities = true);
                      final id = active?['id'];
                      try {
                        final data = await api(
                          '/resolveFull',
                          body: {'id': id},
                        );
                        if (mounted && active?['id'] == id) {
                          await player.invokeMethod('sources', {
                            'id': id,
                            'tracks': data['tracks'],
                          });
                          active?['extendedQualities'] = true;
                          state = {
                            ...state,
                            'qualities': (data['tracks'] as List)
                                .map((track) => track['height'])
                                .toList(),
                          };
                          if (mounted) qualitySheet();
                        }
                      } catch (e) {
                        toast(clean(e));
                      } finally {
                        if (mounted) setState(() => loadingQualities = false);
                      }
                    },
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [0, ...items]
                .map(
                  (h) => ChoiceChip(
                    label: Text(
                      h == 0
                          ? 'Tự động · ${state['height'] ?? '…'}p'
                          : h == 1
                          ? 'Nguồn tốt nhất'
                          : '${h}p',
                    ),
                    selected:
                        (state['qualityMode'] as num?)?.toInt() == h ||
                        (state['qualityMode'] == null && quality == h),
                    onSelected: (_) async {
                      try {
                        await player.invokeMethod('quality', {'height': h});
                        if (mounted) setState(() => quality = h);
                        if (mounted) Navigator.pop(context);
                      } on PlatformException catch (e) {
                        toast(e.message ?? 'Không hỗ trợ');
                      }
                    },
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  void captionsSheet() {
    if (state['captionStatus'] == 'loading') {
      toast('Đang tìm phụ đề…');
      return;
    }
    final tracks = (state['captionTracks'] as List? ?? []).cast<Map>();
    final status = state['captionStatus'];
    sheet(
      'Phụ đề',
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('Tắt'),
            trailing: (state['captionSelected'] ?? -1) == -1
                ? const Icon(Icons.check)
                : null,
            onTap: () async {
              await command('caption', {'id': -1});
              if (mounted) Navigator.pop(context);
            },
          ),
          if (tracks.isEmpty)
            ListTile(
              title: Text(
                status == 'loading'
                    ? 'Đang tìm phụ đề…'
                    : 'Video chưa có phụ đề khả dụng',
              ),
            ),
          ...tracks.map(
            (track) => ListTile(
              title: Text('${track['label']}'),
              subtitle: track['automatic'] == true
                  ? const Text('Tạo tự động')
                  : null,
              trailing: state['captionSelected'] == track['id']
                  ? const Icon(Icons.check)
                  : null,
              onTap: () async {
                await command('caption', {'id': track['id']});
                if (mounted) {
                  Navigator.pop(context);
                  toast('Đang tải phụ đề…');
                }
              },
            ),
          ),
          if (status == 'error')
            const ListTile(
              title: Text('Không tải được phụ đề. Hãy thử ngôn ngữ khác.'),
            ),
        ],
      ),
    );
  }

  void chaptersSheet() {
    if (state['chaptersLoading'] == true) {
      toast('Đang tải chương…');
      return;
    }
    final chapters = (state['chapters'] as List? ?? []).cast<Map>();
    sheet(
      'Chương video',
      SizedBox(
        height: MediaQuery.sizeOf(context).height * .55,
        child: chapters.isEmpty
            ? Center(
                child: Text(
                  state['chaptersLoading'] == true
                      ? 'Đang tải chương…'
                      : 'Video chưa cung cấp chương.',
                ),
              )
            : ListView.builder(
                itemCount: chapters.length,
                itemBuilder: (_, i) {
                  final chapter = chapters[i];
                  final start = (chapter['startMs'] as num).toInt();
                  return ListTile(
                    leading: Text(clock(start)),
                    title: Text('${chapter['title']}'),
                    onTap: () {
                      Navigator.pop(context);
                      command('seek', {'position': start});
                    },
                  );
                },
              ),
      ),
    );
  }

  void sleepSheet() => sheet(
    'Hẹn giờ ngủ',
    Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Dừng sau thời gian thực, kể cả khi phát nhanh.\nÁp dụng cả khi khóa màn hình.',
          style: TextStyle(color: muted, height: 1.5),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [1, 15, 30, 45, 60, 90]
              .map(
                (m) => ActionChip(
                  label: Text('$m phút'),
                  onPressed: () async {
                    await command('timer', {'milliseconds': m * 60000});
                    if (mounted) Navigator.pop(context);
                  },
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 8),
        ActionChip(
          label: const Text('Hết video này'),
          onPressed: () async {
            await command('timer', {'milliseconds': -1});
            if (mounted) Navigator.pop(context);
          },
        ),
        Row(
          children: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                customTimer();
              },
              child: const Text('Số phút khác'),
            ),
            const Spacer(),
            TextButton(
              onPressed: () async {
                await command('timer', {'milliseconds': 0});
                if (mounted) Navigator.pop(context);
              },
              child: const Text('Hủy hẹn giờ'),
            ),
          ],
        ),
      ],
    ),
  );
  Future<void> customTimer() async {
    final c = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Hẹn giờ ngủ'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Số phút (1–720)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, c.text),
            child: const Text('Đặt giờ'),
          ),
        ],
      ),
    );
    final n = int.tryParse(value ?? '');
    if (value != null) {
      if (n != null && n >= 1 && n <= 720) {
        await command('timer', {'milliseconds': n * 60000});
      } else {
        toast('Nhập số phút từ 1 đến 720.');
      }
    }
  }

  Future<void> toggleFull() async {
    if (changingFull || screenLocked) return;
    changingFull = true;
    final next = !full;
    showControls();
    try {
      await player.invokeMethod('fullscreen', {'enabled': next});
      if (!mounted) return;
      setState(() {
        full = next;
        screenLocked = false;
      });
      await SystemChrome.setEnabledSystemUIMode(
        full ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
    } on PlatformException catch (e) {
      toast(e.message ?? 'Chưa đổi được toàn màn hình');
    } finally {
      changingFull = false;
    }
  }

  void showControls() {
    controlsTimer?.cancel();
    if (mounted) setState(() => controlsVisible = true);
    controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => controlsVisible = false);
    });
  }

  void enhancementSheet() => sheet(
    'Tăng cường hình ảnh',
    Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Phóng hình Lanczos và tăng nét nhẹ. Tự giảm xử lý khi máy nóng hoặc phát không mượt. Không tạo lại chi tiết đã mất.',
        ),
        for (final entry in {
          'off': 'Tắt',
          'auto': 'Tự động',
          'strong': 'Mạnh',
        }.entries)
          ListTile(
            title: Text(entry.value),
            trailing: state['enhancement'] == entry.key
                ? const Icon(Icons.check)
                : null,
            onTap: () async {
              await command('enhancement', {'mode': entry.key});
              if (mounted) Navigator.pop(context);
              await poll();
            },
          ),
      ],
    ),
  );

  void playbackOptions() => sheet(
    'Tùy chọn phát',
    Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (full && !tvConnected)
          ListTile(
            leading: const Icon(Icons.screen_rotation),
            title: const Text('Hướng toàn màn hình'),
            subtitle: Text(
              {
                    'auto': 'Theo video',
                    'landscape': 'Ngang',
                    'portrait': 'Dọc',
                  }[state['orientationMode']] ??
                  'Ngang',
            ),
            onTap: () {
              Navigator.pop(context);
              sheet(
                'Hướng toàn màn hình',
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final entry in {
                      'auto': 'Theo video',
                      'landscape': 'Ngang',
                      'portrait': 'Dọc',
                    }.entries)
                      ListTile(
                        title: Text(entry.value),
                        onTap: () async {
                          await command('orientation', {'mode': entry.key});
                          if (mounted) Navigator.pop(context);
                          await poll();
                        },
                      ),
                  ],
                ),
              );
            },
          ),
        if (!tvConnected)
          ListTile(
            leading: const Icon(Icons.auto_fix_high),
            title: const Text('Tăng cường hình ảnh'),
            subtitle: Text(
              '${state['enhancementStatus'] ?? 'off'} · Giữ nguyên độ phân giải nguồn',
            ),
            onTap: () {
              Navigator.pop(context);
              enhancementSheet();
            },
          ),
        ListTile(
          leading: const Icon(Icons.graphic_eq),
          title: const Text('Âm thanh tốt nhất từ nguồn'),
          subtitle: Text(
            '${state['audio'] ?? 'Đang tải'} · ${((state['audioBitrate'] as num? ?? 0) / 1000).round()} kbps',
          ),
        ),
        ListTile(
          leading: const Icon(Icons.headphones),
          title: const Text('Chỉ nghe âm thanh'),
          subtitle: const Text('Tiết kiệm dữ liệu khi nguồn có âm thanh riêng'),
          trailing: Switch(
            value: state['audioOnly'] == true,
            onChanged: (value) async {
              Navigator.pop(context);
              await command('audioOnly', {'enabled': value});
              await poll();
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.speed),
          title: const Text('Tốc độ phát'),
          trailing: Text('${state['speed'] ?? preferredSpeed}×'),
          onTap: () {
            Navigator.pop(context);
            speedSheet();
          },
        ),
        ListTile(
          leading: const Icon(Icons.high_quality_outlined),
          title: const Text('Chất lượng'),
          trailing: Text('${state['height'] ?? 'Auto'}p'),
          onTap: () {
            Navigator.pop(context);
            qualitySheet();
          },
        ),
        ListTile(
          leading: Icon(
            repeatMode == 1 ? Icons.repeat_one : Icons.repeat,
            color: repeatMode == 0 ? null : accent,
          ),
          title: const Text('Lặp'),
          trailing: Text(['Tắt', 'Video này', 'Danh sách'][repeatMode]),
          onTap: () {
            Navigator.pop(context);
            changeRepeat();
          },
        ),
        ListTile(
          leading: const Icon(Icons.closed_caption_outlined),
          title: const Text('Phụ đề'),
          trailing: Text(
            (state['captionSelected'] ?? -1) == -1 ? 'Tắt' : 'Đang bật',
          ),
          onTap: () {
            Navigator.pop(context);
            captionsSheet();
          },
        ),
        ListTile(
          leading: const Icon(Icons.link),
          title: const Text('Sao chép liên kết tại thời điểm này'),
          onTap: () {
            final id = active?['id'];
            if (id != null) {
              final seconds =
                  ((state['position'] as num?)?.toInt() ?? 0) ~/ 1000;
              Clipboard.setData(
                ClipboardData(
                  text: isFacebookLink('$id')
                      ? '$id'
                      : 'https://youtu.be/$id?t=$seconds',
                ),
              );
              Navigator.pop(context);
              toast('Đã sao chép liên kết kèm thời điểm');
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.list_alt_outlined),
          title: const Text('Chương video'),
          trailing: Text('${(state['chapters'] as List? ?? []).length}'),
          onTap: () {
            Navigator.pop(context);
            chaptersSheet();
          },
        ),
        ListTile(
          leading: const Icon(Icons.bedtime_outlined),
          title: const Text('Hẹn giờ ngủ'),
          onTap: () {
            Navigator.pop(context);
            sleepSheet();
          },
        ),
        ListTile(
          leading: const Icon(Icons.picture_in_picture_alt),
          title: const Text('Cửa sổ nổi'),
          onTap: () {
            Navigator.pop(context);
            command('pip');
          },
        ),
      ],
    ),
  );

  Widget videoSurface() => tvConnected
      ? ColoredBox(
          color: Colors.black,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cast_connected, size: 52),
                const SizedBox(height: 12),
                Text('Đang phát trên $tvName'),
              ],
            ),
          ),
        )
      : ColoredBox(
          key: videoKey,
          color: Colors.black,
          child: LayoutBuilder(
            builder: (context, size) => AndroidView(
              // Recreate the platform surface at its final size after rotation/PiP.
              // Reusing a resized TextureView can leave its content at portrait size.
              key: ValueKey(
                '${size.maxWidth.round()}x${size.maxHeight.round()}',
              ),
              viewType: 'ytb/video',
              layoutDirection: TextDirection.ltr,
            ),
          ),
        );

  double get videoAspect =>
      ((state['aspectRatio'] as num?)?.toDouble() ?? 16 / 9).clamp(.3, 3.0);
  Widget videoFrame() => PlayerOverlay(
    locked: screenLocked,
    onRotate: () async {
      final mode = state['orientationMode'] == 'portrait'
          ? 'landscape'
          : 'portrait';
      await command('orientation', {'mode': mode});
      await poll();
      showControls();
    },
    video: videoSurface(),
    onMinimize: backToBrowse,
    onPrevious: () {
      command('previous');
      showControls();
    },
    onNext: () {
      command('next');
      showControls();
    },
    onLock: (value) {
      setState(() => screenLocked = value);
      player.invokeMethod('lock', {'enabled': value});
    },
    onSpeed: (value) {
      if (preferredSpeed == value) return;
      preferredSpeed = value;
      command('speed', {'value': value});
    },
    onAdjust: (kind, delta) async =>
        (await player.invokeMethod<num>('adjust', {
          'kind': kind,
          'delta': delta,
        }))?.toDouble() ??
        0,
    visible: controlsVisible,
    fullscreen: full,
    state: state,
    loading: resolving,
    formatTime: clock,
    onToggle: () {
      if (controlsVisible) {
        controlsTimer?.cancel();
        setState(() => controlsVisible = false);
      } else {
        showControls();
      }
    },
    onPlay: () {
      command(state['playing'] == true ? 'pause' : 'play');
      showControls();
    },
    onSeek: (value) {
      command('seek', {'position': value});
      showControls();
    },
    onFullscreen: toggleFull,
    onSettings: playbackOptions,
  );

  Future<void> offlineLibrary() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          return FutureBuilder<List<dynamic>>(
            future: player
                .invokeListMethod<dynamic>('offlineList')
                .then((value) => value ?? []),
            builder: (context, snapshot) {
              final items = snapshot.data ?? [];
              return SafeArea(
                child: SizedBox(
                  height: MediaQuery.sizeOf(context).height * .7,
                  child: Column(
                    children: [
                      ListTile(
                        title: const Text('Video đã tải'),
                        subtitle: FutureBuilder<Map<String, dynamic>?>(
                          future: player.invokeMapMethod<String, dynamic>(
                            'offlineStatus',
                          ),
                          builder: (context, snapshot) {
                            final data = snapshot.data;
                            if (data == null ||
                                (data['message'] as String? ?? '').isEmpty) {
                              return const Text(
                                'Giới hạn 200 MiB · chỉ mạng không tính dung lượng',
                              );
                            }
                            return Text(
                              '${data['message']} · ${((data['bytes'] as num? ?? 0) / 1048576).toStringAsFixed(1)} MiB · nhấn làm mới',
                            );
                          },
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: () => update(() {}),
                        ),
                      ),
                      Expanded(
                        child: items.isEmpty
                            ? const Center(
                                child: Text('Chưa có bản tải hoàn tất'),
                              )
                            : ListView.builder(
                                itemCount: items.length,
                                itemBuilder: (context, index) {
                                  final item = Map<String, dynamic>.from(
                                    items[index] as Map,
                                  );
                                  return ListTile(
                                    title: Text('${item['title']}'),
                                    subtitle: Text(
                                      '${item['audioOnly'] == true ? 'Âm thanh' : 'Video'} · ${((item['size'] as num? ?? 0) / 1048576).toStringAsFixed(1)} MiB',
                                    ),
                                    onTap: () async {
                                      Navigator.pop(context);
                                      try {
                                        final data = Map<String, dynamic>.from(
                                          (await player
                                              .invokeMapMethod<String, dynamic>(
                                                'offlineData',
                                                {'id': item['id']},
                                              ))!,
                                        );
                                        await persistProgress();
                                        await player.invokeMethod('load', {
                                          'id': data['id'],
                                          'title': data['title'],
                                          'author': data['author'],
                                          'tracks': data['tracks'],
                                          'position': 0,
                                          'metadata': data,
                                        });
                                        if (!mounted) return;
                                        setState(() {
                                          active = data;
                                          watch = true;
                                          state = {};
                                          resolving = false;
                                          error = null;
                                        });
                                        showControls();
                                        await poll();
                                      } on PlatformException catch (e) {
                                        toast(
                                          e.message ?? 'Không mở được bản tải',
                                        );
                                      }
                                    },
                                    trailing: IconButton(
                                      tooltip: 'Xóa bản tải',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () async {
                                        try {
                                          await player.invokeMethod(
                                            'offlineDelete',
                                            {'id': item['id']},
                                          );
                                          update(() {});
                                        } on PlatformException catch (e) {
                                          toast(e.message ?? 'Không xóa được');
                                        }
                                      },
                                    ),
                                  );
                                },
                              ),
                      ),
                      TextButton(
                        onPressed: () async {
                          await player.invokeMethod('offlineCancel');
                          if (context.mounted) update(() {});
                        },
                        child: const Text('Hủy lượt tải đang chạy'),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> startOfflineDownload(bool audioOnly) async {
    try {
      await player.invokeMethod('offlineStart', {'audioOnly': audioOnly});
      if (mounted) toast('Đang tải qua Wi-Fi. Mở Video đã tải để kiểm tra.');
    } on PlatformException catch (e) {
      if (mounted) toast(e.message ?? 'Không tải được');
    }
  }

  void offlineOptions() => sheet(
    'Tải offline',
    Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const ListTile(
          title: Text('Tải qua mạng không tính dung lượng'),
          subtitle: Text(
            'Tối đa 200 MiB cho toàn bộ bản tải. Giữ ứng dụng mở trong khi tải.',
          ),
        ),
        ListTile(
          leading: const Icon(Icons.headphones),
          title: const Text('Chỉ tải âm thanh'),
          onTap: () {
            Navigator.pop(context);
            startOfflineDownload(true);
          },
        ),
        ListTile(
          leading: const Icon(Icons.download),
          title: const Text('Tải video (ưu tiên tối đa 480p)'),
          onTap: () {
            Navigator.pop(context);
            startOfflineDownload(false);
          },
        ),
        ListTile(
          leading: const Icon(Icons.folder_open),
          title: const Text('Video đã tải'),
          onTap: () {
            Navigator.pop(context);
            offlineLibrary();
          },
        ),
      ],
    ),
  );

  Widget playerControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            spacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.download, size: 18),
                label: const Text('Tải offline'),
                onPressed: offlineOptions,
              ),
              ActionChip(
                avatar: Icon(
                  state['audioOnly'] == true
                      ? Icons.videocam
                      : Icons.headphones,
                  size: 18,
                ),
                label: Text(
                  state['audioOnly'] == true ? 'Xem video' : 'Chỉ nghe',
                ),
                onPressed: () async {
                  await command('audioOnly', {
                    'enabled': state['audioOnly'] != true,
                  });
                  await poll();
                },
              ),
              ActionChip(
                avatar: const Icon(Icons.speed, size: 18),
                label: Text('${state['speed'] ?? preferredSpeed}×'),
                onPressed: speedSheet,
              ),
              ActionChip(
                avatar: const Icon(Icons.high_quality_outlined, size: 18),
                label: Text(
                  (state['qualityMode'] as num?)?.toInt() == 0 ||
                          (state['qualityMode'] == null && quality == 0)
                      ? 'Auto${state['height'] != null ? ' · ${state['height']}p' : ''}'
                      : '${quality}p',
                ),
                onPressed: qualitySheet,
              ),
              ActionChip(
                avatar: const Icon(Icons.list_alt, size: 18),
                label: const Text('Chương'),
                onPressed: chaptersSheet,
              ),
              ActionChip(
                avatar: const Icon(Icons.bedtime_outlined, size: 18),
                label: const Text('Hẹn ngủ'),
                onPressed: sleepSheet,
              ),
              ActionChip(
                avatar: const Icon(Icons.picture_in_picture_alt, size: 18),
                label: const Text('Cửa sổ nổi'),
                onPressed: () => command('pip'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget errorCard(String message) => Container(
    margin: const EdgeInsets.all(16),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xff35232c),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, color: Color(0xffffc1cb)),
        const SizedBox(height: 10),
        Text(message, style: const TextStyle(height: 1.5)),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: () => watch && active != null
              ? open(active!)
              : isFeed
              ? loadFeed()
              : search(submittedQuery),
          icon: const Icon(Icons.refresh),
          label: const Text('Thử lại'),
        ),
      ],
    ),
  );
  Widget watchPage() {
    final v = active!;
    final err = error ?? state['error'] as String?;
    final detail = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        playerControls(),
        if (state['audioOnly'] == true)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                const Text(
                  'Chế độ nghe',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      iconSize: 36,
                      tooltip: 'Lùi 10 giây',
                      onPressed: () => command('seek', {
                        'position':
                            ((state['position'] as num? ?? 0).toInt() - 10000)
                                .clamp(0, 1 << 53),
                      }),
                      icon: const Icon(Icons.replay_10),
                    ),
                    IconButton(
                      iconSize: 52,
                      tooltip: state['playing'] == true ? 'Tạm dừng' : 'Phát',
                      onPressed: () =>
                          command(state['playing'] == true ? 'pause' : 'play'),
                      icon: Icon(
                        state['playing'] == true
                            ? Icons.pause_circle
                            : Icons.play_circle,
                      ),
                    ),
                    IconButton(
                      iconSize: 36,
                      tooltip: 'Tiến 10 giây',
                      onPressed: () => command('seek', {
                        'position':
                            ((state['position'] as num? ?? 0).toInt() + 10000)
                                .clamp(
                                  0,
                                  (state['duration'] as num? ?? 0).toInt(),
                                ),
                      }),
                      icon: const Icon(Icons.forward_10),
                    ),
                    IconButton(
                      iconSize: 32,
                      tooltip: 'Hàng đợi',
                      onPressed: showQueue,
                      icon: const Icon(Icons.queue_music),
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (state['timerExpired'] == true)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Đã dừng phát theo hẹn giờ ngủ.',
              style: TextStyle(color: accent),
            ),
          ),
        if (err != null) errorCard(err),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Text(
            v['title'] ?? '',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(viewsLabel(v), style: const TextStyle(color: muted)),
              TextButton.icon(
                onPressed: isFacebookLink('${v['id']}')
                    ? null
                    : () => openChannel(v),
                icon: const Icon(Icons.account_circle_outlined),
                label: Text(v['author'] ?? 'Mở kênh người đăng'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: () => toggleSave(v),
                icon: Icon(
                  saved.any((x) => x['id'] == v['id'])
                      ? Icons.bookmark
                      : Icons.bookmark_border,
                ),
                label: const Text('Xem sau'),
              ),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(
                      text: isFacebookLink('${v['id']}')
                          ? '${v['id']}'
                          : 'https://youtu.be/${v['id']}',
                    ),
                  );
                  toast('Đã sao chép liên kết');
                },
                icon: const Icon(Icons.link),
                label: const Text('Liên kết'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Bài trước',
                onPressed: () => command('previous'),
                icon: const Icon(Icons.skip_previous),
              ),
              TextButton.icon(
                onPressed: showQueue,
                icon: const Icon(Icons.queue_music),
                label: Text('Hàng đợi (${queueItems.length})'),
              ),
              IconButton(
                tooltip: ['Lặp: tắt', 'Lặp video', 'Lặp danh sách'][repeatMode],
                onPressed: changeRepeat,
                color: repeatMode == 0 ? null : accent,
                icon: Icon(repeatMode == 1 ? Icons.repeat_one : Icons.repeat),
              ),
              IconButton(
                tooltip: 'Bài tiếp theo',
                onPressed: queueItems.isEmpty ? null : () => command('next'),
                icon: const Icon(Icons.skip_next),
              ),
            ],
          ),
        ),
        if (state['queueError'] != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('${state['queueError']}'),
          ),
        SwitchListTile(
          title: const Text('Tự phát video tiếp theo'),
          subtitle: Text(
            state['musicError'] as String? ??
                'Tự thêm video liên quan khi hàng đợi sắp hết',
          ),
          value: state['musicAuto'] == true,
          onChanged: profile.enabled
              ? (value) async {
                  await command('musicAuto', {'enabled': value});
                  await poll();
                }
              : null,
        ),
        const SizedBox(height: 24),
      ],
    );
    return LayoutBuilder(
      builder: (c, b) {
        if (b.maxWidth > 800 ||
            (b.maxWidth >= 600 && b.maxWidth > b.maxHeight * 1.2)) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 6,
                child: AspectRatio(
                  aspectRatio: videoAspect,
                  child: videoFrame(),
                ),
              ),
              Expanded(
                flex: 4,
                child: isFacebookLink('${v['id']}')
                    ? SingleChildScrollView(child: detail)
                    : RelatedPanel(
                        seed: v,
                        header: detail,
                        hidden: {...profile.hidden, ...profile.finished},
                        itemBuilder: queuedRow,
                      ),
              ),
            ],
          );
        }
        return Column(
          children: [
            AspectRatio(aspectRatio: videoAspect, child: videoFrame()),
            Expanded(
              child: isFacebookLink('${v['id']}')
                  ? SingleChildScrollView(child: detail)
                  : RelatedPanel(
                      seed: v,
                      header: detail,
                      hidden: {...profile.hidden, ...profile.finished},
                      itemBuilder: queuedRow,
                    ),
            ),
          ],
        );
      },
    );
  }

  void openChannel(Video video) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ChannelPage(video: video, onPlay: (v) => open(v)),
    ),
  );

  Widget thumb(Map<String, dynamic> v) => Stack(
    fit: StackFit.expand,
    children: [
      Image.network(
        v['thumbnail'] ?? 'https://i.ytimg.com/vi/${v['id']}/hqdefault.jpg',
        cacheWidth: 480,
        fit: BoxFit.cover,
        errorBuilder: (_, e, s) => const ColoredBox(
          color: panel,
          child: Icon(Icons.play_circle_outline, size: 40, color: muted),
        ),
      ),
      if (v['duration'] is String || v['duration'] is num)
        Positioned(
          right: 8,
          bottom: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            color: Colors.black87,
            child: Text(
              v['duration'] is num
                  ? clock((v['duration'] as num) * 1000)
                  : v['duration'],
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ),
    ],
  );
  Widget videoCard(Map<String, dynamic> v) => InkWell(
    borderRadius: BorderRadius.circular(18),
    onTap: () => open(v),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: AspectRatio(aspectRatio: 16 / 9, child: thumb(v)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      v['title'] ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 5),
                    InkWell(
                      onTap: isFacebookLink('${v['id']}')
                          ? null
                          : () => openChannel(v),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          v['author'] ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ),
                    ),
                    Text(
                      viewsLabel(v),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                    if (v['reason'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${v['stale'] == true ? 'Đã lưu · ' : ''}${v['reason']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: muted, fontSize: 10),
                        ),
                      ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Tùy chọn video',
                icon: const Icon(Icons.more_vert, size: 20, color: muted),
                onSelected: (action) {
                  if (action == 'hide') {
                    dismissVideo(v);
                  } else {
                    toggleSave(v);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'save',
                    child: Text(
                      saved.any((x) => x['id'] == v['id'])
                          ? 'Bỏ khỏi xem sau'
                          : 'Lưu xem sau',
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'hide',
                    child: Text('Không quan tâm'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget videoRow(Map<String, dynamic> v) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => open(v),
      child: Row(
        children: [
          SizedBox(
            width: 125,
            height: 76,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: thumb(v),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  v['title'] ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  (v['position'] ?? 0) > 0
                      ? 'Xem tiếp từ ${clock(v['position'])}'
                      : v['author'] ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
                Text(
                  viewsLabel(v),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
                InkWell(
                  onTap: isFacebookLink('${v['id']}')
                      ? null
                      : () => openChannel(v),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text('Xem kênh', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Lưu xem sau',
            onPressed: () => toggleSave(v),
            icon: Icon(
              saved.any((x) => x['id'] == v['id'])
                  ? Icons.bookmark
                  : Icons.bookmark_border,
              size: 20,
            ),
          ),
        ],
      ),
    ),
  );
  Widget discover() => RefreshIndicator(
    onRefresh: () => isFeed ? loadFeed() : search(submittedQuery),
    child: CustomScrollView(
      controller: feedScroll,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                VideoSearchBox(
                  controller: searchController,
                  onSearch: (q) {
                    topic = 'Tìm kiếm';
                    search(q);
                  },
                  onPreview: (query) => source
                      .invokeMethod('previewSearch', {'query': query})
                      .catchError((_) => null),
                  onFocusChanged: (value) =>
                      setState(() => searchFocused = value),
                ),
                if (!isFeed)
                  Wrap(
                    spacing: 16,
                    children: [
                      DropdownButton<int>(
                        value: searchDate,
                        items: const [
                          DropdownMenuItem(
                            value: 0,
                            child: Text('Mọi thời gian'),
                          ),
                          DropdownMenuItem(
                            value: 1,
                            child: Text('Một giờ qua'),
                          ),
                          DropdownMenuItem(value: 2, child: Text('Hôm nay')),
                          DropdownMenuItem(value: 3, child: Text('Tuần này')),
                          DropdownMenuItem(value: 4, child: Text('Tháng này')),
                          DropdownMenuItem(value: 5, child: Text('Năm nay')),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => searchDate = v);
                            search(submittedQuery);
                          }
                        },
                      ),
                      DropdownButton<int>(
                        value: searchDuration,
                        items: const [
                          DropdownMenuItem(
                            value: 0,
                            child: Text('Mọi thời lượng'),
                          ),
                          DropdownMenuItem(
                            value: 1,
                            child: Text('Dưới 4 phút'),
                          ),
                          DropdownMenuItem(value: 3, child: Text('4–20 phút')),
                          DropdownMenuItem(
                            value: 2,
                            child: Text('Trên 20 phút'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => searchDuration = v);
                            search(submittedQuery);
                          }
                        },
                      ),
                    ],
                  ),
                const SizedBox(height: 14),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    spacing: 8,
                    children:
                        {
                              'Dành cho bạn': '@forYou',
                              'Việt Nam': '@vn',
                              'Thế giới': '@world',
                              'Âm nhạc': 'nhạc lofi Việt Nam',
                              'Công nghệ': 'công nghệ',
                              'Thiên nhiên': 'nature documentary 4k',
                            }.entries
                            .map(
                              (e) => ChoiceChip(
                                showCheckmark: false,
                                label: Text(
                                  e.key,
                                  style: TextStyle(
                                    color: topic == e.key
                                        ? Colors.black
                                        : Colors.white,
                                  ),
                                ),
                                selected: topic == e.key,
                                onSelected: (_) {
                                  setState(() => topic = e.key);
                                  if (e.value.startsWith('@')) {
                                    loadFeed(mode: e.value.substring(1));
                                  } else {
                                    search(e.value);
                                  }
                                },
                              ),
                            )
                            .toList(),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        isFeed ? topic : 'Kết quả tìm kiếm',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (loading)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (error != null) SliverToBoxAdapter(child: errorCard(error!)),
        if (!loading && videos.isEmpty && error == null)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Không có kết quả. Thử từ khóa khác.'),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 0),
          sliver: SliverLayoutBuilder(
            builder: (c, b) {
              final n = b.crossAxisExtent >= 1100
                  ? 4
                  : b.crossAxisExtent >= 800
                  ? 3
                  : b.crossAxisExtent >= 550
                  ? 2
                  : 1;
              return SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (c, i) => videoCard(videos[i]),
                  childCount: videos.length,
                ),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: n,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 12,
                  mainAxisExtent:
                      (b.crossAxisExtent - (n - 1) * 16) / n * 9 / 16 +
                      140 * MediaQuery.textScalerOf(context).scale(1),
                ),
              );
            },
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                if (pageError != null)
                  Text(
                    pageError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: muted),
                  ),
                if (moreLoading)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  )
                else if (!loading)
                  TextButton.icon(
                    onPressed: hasMore
                        ? loadMore
                        : () => isFeed ? loadFeed() : search(submittedQuery),
                    icon: Icon(hasMore ? Icons.expand_more : Icons.refresh),
                    label: Text(
                      hasMore
                          ? 'Tải tiếp video'
                          : 'Đã hết nguồn hiện tại · Làm mới',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
  Widget library(bool later) {
    final libraryQuery = (later ? savedController : historyController).text;
    final list = (later ? saved : history).where((v) {
      final q = libraryQuery.trim().toLowerCase();
      return q.isEmpty ||
          '${v['title'] ?? ''} ${v['author'] ?? ''}'.toLowerCase().contains(q);
    }).toList();
    final watching = later
        ? <Video>[]
        : list.where((v) => (v['position'] as num? ?? 0) > 0).toList();
    final remaining = later
        ? list
        : list.where((v) => (v['position'] as num? ?? 0) <= 0).toList();
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                later ? 'Để dành cho sau' : 'Lịch sử của bạn',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Lưu riêng trên thiết bị này.',
                style: TextStyle(color: muted),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Tìm trong thư viện',
            ),
            controller: later ? savedController : historyController,
            onChanged: (_) => setState(() {}),
          ),
        ),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              libraryQuery.isEmpty
                  ? 'Chưa có video. Khám phá một video để bắt đầu.'
                  : 'Không tìm thấy video.',
            ),
          ),
        if (watching.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'Đang xem dở',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          ...watching.map(videoRow),
          if (remaining.isNotEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Text(
                'Đã xem',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
        ],
        ...remaining.map(videoRow),
      ],
    );
  }

  Future<void> cacheSettings() async {
    final selected = prefs?.getInt('mediaCacheMb') ?? 64;
    final value = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Dung lượng bộ đệm video'),
              subtitle: Text(
                'Lưu trên bộ nhớ máy, áp dụng khi mở lại ứng dụng.',
              ),
            ),
            for (final size in [64, 128, 256, 512])
              ListTile(
                title: Text('$size MiB'),
                trailing: size == selected ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, size),
              ),
          ],
        ),
      ),
    );
    if (value == null) return;
    await player.invokeMethod('cacheSize', {'mb': value});
    await prefs?.setInt('mediaCacheMb', value);
    if (mounted) {
      setState(() {});
      toast('Dung lượng mới áp dụng khi mở lại ứng dụng');
    }
  }

  Future<void> clearMediaCache() async {
    try {
      await player.invokeMethod('clearMediaCache');
      if (mounted) toast('Đã xóa bộ đệm video');
    } on PlatformException catch (e) {
      if (mounted) toast(e.message ?? 'Không xóa được bộ đệm');
    }
  }

  bool checkingUpdate = false;
  Map<String, dynamic>? updateCandidate;

  Future<void> updateApp() async {
    const updater = MethodChannel('ytb/update');
    if (checkingUpdate) return;
    if (updateCandidate != null) {
      try {
        final outcome = await updater.invokeMethod<String>('install');
        if (outcome == 'permission' && mounted) {
          toast('Cho phép cài ứng dụng, quay lại và bấm Cài cập nhật.');
        }
      } on PlatformException catch (e) {
        if (mounted) toast(e.message ?? 'Không mở được trình cài đặt');
      }
      return;
    }
    setState(() => checkingUpdate = true);
    try {
      final info = await updater.invokeMapMethod<String, dynamic>('check');
      if (!mounted) return;
      setState(
        () => updateCandidate = info?['available'] == true ? info : null,
      );
      if (updateCandidate == null) {
        toast('Bạn đang dùng bản mới nhất (${info?['current'] ?? ''}).');
      } else {
        final outcome = await updater.invokeMethod<String>('install');
        if (outcome == 'permission' && mounted) {
          toast('Cho phép cài ứng dụng, quay lại và bấm Cài cập nhật.');
        }
      }
    } on PlatformException catch (e) {
      if (mounted) toast(e.message ?? 'Không kiểm tra được cập nhật');
    } finally {
      if (mounted) setState(() => checkingUpdate = false);
    }
  }

  Widget settings() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Text(
        'Cài đặt',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 24),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: checkingUpdate
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.system_update),
        title: Text(
          updateCandidate == null
              ? 'Kiểm tra cập nhật'
              : 'Cài cập nhật ${updateCandidate!['version']}',
        ),
        subtitle: Text(
          checkingUpdate
              ? 'Đang tải và xác minh bản phát hành...'
              : updateCandidate == null
              ? 'Tải bản phát hành GitHub mới nhất'
              : 'Android sẽ hỏi xác nhận cài đặt',
        ),
        onTap: checkingUpdate ? null : updateApp,
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Đề xuất theo thói quen xem'),
        subtitle: const Text(
          'Xử lý trên máy: thời gian xem thực tế, video bỏ qua và xem sau. Có thể tắt bất cứ lúc nào.',
        ),
        value: profile.enabled,
        onChanged: (value) async {
          setState(() {
            profile.enabled = value;
            shortsProfile.enabled = value;
          });
          await command('musicAuto', {'enabled': value});
          await saveProfile();
          await invalidateFeedCache();
        },
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.delete_outline),
        title: const Text('Xóa dữ liệu xem và đề xuất'),
        onTap: clearViewingData,
      ),
      const Text(
        'Sở thích không được gửi tới máy chủ riêng. Chất lượng tự động tiết kiệm dữ liệu: ưu tiên 480p trên dữ liệu SIM và mức cao nhất tương thích trên Wi-Fi. Bạn có thể chọn chất lượng khác trong trình phát. Media chỉ được tải trước trên mạng không tính dung lượng.',
        style: TextStyle(color: muted, fontSize: 12, height: 1.5),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.storage),
        title: const Text('Dung lượng bộ đệm video'),
        subtitle: Text(
          '${prefs?.getInt('mediaCacheMb') ?? 64} MiB trên máy · áp dụng khi mở lại',
        ),
        onTap: cacheSettings,
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.cleaning_services_outlined),
        title: const Text('Xóa bộ đệm video'),
        subtitle: const Text('Giữ lịch sử, vị trí xem và danh sách lưu'),
        onTap: clearMediaCache,
      ),
      ListTile(
        leading: const Icon(Icons.download_done),
        title: const Text('Video đã tải'),
        onTap: offlineLibrary,
      ),
      const SizedBox(height: 20),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.speed),
        title: const Text('Tốc độ phiên hiện tại'),
        subtitle: Text('$preferredSpeed× · Mở lại ứng dụng sẽ về 1×'),
        trailing: const Icon(Icons.chevron_right),
        onTap: speedSheet,
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.bedtime_outlined),
        title: const Text('Hẹn giờ ngủ'),
        subtitle: Text(
          (state['timerMs'] ?? 0) > 0
              ? 'Còn ${clock(state['timerMs'])}'
              : 'Chưa đặt',
        ),
        onTap: sleepSheet,
      ),
      const ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.phone_android),
        title: Text('Phát trực tiếp trên thiết bị'),
        subtitle: Text('Chỉ cần kết nối Internet.'),
      ),
      const Divider(height: 32),
      const Text(
        'Diu Túp · 0.8.5 · Đức Hai Ka · 2000',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 12),
      const Text(
        'Phát video trực tiếp trên điện thoại. Không có quảng cáo do ứng dụng thêm. Bảng xếp hạng âm nhạc Việt Nam và thế giới được ghi ngày nguồn cung cấp, kết hợp khám phá nhiều chủ đề và sở thích trên máy. Kéo xuống để làm mới; cuộn để tải tiếp, không có hạn mức đề xuất theo ngày. Nguồn YouTube vẫn có thể thay đổi hoặc hết kết quả.',
        style: TextStyle(color: muted, height: 1.6),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    if (inPip && active != null) {
      return Scaffold(body: videoSurface());
    }
    if (full && active != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (did, result) {
          if (!did) toggleFull();
        },
        child: Scaffold(backgroundColor: Colors.black, body: videoFrame()),
      );
    }
    return PopScope(
      canPop: !watch,
      onPopInvokedWithResult: (did, result) {
        if (!did) backToBrowse();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: watch
              ? IconButton(
                  tooltip: 'Về khám phá',
                  onPressed: backToBrowse,
                  icon: const Icon(Icons.arrow_back),
                )
              : null,
          title: Semantics(
            label: 'Diu Túp',
            image: true,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                'assets/duchaik_logo.png',
                width: 48,
                height: 48,
                excludeFromSemantics: true,
              ),
            ),
          ),
          actions: [
            IconButton(
              tooltip: tvConnected ? 'Điều khiển TV' : 'Kết nối TV',
              onPressed: showTv,
              icon: Icon(tvConnected ? Icons.cast_connected : Icons.cast),
            ),
            IconButton(
              tooltip: 'Cài đặt',
              onPressed: () => selectTab(4),
              icon: const Icon(Icons.tune),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: watch && active != null
            ? watchPage()
            : [
                discover,
                () => ShortsPage(
                  open: (v) => open(v, fromStart: true, asShort: true),
                  surface: videoSurface,
                  activeId: active?['id'],
                  activeVideo: active,
                  onChannel: openChannel,
                  ready: !resolving && state['ready'] == true,
                  playing: state['playing'] == true,
                  toggle: () =>
                      command(state['playing'] == true ? 'pause' : 'play'),
                  save: toggleSave,
                  settings: playbackOptions,
                  profile: shortsProfile,
                  playbackError: error ?? state['error'] as String?,
                  position: (state['position'] as num? ?? 0).toInt(),
                  duration: (state['duration'] as num? ?? 0).toInt(),
                  onSeek: (ms) => command('seek', {'position': ms}),
                ),
                karaokePage,
                libraryPage,
                settings,
              ][tab](),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!watch && active != null && tab != 1)
              Material(
                color: panel,
                child: ListTile(
                  dense: true,
                  onTap: () => setState(() => watch = true),
                  leading: SizedBox(
                    width: 96,
                    height: 54,
                    child: IgnorePointer(child: videoSurface()),
                  ),
                  title: Text(
                    active!['title'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    state['timerExpired'] == true
                        ? 'Đã hết giờ ngủ'
                        : state['playing'] == true
                        ? 'Đang phát'
                        : 'Đã tạm dừng',
                    style: const TextStyle(color: muted),
                  ),
                  trailing: IconButton(
                    tooltip: 'Phát hoặc tạm dừng',
                    onPressed: () =>
                        command(state['playing'] == true ? 'pause' : 'play'),
                    icon: Icon(
                      state['playing'] == true ? Icons.pause : Icons.play_arrow,
                    ),
                  ),
                ),
              ),
            NavigationBar(
              height: 64,
              selectedIndex: tab.clamp(0, 3),
              onDestinationSelected: selectTab,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Trang chủ',
                ),
                NavigationDestination(
                  icon: Icon(Icons.play_circle_outline),
                  label: 'Shorts',
                ),
                NavigationDestination(
                  icon: Icon(Icons.mic_none),
                  label: 'Karaoke',
                ),
                NavigationDestination(
                  icon: Icon(Icons.video_library_outlined),
                  label: 'Thư viện',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
