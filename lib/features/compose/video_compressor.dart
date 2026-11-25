import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// What `probe` reports about a clip (width/height as displayed, rotation already applied).
class VideoInfo {
  const VideoInfo({required this.durationMs, required this.width, required this.height, required this.bytes});

  factory VideoInfo.fromMap(Map<dynamic, dynamic> m) => VideoInfo(
    durationMs: (m['durationMs'] as num?)?.toInt() ?? 0,
    width: (m['width'] as num?)?.toInt() ?? 0,
    height: (m['height'] as num?)?.toInt() ?? 0,
    bytes: (m['bytes'] as num?)?.toInt() ?? 0,
  );

  final int durationMs;
  final int width;
  final int height;
  final int bytes;
}

/// Keep the clip, compress it with these settings, or refuse it (too long to fit even at the lowest quality).
sealed class VideoPlan {
  const VideoPlan();
}

class KeepVideo extends VideoPlan {
  const KeepVideo();
}

class CompressVideo extends VideoPlan {
  const CompressVideo({required this.videoBitrate, required this.maxShortSide, required this.targetBytes});

  final int videoBitrate;
  final int maxShortSide;
  final int targetBytes;
}

class VideoTooLong extends VideoPlan {
  const VideoTooLong({required this.maxSeconds});

  /// The longest clip that still fits the plan once compressed.
  final int maxSeconds;
}

const audioBitrate = 96000;
const minVideoBitrate = 300000;
const maxVideoBitrate = 8000000;

/// Clips over this get compressed even when the plan would take them (faster uploads on Contributor).
const bigClipBytes = 100 * 1000 * 1000;

/// Video bitrate that makes a clip of [durationMs] come out at about [targetBytes] (8% kept for the container),
/// clamped to 300 kbps…8 Mbps.
int videoBitrateFor(int durationMs, int targetBytes) {
  final sec = durationMs / 1000;
  if (sec <= 0) return maxVideoBitrate;
  final total = targetBytes * 8 * 0.92 / sec;
  return (total - audioBitrate).round().clamp(minVideoBitrate, maxVideoBitrate);
}

/// Short side to scale to: low bitrates look better smaller.
int shortSideFor(int videoBitrate, {required bool allowHd}) {
  if (videoBitrate < 600000) return 480;
  if (videoBitrate < 2500000 || !allowHd) return 720;
  return 1080;
}

/// The keep-or-compress decision for a clip of [size] bytes when the plan allows [limit] bytes per video
/// (null = no limit).
VideoPlan planVideo({required int size, required int durationMs, required int? limit}) {
  final fits = limit == null || size <= limit;
  if (fits && size <= bigClipBytes) return const KeepVideo();
  final target = limit == null ? size : (limit * 0.95).floor();
  if (limit != null && durationMs > 0) {
    // even at the lowest bitrate the clip would be too big
    final minBytes = (minVideoBitrate + audioBitrate) * (durationMs / 1000) / 8 / 0.92;
    if (minBytes > target) {
      return VideoTooLong(maxSeconds: (target * 8 * 0.92 / (minVideoBitrate + audioBitrate)).floor());
    }
  }
  final bitrate = videoBitrateFor(durationMs, target);
  // big plans (Contributor) keep 1080p; Pro's 4 MB is 720p at most
  return CompressVideo(
    videoBitrate: bitrate,
    maxShortSide: shortSideFor(bitrate, allowHd: limit == null || limit > 50 * 1000 * 1000),
    targetBytes: target,
  );
}

class VideoCompressCancelled implements Exception {
  const VideoCompressCancelled();
}

/// Wraps the `outstagram/video` channel (android/.../VideoCompressor.kt). One compression at a time.
class VideoCompressor {
  const VideoCompressor();

  static const _channel = MethodChannel('outstagram/video');
  static const _progress = EventChannel('outstagram/video/progress');

  Future<VideoInfo> probe(String path) async =>
      VideoInfo.fromMap(await _channel.invokeMethod<Map<dynamic, dynamic>>('probe', {'path': path}) ?? const {});

  /// Returns the compressed file's path (in the cache; delete it with [deleteOutput] when done).
  /// Throws [VideoCompressCancelled] after [cancel].
  Future<String> compress(String path, CompressVideo plan, {void Function(double progress)? onProgress}) async {
    final sub = _progress.receiveBroadcastStream().listen((p) => onProgress?.call(((p as num) / 100).clamp(0.0, 1.0)));
    try {
      final out = await _channel.invokeMethod<String>('compress', {
        'path': path,
        'videoBitrate': plan.videoBitrate,
        'audioBitrate': audioBitrate,
        'maxShortSide': plan.maxShortSide,
      });
      return out!;
    } on PlatformException catch (e) {
      if (e.code == 'cancelled') throw const VideoCompressCancelled();
      rethrow;
    } finally {
      await sub.cancel();
    }
  }

  Future<void> cancel() => _channel.invokeMethod<void>('cancel');

  /// Removes a file this class wrote (never the user's original).
  static Future<void> deleteOutput(String? path) async {
    if (path == null || !path.contains('${Platform.pathSeparator}video_out${Platform.pathSeparator}')) return;
    try {
      await File(path).delete();
    } catch (_) {}
  }
}
