import 'dart:convert';
import 'dart:io' as io;

import 'package:dio/dio.dart';
import 'package:file/memory.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Answers API calls from a list of (method, path regex, json) rows; logs anything it doesn't know.
class FakeApi implements HttpClientAdapter {
  FakeApi(this.routes);

  final List<(String, RegExp, Object? Function(RequestOptions))> routes;
  final unknown = <String>{};

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    final path = o.uri.path + (o.uri.query.isEmpty ? '' : '?${o.uri.query}');
    for (final (m, re, f) in routes) {
      if (m == o.method && re.hasMatch(path)) {
        final json = f(o);
        return ResponseBody.fromString(jsonEncode(json), json == null ? 204 : 200,
            headers: {Headers.contentTypeHeader: ['application/json']});
      }
    }
    unknown.add('${o.method} $path');
    return ResponseBody.fromString('{"detail":"Not Found"}', 404,
        headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

/// Serves `https://img.test/NAME` from `test/screenshots/media/NAME` (CachedNetworkImage in tests).
class FakeImageCache implements BaseCacheManager {
  FakeImageCache() {
    for (final f in io.Directory('test/screenshots/media').listSync().whereType<io.File>()) {
      final name = f.uri.pathSegments.last;
      _fs.file('/$name').writeAsBytesSync(f.readAsBytesSync());
    }
  }

  final _fs = MemoryFileSystem();

  FileInfo _info(String url) =>
      FileInfo(_fs.file('/${Uri.parse(url).pathSegments.last}'), FileSource.Cache, DateTime(2100), url);

  @override
  Stream<FileResponse> getFileStream(String url, {String? key, Map<String, String>? headers, bool withProgress = false}) =>
      Stream.value(_info(url));

  @override
  Future<FileInfo?> getFileFromCache(String key, {bool ignoreMemCache = false}) async => null;

  @override
  Future<FileInfo?> getFileFromMemory(String key) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Roboto + Material Icons from the Flutter SDK (tests otherwise draw boxes), plus Windows' emoji font.
Future<void> loadFonts() async {
  final sdk = io.Platform.environment['FLUTTER_ROOT'] ??
      io.File(io.Platform.resolvedExecutable).parent.parent.parent.parent.parent.parent.path;
  final dir = '$sdk/bin/cache/artifacts/material_fonts';
  Future<ByteData> read(String p) async => ByteData.sublistView(await io.File(p).readAsBytes());

  final roboto = FontLoader('Roboto');
  for (final w in ['regular', 'medium', 'bold', 'black', 'light', 'italic', 'mediumitalic', 'bolditalic']) {
    final f = io.File('$dir/roboto-$w.ttf');
    if (f.existsSync()) roboto.addFont(read(f.path));
  }
  await roboto.load();
  // Text with no family (e.g. the logo's wordmark) gets the test font, which draws boxes; a phone would use
  // its system font, so map the test font to Roboto too.
  final fallback = FontLoader('FlutterTest');
  for (final w in ['regular', 'medium', 'bold', 'black']) {
    final f = io.File('$dir/roboto-$w.ttf');
    if (f.existsSync()) fallback.addFont(read(f.path));
  }
  await fallback.load();

  // Emoji: Segoe UI Emoji on Windows (Noto's COLRv1 build draws nothing in tests). Elsewhere emoji show blank.
  const segoe = 'C:/Windows/Fonts/seguiemj.ttf';
  const symbols = 'C:/Windows/Fonts/seguisym.ttf'; // ⅓ and friends
  if (io.File(symbols).existsSync()) await (FontLoader('SegoeSymbol')..addFont(read(symbols))).load();
  if (io.File(segoe).existsSync()) await (FontLoader('SegoeEmoji')..addFont(read(segoe))).load();

  // flutter_math_fork's KaTeX fonts (package fonts aren't loaded in tests)
  final config = jsonDecode(io.File('.dart_tool/package_config.json').readAsStringSync()) as Map<String, dynamic>;
  final pkg = (config['packages'] as List).cast<Map<String, dynamic>>().where((p) => p['name'] == 'flutter_math_fork');
  final Uri? math = pkg.isEmpty
      ? null
      : io.File('.dart_tool/package_config.json').absolute.uri.resolve('${pkg.first['rootUri']}/').resolve('lib/');
  if (math != null) {
    final files = io.Directory.fromUri(math.resolve('katex_fonts/fonts/')).listSync().whereType<io.File>().toList();
    final families = <String, FontLoader>{};
    for (final f in files) {
      final name = f.uri.pathSegments.last;
      if (!name.endsWith('.ttf')) continue;
      final family = name.substring(0, name.indexOf('-'));
      families.putIfAbsent(family, () => FontLoader('packages/flutter_math_fork/$family')).addFont(read(f.path));
    }
    for (final l in families.values) {
      await l.load();
    }
  }

  final icons = FontLoader('MaterialIcons')..addFont(read('$dir/materialicons-regular.otf'));
  await icons.load();
}
