import 'package:app_core/app_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'src/data/demo_backend.dart';
import 'src/ui/app.dart';

const productId = 'tsuzuri';
const productDisplayName = 'つづり';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // SQLite is not available on the web preview; the web build keeps data in
    // memory for the session only and says so in the demo banner.
    final LocalStore store = kIsWeb ? MemoryLocalStore() : await SqliteLocalStore.open();
    final backend = DemoBackend(store);
    await backend.load();
    runApp(TsuzuriApp(backend: backend));
  } catch (_) {
    // Do not silently switch to volatile storage and report a successful startup.
    runApp(const MaterialApp(
      home: Scaffold(body: Center(child: Text('データを開けませんでした。アプリを再起動してください。'))),
    ));
  }
}
