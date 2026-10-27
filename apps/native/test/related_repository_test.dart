import 'package:flutter_test/flutter_test.dart';
import 'package:ytb/related_repository.dart';

void main() {
  test(
    'related pages deduplicate, exclude current video and use server cursors',
    () async {
      final calls = <Map>[];
      final repo = RelatedRepository(
        {'id': 'current', 'title': 'My song'},
        request: (method, args) async {
          calls.add({'method': method, ...args});
          final page = args['continuation'] == null
              ? 0
              : int.parse(args['continuation']);
          return {
            'videos': List.generate(
              30,
              (i) => {
                'id': i == 0 ? 'current' : '${page * 29 + i}',
                'title': 'song $i',
              },
            ),
            'continuation': '${page + 1}',
          };
        },
      );
      final first = await repo.next(), second = await repo.next();
      expect(first.videos.length, 24);
      expect(second.videos.length, 24);
      expect(
        {
          ...first.videos.map((v) => v['id']),
          ...second.videos.map((v) => v['id']),
        }.length,
        48,
      );
      expect(first.videos.any((v) => v['id'] == 'current'), false);
      expect(calls[1]['continuation'], '1');
    },
  );
  test(
    'related source failure falls back to contextual search and ends honestly',
    () async {
      final calls = <String>[];
      final repo = RelatedRepository(
        {'id': 'current', 'title': 'Tình ca'},
        request: (method, args) async {
          calls.add(method);
          if (method == 'related') throw Exception('offline');
          return {
            'videos': [
              {'id': 'other', 'title': 'tình ca'},
            ],
          };
        },
      );
      final page = await repo.next();
      expect(calls, ['related', 'search']);
      expect(page.videos.single['id'], 'other');
      expect(page.hasMore, false);
      expect(page.error, isNull);
    },
  );
  test('query change has an independent search cursor; repeated tokens cannot loop', () async {
    var calls = 0;
    final repo = RelatedRepository(
      {'id': 'current', 'title': 'x'},
      query: 'tình ca',
      request: (method, args) async {
        calls++;
        expect(method, 'search');
        return {'videos': [], 'continuation': 'same'};
      },
    );
    final page = await repo.next();
    expect(page.hasMore, false);
    expect(calls, 2);
  });
}
