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
import 'compose_draft.dart';
import '../feed/models.dart';
import '../feed/social_api.dart';

/// Bumped after a post is created so feeds and profiles reload.
final postsVersionProvider = NotifierProvider<PostsVersion, int>(PostsVersion.new);

class PostsVersion extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

class _Picked {
  _Picked(this.bytes);

  final Uint8List bytes;
}

class ComposeScreen extends ConsumerStatefulWidget {
  const ComposeScreen({super.key});

  @override
  ConsumerState<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends ConsumerState<ComposeScreen> {
  static const _maxImages = 10;

  final _caption = TextEditingController();
  final _picker = ImagePicker();
  final _images = <_Picked>[];
  var _category = PostCategory.academic;
  var _compressing = false;
  double? _progress; // non-null while posting
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
      if (d.images.isNotEmpty) _images.clear();
      if (d.caption != null && d.caption!.trim().isNotEmpty) {
        _caption.text = d.caption!.trim();
        _caption.selection = TextSelection.collapsed(offset: _caption.text.length);
      }
      if (d.category != null) _category = d.category!;
    });
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
    _caption.dispose();
    super.dispose();
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
    for (final (side, q) in [(1600, 82), (1440, 72), (1280, 62), (1080, 52), (900, 45)]) {
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

  void _addTag(String tag) {
    final t = '#$tag';
    if (_caption.text.contains(t)) return;
    _caption.text = _caption.text.isEmpty ? t : '${_caption.text.trimRight()} $t';
    _caption.selection = TextSelection.collapsed(offset: _caption.text.length);
    setState(() {});
  }

  bool get _canPost => (_images.isNotEmpty || _caption.text.trim().isNotEmpty) && _progress == null && !_compressing;

  Future<void> _post() async {
    if (!_canPost) return;
    FocusScope.of(context).unfocus();
    setState(() => _progress = 0);
    try {
      final api = ref.read(socialApiProvider);
      var media = <Map<String, String>>[];
      if (_images.isNotEmpty) {
        media = await api.upload([
          for (var i = 0; i < _images.length; i++)
            UploadFile(bytes: _images[i].bytes, filename: 'photo_$i.webp', mime: 'image/webp'),
        ], onProgress: (p) => mounted ? setState(() => _progress = p * 0.9) : null);
      }
      await api.createPost(media: media, caption: _caption.text.trim(), category: _category);
      HapticFeedback.heavyImpact();
      ref.read(postsVersionProvider.notifier).bump();
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
                          child: Image.memory(_images[i].bytes, width: 132, height: 132, fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => setState(() => _images.removeAt(i)),
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
                if (_images.length < _maxImages) ...[
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
            'Photos are compressed on your phone (WebP, ≤${fmtBytes(ref.watch(billingStatusProvider).value?.limits.mediaBytes ?? Limits.free.mediaBytes)} each) before upload.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
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
