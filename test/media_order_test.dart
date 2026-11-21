import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearthframe/media_order.dart';
import 'package:hearthframe/sources.dart';

void main() {
  final items = List.generate(
      20,
      (i) => MediaItem('/photo/${i.toString().padLeft(2, '0')}.jpg',
          mtime: i * 1000 + 1000));

  test('turning shuffle off restores path order without mutating input', () {
    final reversed = items.reversed.toList();
    expect(
        orderMedia(reversed, shuffle: false, recentWeighted: true)
            .map((e) => e.path),
        items.map((e) => e.path));
    expect(reversed.first, same(items.last));
  });

  test('each shuffle includes every media exactly once including new batches',
      () {
    final ordered = orderMedia(items,
        shuffle: true, recentWeighted: false, random: Random(7));
    expect(ordered.toSet(), items.toSet());
    expect(ordered, isNot(items));
    final newBatch = [
      const MediaItem('/new/video.mp4', isVideo: true, mtime: 99999)
    ];
    final refreshed = orderMedia([...ordered, ...newBatch],
        shuffle: true, recentWeighted: true, random: Random(7));
    expect(refreshed.toSet(), {...items, ...newBatch});
    expect(refreshed.length, 21);
  });

  test('recent weighting changes the order for identical random draws', () {
    final plain = orderMedia(items,
        shuffle: true, recentWeighted: false, random: Random(17));
    final weighted = orderMedia(items,
        shuffle: true, recentWeighted: true, random: Random(17));
    expect(weighted.toSet(), items.toSet());
    expect(weighted, isNot(plain));
  });

  test('weighted sampling favors recent items without excluding older ones',
      () {
    var oldFirst = 0;
    var recentFirst = 0;
    for (var seed = 0; seed < 500; seed++) {
      final ordered = orderMedia([items.first, items.last],
          shuffle: true, recentWeighted: true, random: Random(seed));
      if (ordered.first == items.first) {
        oldFirst++;
      } else {
        recentFirst++;
      }
    }
    expect(oldFirst, greaterThan(0));
    expect(recentFirst, greaterThan(oldFirst * 2));
  });

  test('empty, single and unknown timestamps remain valid permutations', () {
    for (final input in <List<MediaItem>>[
      [],
      [items.first],
      [const MediaItem('a'), const MediaItem('b', mtime: 0)]
    ]) {
      final ordered = orderMedia(input,
          shuffle: true, recentWeighted: true, random: Random(1));
      expect(ordered.toSet(), input.toSet());
    }
  });
}
