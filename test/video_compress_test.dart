import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outstagram/features/compose/compose_screen.dart';
import 'package:outstagram/features/compose/video_compressor.dart';

const mb = 1000 * 1000;
const pro = 4 * mb;
const contributor = 500 * mb;

void main() {
  group('videoBitrateFor', () {
    test('fills the target with 8% headroom, minus audio', () {
      // 3.8 MB over 60 s -> 466 kbps total -> 370 kbps video
      expect(videoBitrateFor(60000, 3800000), closeTo(370133, 1));
    });
    test('clamps to 300 kbps … 8 Mbps', () {
      expect(videoBitrateFor(600000, 3800000), minVideoBitrate);
      expect(videoBitrateFor(5000, 400 * mb), maxVideoBitrate);
    });
    test('unknown duration -> the max bitrate', () => expect(videoBitrateFor(0, pro), maxVideoBitrate));
  });

  group('planVideo', () {
    test('a clip that fits is kept as is', () {
      expect(planVideo(size: 3 * mb, durationMs: 8000, limit: pro), isA<KeepVideo>());
      expect(planVideo(size: 90 * mb, durationMs: 60000, limit: contributor), isA<KeepVideo>());
    });

    test('a 60 s phone clip is compressed to fit Pro at 480p', () {
      final p = planVideo(size: 120 * mb, durationMs: 60000, limit: pro) as CompressVideo;
      expect(p.targetBytes, (pro * 0.95).floor());
      expect(p.maxShortSide, 480);
      // estimated output stays under the limit
      final bytes = (p.videoBitrate + audioBitrate) * 60 / 8;
      expect(bytes, lessThan(pro));
    });

    test('a short clip over Pro gets 720p, never 1080p', () {
      final p = planVideo(size: 30 * mb, durationMs: 8000, limit: pro) as CompressVideo;
      expect(p.maxShortSide, 720);
    });

    test('a clip too long even at the lowest bitrate is refused with a trim hint', () {
      final p = planVideo(size: 300 * mb, durationMs: 180000, limit: pro) as VideoTooLong;
      expect(p.maxSeconds, inInclusiveRange(60, 80));
    });

    test('Contributor: clips over 100 MB are compressed at up to 1080p', () {
      final p = planVideo(size: 200 * mb, durationMs: 120000, limit: contributor) as CompressVideo;
      expect(p.maxShortSide, 1080);
      expect(p.videoBitrate, maxVideoBitrate);
    });

    test('Contributor: over 500 MB still fits once compressed', () {
      expect(planVideo(size: 900 * mb, durationMs: 600000, limit: contributor), isA<CompressVideo>());
    });
  });

  testWidgets('compress tile shows progress and cancels', (tester) async {
    var cancelled = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: VideoCompressTile(progress: 0.42, onCancel: () => cancelled = true)),
    ));
    expect(find.text('Compressing 42%'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    expect(cancelled, isTrue);
  });
}
