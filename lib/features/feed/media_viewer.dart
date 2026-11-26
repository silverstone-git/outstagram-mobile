import 'package:cached_network_image/cached_network_image.dart';

import '../../core/ui/avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'models.dart';

/// Full-screen media: swipe between items, pinch or double-tap to zoom photos, swipe down / back to close.
Future<void> openMediaViewer(BuildContext context, List<Media> media, int index) =>
    Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (_, _, _) => MediaViewer(media: media, initial: index),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ));

class MediaViewer extends StatefulWidget {
  const MediaViewer({super.key, required this.media, this.initial = 0});

  final List<Media> media;
  final int initial;

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  late final _pages = PageController(initialPage: widget.initial);
  late var _index = widget.initial;
  var _zoomed = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        PageView.builder(
          controller: _pages,
          physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
          itemCount: widget.media.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (_, i) {
            final m = widget.media[i];
            if (m.isVideo) return Center(child: PostVideo(url: m.url, autoplay: i == _index, fit: BoxFit.contain));
            return ZoomableImage(url: m.url, onZoomChanged: (z) => setState(() => _zoomed = z));
          },
        ),
        SafeArea(
          child: Row(children: [
            IconButton(
              tooltip: 'Close',
              color: Colors.white,
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
            const Spacer(),
            if (widget.media.length > 1)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text('${_index + 1}/${widget.media.length}', style: const TextStyle(color: Colors.white)),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// A photo that pinch-zooms (up to 5×) and double-tap toggles 2.5× around the tap point.
class ZoomableImage extends StatefulWidget {
  const ZoomableImage({super.key, required this.url, this.onZoomChanged});

  final String url;
  final ValueChanged<bool>? onZoomChanged;

  @override
  State<ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<ZoomableImage> with SingleTickerProviderStateMixin {
  final _ctl = TransformationController();
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  Animation<Matrix4>? _tween;
  Offset _tap = Offset.zero;
  var _zoomed = false;

  @override
  void initState() {
    super.initState();
    _anim.addListener(() {
      if (_tween != null) _ctl.value = _tween!.value;
    });
    _ctl.addListener(() {
      final z = _ctl.value.getMaxScaleOnAxis() > 1.01;
      if (z != _zoomed) {
        _zoomed = z;
        widget.onZoomChanged?.call(z);
      }
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    _ctl.dispose();
    super.dispose();
  }

  void _toggle() {
    final Matrix4 end;
    if (_zoomed) {
      end = Matrix4.identity();
    } else {
      const s = 2.5;
      end = Matrix4.identity()
        ..translateByDouble(-_tap.dx * (s - 1), -_tap.dy * (s - 1), 0, 1)
        ..scaleByDouble(s, s, 1, 1);
    }
    _tween = Matrix4Tween(begin: _ctl.value, end: end).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    _anim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (d) => _tap = d.localPosition,
      onDoubleTap: _toggle,
      child: InteractiveViewer(
        transformationController: _ctl,
        minScale: 1,
        maxScale: 5,
        child: SizedBox.expand(
          child: CachedNetworkImage(
            imageUrl: widget.url,
            cacheKey: Avatar.cacheKey(widget.url), // same entry as the feed's copy
            fit: BoxFit.contain,
            placeholder: (_, _) => const Center(child: CircularProgressIndicator(color: Colors.white)),
            errorWidget: (_, _, _) => const Center(child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48)),
          ),
        ),
      ),
    );
  }
}

/// Inline video: first frame with a play button; tap plays/pauses, loops, starts muted in the feed.
class PostVideo extends StatefulWidget {
  const PostVideo({super.key, required this.url, this.autoplay = false, this.fit = BoxFit.cover});

  final String url;
  final bool autoplay;
  final BoxFit fit;

  @override
  State<PostVideo> createState() => _PostVideoState();
}

class _PostVideoState extends State<PostVideo> {
  late final VideoPlayerController _c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
  var _ready = false;
  var _failed = false;
  late var _muted = !widget.autoplay;

  @override
  void initState() {
    super.initState();
    _c.setLooping(true);
    _c.initialize().then((_) {
      if (!mounted) return;
      _c.setVolume(_muted ? 0 : 1);
      if (widget.autoplay) _c.play();
      setState(() => _ready = true);
    }, onError: (_) {
      if (mounted) setState(() => _failed = true);
    });
    _c.addListener(_tick);
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(PostVideo old) {
    super.didUpdateWidget(old);
    if (old.autoplay && !widget.autoplay) _c.pause();
  }

  @override
  void dispose() {
    _c.removeListener(_tick);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: Icon(Icons.videocam_off_outlined, color: Colors.white54, size: 48)),
      );
    }
    if (!_ready) {
      return const ColoredBox(color: Colors.black, child: Center(child: CircularProgressIndicator(color: Colors.white)));
    }
    final playing = _c.value.isPlaying;
    final size = _c.value.size;
    return GestureDetector(
      onTap: () => playing ? _c.pause() : _c.play(),
      child: ColoredBox(
        color: Colors.black,
        child: Stack(fit: StackFit.expand, children: [
          FittedBox(
            fit: widget.fit,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(width: size.width, height: size.height, child: VideoPlayer(_c)),
          ),
          if (!playing)
            const Center(child: Icon(Icons.play_circle_fill_rounded, size: 72, color: Colors.white70)),
          Positioned(
            right: 8,
            bottom: 8,
            child: IconButton.filledTonal(
              tooltip: _muted ? 'Sound on' : 'Mute',
              iconSize: 18,
              onPressed: () {
                setState(() => _muted = !_muted);
                _c.setVolume(_muted ? 0 : 1);
              },
              icon: Icon(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: VideoProgressIndicator(_c, allowScrubbing: true, padding: EdgeInsets.zero),
          ),
        ]),
      ),
    );
  }
}
