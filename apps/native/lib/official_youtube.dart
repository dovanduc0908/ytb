/// Official YouTube destinations only. No media extraction or account tokens.
class OfficialYoutube {
  static Uri destination(String input) {
    final text = input.trim();
    if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(text)) {
      return Uri.https('www.youtube.com', '/watch', {'v': text});
    }
    final uri = Uri.tryParse(text);
    if (uri != null &&
        uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        !uri.hasPort &&
        const {
          'youtube.com',
          'www.youtube.com',
          'm.youtube.com',
          'youtu.be',
        }.contains(uri.host)) {
      if (uri.host == 'youtu.be') {
        final id = uri.pathSegments.firstOrNull;
        if (id != null && RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)) {
          return Uri.https('www.youtube.com', '/watch', {'v': id});
        }
      } else {
        return uri.replace(host: 'www.youtube.com');
      }
    }
    return Uri.https('www.youtube.com', '/results', {'search_query': text});
  }
}
