import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

class YoutubeAccountError implements Exception {
  const YoutubeAccountError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Read-only account data. Tokens and responses are never persisted or sent to
/// the native source extractor; playback links open the official YouTube app.
class YoutubeAccountApi {
  YoutubeAccountApi(this.token, {http.Client? client})
    : client = client ?? http.Client();
  final String token;
  final http.Client client;
  void close() => client.close();
  Future<List<Map<String, dynamic>>> list(
    String resource,
    Map<String, String> query,
  ) async {
    final items = <Map<String, dynamic>>[];
    final seen = <String>{};
    String? next;
    do {
      final response = await client
          .get(
            Uri.https('www.googleapis.com', '/youtube/v3/$resource', {
              ...query,
              'maxResults': '50',
              'pageToken': ?next,
            }),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 401) {
        throw const YoutubeAccountError(
          'Phiên cấp quyền đã hết hạn. Hãy đăng nhập và cấp quyền lại.',
        );
      }
      if (response.statusCode == 403) {
        throw const YoutubeAccountError(
          'Chưa có quyền đọc YouTube, API chưa bật hoặc đã hết hạn mức. Hãy thử lại sau hoặc cấp quyền lại.',
        );
      }
      if (response.statusCode != 200) {
        throw const YoutubeAccountError(
          'Không tải được dữ liệu YouTube. Hãy thử lại.',
        );
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      for (final item in data['items'] as List? ?? []) {
        items.add(Map<String, dynamic>.from(item as Map));
      }
      next = data['nextPageToken'] as String?;
      if (next != null && !seen.add(next)) {
        throw const YoutubeAccountError(
          'YouTube trả trang lặp. Hãy thử đồng bộ lại.',
        );
      }
    } while (next != null && next.isNotEmpty);
    return items;
  }
}

class YoutubeAccountLogin {
  static const scopes = ['https://www.googleapis.com/auth/youtube.readonly'];
  // Public OAuth client ID, not a secret. Keep normal/CI builds configured too.
  static const clientId = String.fromEnvironment(
    'YTB_GOOGLE_WEB_CLIENT_ID',
    defaultValue: '917896460784-eq30f14r51jh8vo7h6vrobpi6brgj966.apps.googleusercontent.com',
  );
  static Future<void>? _initialization;
  static Future<GoogleSignInAccount> authenticate({
    String serverClientId = clientId,
    bool switchAccount = false,
  }) async {
    if (serverClientId.isEmpty) {
      throw const YoutubeAccountError(
        'Bản cài này chưa được cấu hình đăng nhập Google. Cần hoàn tất cấu hình OAuth trước khi sử dụng.',
      );
    }
    try {
      await (_initialization ??= GoogleSignIn.instance.initialize(
        serverClientId: serverClientId,
      ));
    } catch (_) {
      _initialization = null;
      rethrow;
    }
    if (switchAccount) await GoogleSignIn.instance.signOut();
    return GoogleSignIn.instance.authenticate(scopeHint: scopes);
  }
}
