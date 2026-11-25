import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/net/api_client.dart';
import '../../core/net/api_error.dart';
import '../../core/ui/avatar.dart';
import '../../core/ui/feedback.dart';
import '../account/account_api.dart';
import '../account/verify_gate.dart';
import '../compose/compose_screen.dart';
import 'profile_view.dart';

final profilePhotoApiProvider = Provider<ProfilePhotoApi>((ref) => ProfilePhotoApi(ref.watch(apiProvider)));

/// `PUT /me/avatar` (multipart `file`; the server crops a 512 px square) and `DELETE /me/avatar`.
class ProfilePhotoApi {
  ProfilePhotoApi(this._api);

  final Api _api;

  Future<String?> upload(Uint8List bytes, {void Function(double)? onProgress}) async {
    try {
      final r = await _api.dio.put<Map<String, dynamic>>(
        '/me/avatar',
        data: FormData.fromMap({
          'file': MultipartFile.fromBytes(bytes, filename: 'avatar.jpg', contentType: DioMediaType.parse('image/jpeg')),
        }),
        onSendProgress: (s, t) => onProgress?.call(t <= 0 ? 0 : s / t),
      );
      return r.data?['avatar_url'] as String?;
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<void> remove() => _api.delete<dynamic>('/me/avatar');
}

/// Shrinks a picked photo before upload (the server makes the final 512 px square).
Future<Uint8List> shrinkForAvatar(Uint8List raw) =>
    FlutterImageCompress.compressWithList(raw, minWidth: 1080, minHeight: 1080, quality: 85);

/// Your own avatar on the profile: tap to take / choose / remove a photo.
class ProfilePhotoButton extends ConsumerStatefulWidget {
  const ProfilePhotoButton({super.key, required this.name, required this.url});

  final String name;
  final String? url;

  @override
  ConsumerState<ProfilePhotoButton> createState() => _ProfilePhotoButtonState();
}

class _ProfilePhotoButtonState extends ConsumerState<ProfilePhotoButton> {
  double? _progress;

  void _refreshEverywhere() {
    final me = ref.read(authControllerProvider).value?.user.username;
    ref.invalidate(meProvider);
    if (me != null) ref.invalidate(profileProvider(me));
    ref.read(postsVersionProvider.notifier).bump(); // post cards show the new face
  }

  Future<void> _pick(ImageSource source) async {
    final me = await ref.read(meProvider.future).catchError((_) => null);
    if (!mounted) return;
    if (me != null && me.needsVerification) {
      await showVerifyEmailSheet(context);
      return;
    }
    final x = await ImagePicker().pickImage(source: source, preferredCameraDevice: CameraDevice.front);
    if (x == null) return;
    setState(() => _progress = 0);
    try {
      final bytes = await shrinkForAvatar(await x.readAsBytes());
      await ref
          .read(profilePhotoApiProvider)
          .upload(
            bytes,
            onProgress: (p) {
              if (mounted) setState(() => _progress = p);
            },
          );
      HapticFeedback.mediumImpact();
      _refreshEverywhere();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile photo updated')));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  Future<void> _remove() async {
    try {
      await ref.read(profilePhotoApiProvider).remove();
      _refreshEverywhere();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _menu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Profile photo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(c, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(c, 'camera'),
            ),
            if (widget.url != null)
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: Theme.of(c).colorScheme.error),
                title: Text('Remove photo', style: TextStyle(color: Theme.of(c).colorScheme.error)),
                onTap: () => Navigator.pop(c, 'remove'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    switch (choice) {
      case 'gallery':
        await _pick(ImageSource.gallery);
      case 'camera':
        await _pick(ImageSource.camera);
      case 'remove':
        await _remove();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final busy = _progress != null;
    return Semantics(
      button: true,
      label: 'Change profile photo',
      child: GestureDetector(
        onTap: busy ? null : _menu,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Avatar(name: widget.name, url: widget.url, radius: 38),
            if (busy)
              Positioned.fill(
                child: CircularProgressIndicator(value: _progress == 0 ? null : _progress, strokeWidth: 3),
              ),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.surface, width: 2),
                ),
                child: Icon(Icons.photo_camera_rounded, size: 14, color: cs.onPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
