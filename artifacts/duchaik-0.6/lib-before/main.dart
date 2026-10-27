import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'search_box.dart';
import 'player_overlay.dart';
import 'recommendations.dart';
import 'feed_repository.dart';

const ink = Color(0xff0f0f0f);
const panel = Color(0xff272727);
const accent = Color(0xffff0033);
const muted = Color(0xffaaaaaa);
const player = MethodChannel('ytb/player');
const source = MethodChannel('ytb/source');
const speeds = [
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
  4.25,
  4.5,
  4.75,
  5.0,
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

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const YtbApp());
}

class YtbApp extends StatelessWidget {
  const YtbApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Duchaik YTB',
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
  final feedScroll = ScrollController();
  FeedRepository? feed;
  Future<FeedPage>? preparedPage;
  bool isFeed = true, moreLoading = false, hasMore = true;
  String feedMode = 'forYou';
  String? searchContinuation, pageError;
  DateTime lastPoll = DateTime.now();
  String feedDay = '';
  int sessionWatchMs = 0, lastPrefetchIndex = -1;
  Future<void> saveProfile() async =>
      prefs?.setString('recommendationProfile', jsonEncode(profile.toJson()));
  void warmCards(List<Video> cards) {
    if (!mounted) return;
    unawaited(
      source
          .invokeMethod('prefetch', {
            'ids': cards.take(2).map((v) => v['id']).toList(),
          })
          .catchError((_) => null),
    );
    for (final v in cards.take(6)) {
      unawaited(
        precacheImage(
          NetworkImage(
            v['thumbnail'] ?? 'https://i.ytimg.com/vi/${v['id']}/hqdefault.jpg',
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
    final rowHeight = width / columns * 9 / 16 + 110;
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
            .where((v) => !profile.hidden.contains(v['id']))
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
        extra = page.videos
            .where((v) => !profile.hidden.contains(v['id']))
            .toList();
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
      history.clear();
      sessionWatchMs = 0;
    });
    await prefs?.remove('history');
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
  final videoKey = GlobalKey();
  Timer? controlsTimer;
  bool controlsVisible = true, changingFull = false;
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
      }
    });
    init();
    ticker = Timer.periodic(const Duration(milliseconds: 500), (_) => poll());
  }

  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    preferredSpeed = prefs!.getDouble('speed') ?? 1;
    try {
      profile = RecommendationProfile.fromJson(
        Map<String, dynamic>.from(
          jsonDecode(prefs!.getString('recommendationProfile') ?? '{}'),
        ),
      );
    } catch (_) {}
    for (final key in ['history', 'saved']) {
      try {
        final data = (jsonDecode(prefs!.getString(key) ?? '[]') as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        if (key == 'history') {
          history = data;
        } else {
          saved = data;
        }
      } catch (_) {}
    }
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
    feedScroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s != AppLifecycleState.resumed) {
      persistProgress();
      saveProfile();
    } else if (isFeed &&
        !watch &&
        feedDay != DateTime.now().toIso8601String().substring(0, 10)) {
      loadFeed();
    }
  }

  Future<Map<String, dynamic>> api(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final args = path.startsWith('/search')
          ? {'query': Uri.parse(path).queryParameters['q'] ?? ''}
          : body;
      return Map<String, dynamic>.from(
        await source
            .invokeMethod(
              path.startsWith('/search')
                  ? 'search'
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
    submittedQuery = q;
    final id = videoId(q);
    if (id != null) {
      await open({'id': id, 'title': 'Đang lấy thông tin video', 'author': ''});
      return;
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

  Future<void> open(Map<String, dynamic> v, {bool forceFull = false}) async {
    await persistProgress();
    if (!forceFull &&
        active != null &&
        sessionWatchMs >= 1000 &&
        sessionWatchMs < 8000) {
      profile.boost(active!, -.3);
    }
    if (!forceFull) sessionWatchMs = 0;
    final seq = ++loadGeneration;
    if (mounted) {
      setState(() {
        resolving = true;
        error = null;
        watch = true;
        active = Map.from(v);
        state = {};
      });
    }
    await command('pause');
    try {
      final data = await api(
        forceFull ? '/resolveFull' : '/resolve',
        body: {'id': v['id']},
      );
      if (!mounted || seq != loadGeneration) return;
      final previous = history.where((x) => x['id'] == v['id']).firstOrNull;
      final position = (previous?['position'] as num?)?.toInt() ?? 0;
      final duration = (data['duration'] as num?)?.toInt() ?? 0;
      final resume = duration > 0 && position > duration * 1000 - 10000
          ? 0
          : position;
      await player.invokeMethod('load', {
        'id': data['id'],
        'tracks': data['tracks'],
        'title': data['title'],
        'author': data['author'],
        'position': resume,
      });
      await command('speed', {'value': preferredSpeed});
      showControls();
      loadedId = v['id'];
      data.remove('tracks');
      active = data;
      quality = 0;
      history.removeWhere((x) => x['id'] == v['id']);
      history.insert(0, {...data, 'position': resume});
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
        sessionWatchMs += profile.observe(
          active!,
          state,
          d,
          now.difference(lastPoll).inMilliseconds,
        );
      }
      lastPoll = now;
      if (mounted && d != null && jsonEncode(d) != jsonEncode(state)) {
        setState(() {
          state = d;
          if (active == null && d['id'] != null && d['id'] != '') {
            active =
                history.where((v) => v['id'] == d['id']).firstOrNull ??
                {'id': d['id'], 'title': d['title'], 'author': d['author']};
            loadedId = d['id'] as String;
          }
        });
        if (d['error'] != null &&
            active?['engine'] == 'direct-player' &&
            !resolving &&
            fallbackIds.add(active!['id'])) {
          unawaited(open(active!, forceFull: true));
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
    history[index]['position'] = state['position'];
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
        profile.boost(v, 2);
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
    );
  }

  void speedSheet() => sheet(
    'Tốc độ phát',
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: speeds
          .map(
            (s) => ChoiceChip(
              label: Text('${s.toString().replaceAll(RegExp(r'\.0$'), '')}×'),
              selected: (state['speed'] ?? preferredSpeed) == s,
              onSelected: (_) async {
                await command('speed', {'value': s});
                preferredSpeed = s;
                await prefs?.setDouble('speed', s);
                if (mounted) Navigator.pop(context);
              },
            ),
          )
          .toList(),
    ),
  );
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
          if (active?['extendedQualities'] != true)
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
                    label: Text(h == 0 ? 'Tự động · khởi đầu 720p' : '${h}p'),
                    selected: quality == h,
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
    if (changingFull) return;
    changingFull = true;
    setState(() => full = !full);
    showControls();
    try {
      await player.invokeMethod('fullscreen', {'enabled': full});
      await SystemChrome.setEnabledSystemUIMode(
        full ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
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

  void playbackOptions() => sheet(
    'Tùy chọn phát',
    Column(
      mainAxisSize: MainAxisSize.min,
      children: [
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

  Widget videoSurface() => ColoredBox(
    key: videoKey,
    color: Colors.black,
    child: LayoutBuilder(
      builder: (context, size) => AndroidView(
        // Recreate the platform surface at its final size after rotation/PiP.
        // Reusing a resized TextureView can leave its content at portrait size.
        key: ValueKey('${size.maxWidth.round()}x${size.maxHeight.round()}'),
        viewType: 'ytb/video',
        layoutDirection: TextDirection.ltr,
      ),
    ),
  );

  Widget videoFrame() => PlayerOverlay(
    video: videoSurface(),
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
                avatar: const Icon(Icons.speed, size: 18),
                label: Text('${state['speed'] ?? preferredSpeed}×'),
                onPressed: speedSheet,
              ),
              ActionChip(
                avatar: const Icon(Icons.high_quality_outlined, size: 18),
                label: Text(
                  quality == 0
                      ? 'Auto${state['height'] != null ? ' · ${state['height']}p' : ''}'
                      : '${quality}p',
                ),
                onPressed: qualitySheet,
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
          child: Text(v['author'] ?? '', style: const TextStyle(color: muted)),
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
                    ClipboardData(text: 'https://youtu.be/${v['id']}'),
                  );
                  toast('Đã sao chép liên kết');
                },
                icon: const Icon(Icons.link),
                label: const Text('Liên kết'),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Tiếp tục khám phá',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
        ),
        ...videos
            .where((x) => x['id'] != v['id'])
            .take(6)
            .map((x) => videoRow(x)),
        const SizedBox(height: 24),
      ],
    );
    return LayoutBuilder(
      builder: (c, b) {
        if (b.maxWidth > 800) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 6,
                child: AspectRatio(aspectRatio: 16 / 9, child: videoFrame()),
              ),
              Expanded(flex: 4, child: SingleChildScrollView(child: detail)),
            ],
          );
        }
        return Column(
          children: [
            AspectRatio(aspectRatio: 16 / 9, child: videoFrame()),
            Expanded(child: SingleChildScrollView(child: detail)),
          ],
        );
      },
    );
  }

  Widget thumb(Map<String, dynamic> v) => Stack(
    fit: StackFit.expand,
    children: [
      Image.network(
        v['thumbnail'] ?? 'https://i.ytimg.com/vi/${v['id']}/hqdefault.jpg',
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
                    Text(
                      v['author'] ?? '',
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
                      (b.crossAxisExtent - (n - 1) * 16) / n * 9 / 16 + 104,
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
    final list = later ? saved : history;
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
        if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Chưa có video. Khám phá một video để bắt đầu.'),
          ),
        ...list.map(videoRow),
      ],
    );
  }

  Widget settings() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Text(
        'Cài đặt',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 24),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Đề xuất theo thói quen xem'),
        subtitle: const Text(
          'Xử lý trên máy: thời gian xem thực tế, video bỏ qua và xem sau. Có thể tắt bất cứ lúc nào.',
        ),
        value: profile.enabled,
        onChanged: (value) async {
          setState(() => profile.enabled = value);
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
        'Sở thích không được gửi tới máy chủ riêng. YouTube vẫn nhận các yêu cầu tìm kiếm và phát video. Bộ đệm video tối đa 128 MB; chỉ chuẩn bị trước media trên mạng không tính dung lượng.',
        style: TextStyle(color: muted, fontSize: 12, height: 1.5),
      ),
      const SizedBox(height: 20),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.speed),
        title: const Text('Tốc độ mặc định'),
        subtitle: Text('$preferredSpeed×'),
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
        'Duchaik YTB · 0.5.0 · Đức Hai Ka · 2000',
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
          title: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/duchaik_logo.png',
                  width: 42,
                  height: 42,
                ),
              ),
              const SizedBox(width: 8),
              const Flexible(
                child: Text(
                  'Duchaik YTB',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.5,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Cài đặt',
              onPressed: () => setState(() {
                tab = 3;
                watch = false;
              }),
              icon: const Icon(Icons.tune),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: watch && active != null
            ? watchPage()
            : [
                discover,
                () => library(false),
                () => library(true),
                settings,
              ][tab](),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!watch && active != null)
              Container(
                color: panel,
                child: ListTile(
                  dense: true,
                  onTap: () => setState(() => watch = true),
                  leading: const Icon(Icons.graphic_eq, color: accent),
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
              selectedIndex: tab,
              onDestinationSelected: (i) {
                if (i == 0) {
                  loadFeed(mode: 'forYou');
                } else {
                  setState(() {
                    tab = i;
                    watch = false;
                  });
                }
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Trang chủ',
                ),
                NavigationDestination(
                  icon: Icon(Icons.history),
                  label: 'Lịch sử',
                ),
                NavigationDestination(
                  icon: Icon(Icons.bookmark_outline),
                  selectedIcon: Icon(Icons.bookmark),
                  label: 'Xem sau',
                ),
                NavigationDestination(icon: Icon(Icons.tune), label: 'Cài đặt'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
