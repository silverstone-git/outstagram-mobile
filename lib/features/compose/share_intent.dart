import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../app/router.dart';
import '../../core/auth/auth_controller.dart';
import 'compose_draft.dart';

/// "Share to Outstagram": photos and text shared from other apps (Android share sheet) open the
/// composer prefilled. Wraps the app once (MaterialApp.router `builder`). If nobody is signed in,
/// the draft waits until sign-in, then the composer opens.
class ShareIntentListener extends ConsumerStatefulWidget {
  const ShareIntentListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ShareIntentListener> createState() => _ShareIntentListenerState();
}

class _ShareIntentListenerState extends ConsumerState<ShareIntentListener> {
  StreamSubscription<List<SharedMediaFile>>? _sub;

  @override
  void initState() {
    super.initState();
    final share = ReceiveSharingIntent.instance;
    _sub = share.getMediaStream().listen(_handle, onError: (Object e) => debugPrint('share intent: $e'));
    share.getInitialMedia().then((files) {
      _handle(files);
      share.reset();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _handle(List<SharedMediaFile> files) async {
    if (files.isEmpty || !mounted) return;
    final draft = await draftFromShared(files);
    if (draft.isEmpty || !mounted) return;
    ref.read(composeDraftProvider.notifier).set(draft);
    _open();
  }

  void _open() {
    final signedIn = ref.read(authControllerProvider).value != null;
    if (signedIn) ref.read(routerProvider).go('/create');
  }

  @override
  Widget build(BuildContext context) {
    // Shared while signed out: open the composer right after sign-in.
    ref.listen(authControllerProvider, (prev, next) {
      final wasIn = prev?.value != null, isIn = next.value != null;
      if (!wasIn && isIn && ref.read(composeDraftProvider) != null) {
        Future.microtask(() => ref.read(routerProvider).go('/create'));
      }
    });
    return widget.child;
  }
}

/// Images become draft photos (any format; the composer compresses them), videos draft videos (uploaded as
/// they are), text and links the caption.
Future<ComposeDraft> draftFromShared(List<SharedMediaFile> files) async {
  final images = <Uint8List>[];
  final videos = <String>[];
  final text = <String>[];
  for (final f in files) {
    switch (f.type) {
      case SharedMediaType.image:
        try {
          images.add(await File(f.path).readAsBytes());
        } catch (e) {
          debugPrint('share intent: cannot read ${f.path}: $e');
        }
      case SharedMediaType.text || SharedMediaType.url:
        // The plugin also reports the app's own VIEW intents (launcher shortcuts: outstagram://app/...)
        // as a shared URL on a cold start; those are navigation, not content.
        if (f.path.trim().isNotEmpty && !isOwnDeepLink(f.path)) text.add(f.path.trim());
      case SharedMediaType.video:
        if (File(f.path).existsSync()) videos.add(f.path);
      default:
        break; // other files: not supported by the composer
    }
    final msg = f.message?.trim();
    if (msg != null && msg.isNotEmpty && !isOwnDeepLink(msg) && !text.contains(msg)) text.add(msg);
  }
  return ComposeDraft(images: images, videos: videos, caption: text.isEmpty ? null : text.join('\n'));
}

/// Links the app opens itself: launcher shortcuts (`res/xml/shortcuts.xml`) and App Links to posts and
/// profiles (`https://outstagram.aryan.cfd/p/?id=…`, `/u/?name=…`; staging under `https://aryan.cfd/outstagram/`), and email
/// sign-in links (`…/signin/?h=…`).
/// They're navigation, not content.
bool isOwnDeepLink(String s) {
  final t = s.trim();
  return t.startsWith('outstagram://') ||
      RegExp(r'^https://aryan\.cfd/outstagram/([pu]|signin)/?\?\S*$').hasMatch(t) ||
      RegExp(r'^https://outstagram\.aryan\.cfd/([pu]|signin)/?\?\S*$').hasMatch(t);
}
