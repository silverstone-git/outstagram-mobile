import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Small platform facts and actions from `MainActivity.kt` (channel `outstagram/platform`).
const _platform = MethodChannel('outstagram/platform');

/// Build.VERSION.SDK_INT, read once at startup ([loadAndroidSdkInt]); null elsewhere or before then.
int? androidSdkInt;

Future<void> loadAndroidSdkInt() async {
  if (!Platform.isAndroid) return;
  try {
    androidSdkInt = await _platform.invokeMethod<int>('sdkInt');
  } catch (_) {}
}

/// Android 13 (API 33)+ confirms clipboard copies itself, so the app shouldn't add a snackbar too.
bool get systemConfirmsCopy => Platform.isAndroid && (androidSdkInt ?? 0) >= 33;

/// Writes [bytes] to the public Downloads folder (MediaStore). False where that would need a storage
/// permission (Android 9 and older) or off Android; throws if the save fails.
Future<bool> saveToDownloads(String name, List<int> bytes, String mime) async {
  if (!Platform.isAndroid) return false;
  final uri = await _platform.invokeMethod<String>(
    'saveToDownloads',
    {'name': name, 'mime': mime, 'bytes': Uint8List.fromList(bytes)},
  );
  return uri != null;
}
