import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/config/device_tz.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DeviceTimezone.init();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const ProviderScope(child: OutstagramApp()));
}
