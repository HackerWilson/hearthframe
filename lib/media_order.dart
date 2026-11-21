import 'dart:math';

import 'sources.dart';

List<MediaItem> orderMedia(
  List<MediaItem> items, {
  required bool shuffle,
  required bool recentWeighted,
  Random? random,
}) {
  final ordered = List<MediaItem>.of(items);
  if (!shuffle) {
    ordered.sort((a, b) => a.path.compareTo(b.path));
    return ordered;
  }
  final rng = random ?? Random();
  if (!recentWeighted || ordered.length < 2) {
    ordered.shuffle(rng);
    return ordered;
  }
  final times = [
    for (final item in ordered)
      if ((item.mtime ?? 0) > 0) item.mtime!,
  ]..sort();
  if (times.isEmpty) {
    ordered.shuffle(rng);
    return ordered;
  }
  final oldest = times.first;
  final span = times.last - oldest;
  final keyed = <MapEntry<double, MediaItem>>[];
  for (final item in ordered) {
    final t = item.mtime ?? 0;
    final rank = t <= 0 || span == 0 ? 0.0 : (t - oldest) / span;
    final weight = 1.0 + 4.0 * rank.clamp(0.0, 1.0);
    keyed.add(MapEntry(pow(rng.nextDouble(), 1.0 / weight).toDouble(), item));
  }
  keyed.sort((a, b) => b.key.compareTo(a.key));
  return [for (final entry in keyed) entry.value];
}
