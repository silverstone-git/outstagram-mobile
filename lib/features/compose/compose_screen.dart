import 'dart:io';

import '../account/account_api.dart';
import '../account/account_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/net/api_error.dart';
import '../../core/ui/feedback.dart';
import '../billing/billing_api.dart';
import '../billing/paywall_sheet.dart';
import 'compose_draft.dart';
import 'video_compressor.dart';
import '../feed/models.dart';
import '../feed/social_api.dart';

/// Bumped after a post is created so feeds and profiles reload.
final postsVersionProvider = NotifierProvider<PostsVersion, int>(PostsVersion.new);

class PostsVersion extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

/// A compressed photo (bytes) or a video file (path), in the order they'll be posted.
class _Picked {
  _Picked(Uint8List this.bytes)
      : videoPath = null,
        videoSize = 0,
        compressed = false;

  _Picked.video(String this.videoPath, this.videoSize, {this.compressed = false}) : bytes = null;

  final Uint8List? bytes;
  final String? videoPath;
  final int videoSize;

  /// The file is our compressed copy in the cache (delete it when done), not the user's original.
  final bool compressed;

  bool get isVideo => videoPath != null;
}

const _videoMime = {'mp4': 'video/mp4', 'mov': 'video/quicktime', 'webm': 'video/webm', 'mkv': 'video/x-matroska',
    'm4v': 'video/x-m4v', '3gp': 'video/3gpp'};

class ComposeScreen extends ConsumerStatefulWidget {
  const ComposeScreen({super.key});

  @override
  ConsumerState<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends ConsumerState<ComposeScreen> {
  /// Photos + videos per post (plan's `media_per_post`, 4 for everyone).
  int get _maxImages => ref.read(billingStatusProvider).value?.limits.mediaPerPost ?? 4;

  final _caption = TextEditingController();
  final _picker = ImagePicker();
  final _images = <_Picked>[];
  var _category = PostCategory.academic;
  var _compressing = false;
  double? _progress; // non-null while posting
  double? _videoProgress; // non-null while a video is being compressed
  static const _compressor = VideoCompressor();
  List<String> _trending = const [];

  @override
  void initState() {
    super.initState();
    ref.read(socialApiProvider).trending().then((t) {
      if (mounted) setState(() => _trending = t.take(8).toList());
    });
    // A draft set before this tab was first built (e.g. shared from another app at launch).
    Future.microtask(() {
      final d = ref.read(composeDraftProvider.notifier).take();
      if (d != null) _applyDraft(d);
    });
  }

  /// Fills the composer from a [ComposeDraft]; replaces what's there unless the draft has no images.
  Future<void> _applyDraft(ComposeDraft d) async {
    if (!mounted || d.isEmpty) return;
    setState(() {
      if (d.images.isNotEmpty || d.videos.isNotEmpty) _images.clear();
      if (d.caption != null && d.caption!.trim().isNotEmpty) {
        _caption.text = d.caption!.trim();
        _caption.selection = TextSelection.collapsed(offset: _caption.text.length);
      }
      if (d.category != null) _category = d.category!;
    });
    for (final v in d.videos) {
      await _addVideo(v);
    }
    if (d.images.isEmpty) return;
    setState(() => _compressing = true);
    final max = await _maxBytes();
    var skipped = 0;
    for (final raw in d.images.take(_maxImages)) {
      final bytes = await _compressBytes(raw, max);
      if (bytes == null) {
        skipped++;
      } else if (mounted) {
        setState(() => _images.add(_Picked(bytes)));
      }
    }
    if (mounted) {
      setState(() => _compressing = false);
      if (skipped > 0) showError(context, ApiException('$skipped photo(s) were too large even after compression'));
    }
  }

  @override
  void dispose() {
    if (_videoProgress != null) _compressor.cancel();
    for (final m in _images) {
      if (m.compressed) VideoCompressor.deleteOutput(m.videoPath);
    }
    _caption.dispose();
    super.dispose();
  }

  void _remove(int i) {
    final m = _images[i];
    setState(() => _images.removeAt(i));
    if (m.compressed) VideoCompressor.deleteOutput(m.videoPath);
  }

  /// The plan's per-file limit (free: 200 kB). Falls back to the free limit offline.
  Future<int> _maxBytes() async {
    try {
      return (await ref.read(billingStatusProvider.future)).limits.mediaBytes;
    } catch (_) {
      return Limits.free.mediaBytes;
    }
  }

  /// Downscale + WebP, stepping quality down until it fits the plan's limit.
  Future<Uint8List?> _compress(XFile f, int max) async => _compressBytes(await f.readAsBytes(), max);

  Future<Uint8List?> _compressBytes(Uint8List raw, int max) async {
    // Paid plans (4 MB Pro, 20 MB Contributor) keep big, high-quality photos; Free steps down to fit 200 kB.
    final steps = [
      if (max >= 15000000) (4096, 92),
      if (max >= 4000000) ...[(3072, 90), (2048, 88)],
      (1600, 82), (1440, 72), (1280, 62), (1080, 52), (900, 45),
    ];
    for (final (side, q) in steps) {
      final out = await FlutterImageCompress.compressWithList(
        raw,
        minWidth: side,
        minHeight: side,
        quality: q,
        format: CompressFormat.webp,
      );
      if (out.length <= max) return out;
    }
    return null;
  }

  Future<void> _pick(ImageSource source) async {
    final room = _maxImages - _images.length;
    if (room <= 0) return;
    final List<XFile> files = source == ImageSource.camera
        ? [?await _picker.pickImage(source: ImageSource.camera)]
        : await _picker.pickMultiImage(limit: room);
    if (files.isEmpty) return;
    setState(() => _compressing = true);
    final max = await _maxBytes();
    var skipped = 0;
    for (final f in files.take(room)) {
      final bytes = await _compress(f, max);
      if (bytes == null) {
        skipped++;
      } else if (mounted) {
        setState(() => _images.add(_Picked(bytes)));
      }
    }
    if (mounted) {
      setState(() => _compressing = false);
      if (skipped > 0) showError(context, ApiException('$skipped photo(s) were too large even after compression'));
    }
  }

  Future<void> _pickVideo() async {
    if (_images.length >= _maxImages || _videoProgress != null) return;
    final f = await _picker.pickVideo(source: ImageSource.gallery);
    if (f != null) await _addVideo(f.path);
  }

  /// Videos are uploaded as they are, so they must fit the plan's per-file limit (free 200 kB, Pro 15 MB).
  Future<Limits> _limits() async {
    try {
      return (await ref.read(billingStatusProvider.future)).limits;
    } catch (_) {
      return Limits.free;
    }
  }

  /// Free can't post videos. Clips that fit the plan (Pro 4 MB, Contributor 500 MB) are kept as they are;
  /// bigger ones (and Contributor clips over 100 MB) are compressed on the phone to fit.
  Future<void> _addVideo(String path) async {
    if (_images.length >= _maxImages || !mounted || _videoProgress != null) return;
    final size = await File(path).length();
    final lim = await _limits();
    if (!mounted) return;
    final plan = ref.read(billingStatusProvider).value?.plan ?? 'free';
    if (!lim.videosAllowed) {
      showPaywall(context, code: 'video_not_allowed', needs: 'pro',
          message: 'Posting videos needs Pro (up to 4 MB) or Contributor (up to 500 MB).');
      return;
    }
    final max = lim.videoBytes;
    final needs = plan == 'pro' ? 'contributor' : null;
    void tooBig(String msg) => showError(context, ApiException(msg, status: 413, code: 'media_too_large',
        detail: {'code': 'media_too_large', 'message': msg, 'upgrade': needs != null, 'needs': ?needs,
            'size': size, 'limit': max}));

    if (size <= (max ?? size) && size <= bigClipBytes) {
      setState(() => _images.add(_Picked.video(path, size)));
      return;
    }
    VideoInfo info;
    try {
      info = await _compressor.probe(path);
    } catch (_) {
      if (mounted) showError(context, ApiException("Couldn't read this video."));
      return;
    }
    if (!mounted) return;
    final todo = planVideo(size: size, durationMs: info.durationMs, limit: max);
    switch (todo) {
      case KeepVideo():
        setState(() => _images.add(_Picked.video(path, size)));
        return;
      case VideoTooLong(:final maxSeconds):
        tooBig('This clip is too long to fit your plan (${fmtBytes(max ?? 0)} per video) even compressed. '
            'Trim it to about $maxSeconds s in your gallery${needs == null ? '' : ', or upgrade'}.');
        return;
      case CompressVideo():
        break;
    }
    setState(() => _videoProgress = 0);
    String? out;
    try {
      out = await _compressor.compress(path, todo,
          onProgress: (p) => mounted ? setState(() => _videoProgress = p) : null);
      final outSize = await File(out).length();
      if (!mounted) {
        await VideoCompressor.deleteOutput(out);
        return;
      }
      if (max == null || size <= max) {
        // fitted already (a big Contributor clip): use whichever is smaller
        if (outSize >= size) {
          await VideoCompressor.deleteOutput(out);
          setState(() => _images.add(_Picked.video(path, size)));
          return;
        }
      } else if (outSize > max) {
        await VideoCompressor.deleteOutput(out);
        tooBig('Even compressed, this clip is ${fmtBytes(outSize)}; your plan allows ${fmtBytes(max)}. '
            'Trim it in your gallery first.');
        return;
      }
      setState(() => _images.add(_Picked.video(out!, outSize, compressed: true)));
    } on VideoCompressCancelled {
      // the user cancelled; nothing to add
    } catch (e) {
      await VideoCompressor.deleteOutput(out);
      if (mounted) showError(context, ApiException("Couldn't compress this video. Try a shorter clip."));
    } finally {
      if (mounted) setState(() => _videoProgress = null);
    }
  }

  void _addTag(String tag) {
    final t = '#$tag';
    if (_caption.text.contains(t)) return;
    _caption.text = _caption.text.isEmpty ? t : '${_caption.text.trimRight()} $t';
    _caption.selection = TextSelection.collapsed(offset: _caption.text.length);
    setState(() {});
  }

  bool get _canPost =>
      (_images.isNotEmpty || _caption.text.trim().isNotEmpty) && _progress == null && !_compressing && _videoProgress == null;

  Future<void> _post() async {
    if (!_canPost) return;
    FocusScope.of(context).unfocus();
    setState(() => _progress = 0);
    try {
      final api = ref.read(socialApiProvider);
      // Photos go through the server (it re-checks and compresses); videos straight to the bucket with
      // a presigned PUT (they can be far bigger than a Cloud Run request). Progress is by bytes.
      final photos = [for (final m in _images) if (!m.isVideo) m];
      final total = _images.fold<int>(0, (n, m) => n + (m.isVideo ? m.videoSize : m.bytes!.length)).clamp(1, 1 << 62);
      var done = 0;
      void progress(int sent) => mounted ? setState(() => _progress = (done + sent) / total * 0.95) : null;
      final photoUrls = photos.isEmpty
          ? const <Map<String, String>>[]
          : await api.upload([
              for (var i = 0; i < photos.length; i++)
                UploadFile(bytes: photos[i].bytes!, filename: 'photo_$i.webp', mime: 'image/webp'),
            ], onProgress: (p) => progress((p * photos.fold<int>(0, (n, m) => n + m.bytes!.length)).round()));
      done += photos.fold<int>(0, (n, m) => n + m.bytes!.length);
      final media = <Map<String, String>>[];
      var pi = 0;
      for (final m in _images) {
        if (!m.isVideo) {
          media.add(photoUrls[pi++]);
          continue;
        }
        final ext = m.videoPath!.split('.').last.toLowerCase();
        media.add(await api.uploadVideo(
          m.videoPath!,
          m.videoSize,
          mime: _videoMime[ext] ?? 'video/mp4',
          onSent: progress,
        ));
        done += m.videoSize;
      }
      await api.createPost(media: media, caption: _caption.text.trim(), category: _category);
      HapticFeedback.heavyImpact();
      ref.read(postsVersionProvider.notifier).bump();
      for (final m in _images) {
        if (m.compressed) VideoCompressor.deleteOutput(m.videoPath);
      }
      if (!mounted) return;
      setState(() {
        _images.clear();
        _caption.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Posted!')));
      context.go('/profile');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(composeDraftProvider, (_, d) {
      if (d != null) _applyDraft(ref.read(composeDraftProvider.notifier).take()!);
    });
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('New post'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(84, 40)),
              onPressed: _canPost ? _post : null,
              child: const Text('Share'),
            ),
          ),
        ],
        bottom: _progress == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(value: _progress),
              ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (ref.watch(meProvider).value?.needsVerification ?? false) ...[
            const VerifyEmailBanner(reason: 'share posts'),
            const SizedBox(height: 12),
          ],
          SizedBox(
            height: 132,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (var i = 0; i < _images.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: _images[i].isVideo
                              ? _VideoTile(size: _images[i].videoSize)
                              : Image.memory(_images[i].bytes!, width: 132, height: 132, fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => _remove(i),
                            child: const CircleAvatar(
                              radius: 13,
                              backgroundColor: Colors.black54,
                              child: Icon(Icons.close_rounded, size: 16, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_videoProgress != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: VideoCompressTile(progress: _videoProgress!, onCancel: _compressor.cancel),
                  ),
                if (_images.length + (_videoProgress == null ? 0 : 1) < _maxImages) ...[
                  _PickTile(
                    icon: Icons.photo_library_outlined,
                    label: 'Gallery',
                    busy: _compressing,
                    onTap: () => _pick(ImageSource.gallery),
                  ),
                  const SizedBox(width: 8),
                  _PickTile(
                    icon: Icons.photo_camera_outlined,
                    label: 'Camera',
                    busy: false,
                    onTap: () => _pick(ImageSource.camera),
                  ),
                  const SizedBox(width: 8),
                  _PickTile(
                    icon: Icons.video_library_outlined,
                    label: 'Video',
                    busy: false,
                    onTap: _pickVideo,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _caption,
            minLines: 3,
            maxLines: 8,
            maxLength: 2200,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: 'What did you learn, build or ace today?'),
          ),
          if (_trending.isNotEmpty) ...[
            Text(
              'Trending',
              style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final t in _trending) ActionChip(label: Text('#$t'), onPressed: () => _addTag(t))],
            ),
            const SizedBox(height: 16),
          ],
          Text(
            'Category',
            style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in PostCategory.values)
                ChoiceChip(
                  label: Text('${c.emoji} ${c.label}'),
                  selected: _category == c,
                  onSelected: (_) => setState(() => _category = c),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _limitsText(ref.watch(billingStatusProvider).value?.limits ?? Limits.free),
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// "Up to 4 photos or videos. Photos are compressed … Videos need Pro." for the plan's limits.
String _limitsText(Limits l) {
  final videos = !l.videosAllowed
      ? 'Videos need Pro or Contributor.'
      : 'Videos are compressed on your phone to fit your plan (up to ${fmtLimit(l.videoBytes, fmtBytes)} each).';
  return 'Up to ${l.mediaPerPost ?? 4} photos or videos per post. Photos are compressed on your phone '
      '(WebP, ≤${fmtBytes(l.mediaBytes)} each). $videos';
}

/// "Compressing 42%" with a cancel button, shown in the media strip while a clip is compressed.
class VideoCompressTile extends StatelessWidget {
  const VideoCompressTile({super.key, required this.progress, required this.onCancel});

  final double progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 132,
          height: 132,
          color: Colors.black87,
          padding: const EdgeInsets.all(6),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(value: progress > 0 ? progress : null, color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text('Compressing ${(progress * 100).round()}%',
                style: const TextStyle(color: Colors.white, fontSize: 12)),
            TextButton(
              onPressed: onCancel,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white70,
                minimumSize: const Size(64, 32),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Cancel'),
            ),
          ]),
        ),
      );
}

class _VideoTile extends StatelessWidget {
  const _VideoTile({required this.size});

  final int size;

  @override
  Widget build(BuildContext context) => Container(
        width: 132,
        height: 132,
        color: Colors.black87,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 40),
          const SizedBox(height: 6),
          Text('Video · ${fmtBytes(size)}', style: const TextStyle(color: Colors.white, fontSize: 12)),
        ]),
      );
}

class _PickTile extends StatelessWidget {
  const _PickTile({required this.icon, required this.label, required this.busy, required this.onTap});

  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 110,
        height: 132,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            busy
                ? const SizedBox.square(dimension: 26, child: CircularProgressIndicator(strokeWidth: 2.5))
                : Icon(icon, size: 30, color: cs.primary),
            const SizedBox(height: 6),
            Text(label),
          ],
        ),
      ),
    );
  }
}
