import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearthframe/media_cache.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hf_cache_test');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<File> put(String name, int bytes, DateTime modified) async {
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(List.filled(bytes, 0));
    await file.setLastModified(modified);
    return file;
  }

  test('prune removes the oldest entries until under the limit', () async {
    final now = DateTime.now();
    final oldest =
        await put('a.bin', 600, now.subtract(const Duration(days: 3)));
    final middle =
        await put('b.bin', 600, now.subtract(const Duration(days: 2)));
    final newest =
        await put('c.bin', 600, now.subtract(const Duration(days: 1)));
    final inFlight = await put('x.part', 5000, now);
    final stale =
        await put('y.part', 700, now.subtract(const Duration(days: 4)));

    await pruneCacheDir(dir, maxBytes: 1200);

    expect(await oldest.exists(), isFalse);
    expect(await middle.exists(), isTrue);
    expect(await newest.exists(), isTrue);
    expect(await inFlight.exists(), isTrue);
    expect(await stale.exists(), isFalse);
  });

  test('prune never removes kept or active entries', () async {
    final now = DateTime.now();
    final oldest =
        await put('a.bin', 600, now.subtract(const Duration(days: 3)));
    final active =
        await put('b.bin', 600, now.subtract(const Duration(days: 2)));
    final kept = await put('c.bin', 600, now.subtract(const Duration(days: 1)));

    await pruneCacheDir(
      dir,
      maxBytes: 600,
      keep: {kept.path},
      activePath: active.path,
    );

    expect(await oldest.exists(), isFalse);
    expect(await active.exists(), isTrue);
    expect(await kept.exists(), isTrue);
  });

  test('clear removes finished entries but keeps the active one', () async {
    final active = await put('a.bin', 300, DateTime.now());
    final other = await put('b.bin', 700, DateTime.now());
    final part = await put('x.part', 900, DateTime.now());

    final freed = await clearCacheDir(dir, activePath: active.path);

    expect(freed, 700);
    expect(await active.exists(), isTrue);
    expect(await other.exists(), isFalse);
    expect(await part.exists(), isTrue);
  });

  test('formatBytes is compact and readable', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.50 KB');
    expect(formatBytes(5 * 1024 * 1024), '5.00 MB');
    expect(formatBytes((1.5 * 1024 * 1024 * 1024).round()), '1.50 GB');
  });
}
