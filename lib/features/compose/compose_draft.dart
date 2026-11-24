import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../feed/models.dart';

/// Something to open the composer with: a result card ("Post to feed") or content shared from
/// another app ("Share to Outstagram"). Images are raw bytes in any format; the composer compresses them.
class ComposeDraft {
  const ComposeDraft({this.images = const [], this.caption, this.category});

  final List<Uint8List> images;
  final String? caption;
  final PostCategory? category;

  bool get isEmpty => images.isEmpty && (caption == null || caption!.trim().isEmpty);
}

/// Set it, then navigate to `/create`; the composer takes it (and clears it) when it sees it.
final composeDraftProvider = NotifierProvider<ComposeDraftNotifier, ComposeDraft?>(ComposeDraftNotifier.new);

class ComposeDraftNotifier extends Notifier<ComposeDraft?> {
  @override
  ComposeDraft? build() => null;

  void set(ComposeDraft d) => state = d;

  ComposeDraft? take() {
    final d = state;
    state = null;
    return d;
  }
}
