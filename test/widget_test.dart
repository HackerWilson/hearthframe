import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearthframe/sources.dart';

void main() {
  test('LocalFolderSource collects images and videos recursively', () async {
    final dir = await Directory.systemTemp.createTemp('hearthframe_test');
    try {
      await File('${dir.path}/a.jpg').writeAsString('x');
      await File('${dir.path}/b.MP4').writeAsString('x');
      await File('${dir.path}/note.txt').writeAsString('x');
      final sub = await Directory('${dir.path}/sub').create();
      await File('${sub.path}/c.png').writeAsString('x');

      final items = await LocalFolderSource(dir.path).list();
      final paths = items.map((e) => e.path).toList();

      expect(items.length, 3);
      expect(paths.any((p) => p.endsWith('a.jpg')), isTrue);
      expect(paths.any((p) => p.endsWith('c.png')), isTrue);
      expect(paths.any((p) => p.endsWith('note.txt')), isFalse);
      final video = items.firstWhere((e) => e.path.endsWith('b.MP4'));
      expect(video.isVideo, isTrue);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('LocalFolderSource returns empty for a missing folder', () async {
    final items =
        await LocalFolderSource('/nonexistent/hearthframe/path').list();
    expect(items, isEmpty);
  });

  test('LocalFolderSource skips thumbnail and hidden directories', () async {
    final dir = await Directory.systemTemp.createTemp('hearthframe_skip');
    try {
      await File('${dir.path}/ok.jpg').writeAsString('x');
      final ea = await Directory('${dir.path}/@eaDir').create();
      await File('${ea.path}/thumb.jpg').writeAsString('x');
      final hidden = await Directory('${dir.path}/.hidden').create();
      await File('${hidden.path}/secret.jpg').writeAsString('x');

      final items = await LocalFolderSource(dir.path).list();
      expect(items.length, 1);
      expect(items.single.path.endsWith('ok.jpg'), isTrue);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
