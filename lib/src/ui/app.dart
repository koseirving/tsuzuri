import 'dart:async';

import 'package:flutter/material.dart';

import '../data/backend.dart';
import '../data/demo_backend.dart';
import 'onboarding.dart';
import 'read.dart';
import 'settings.dart';
import 'theme.dart';
import 'together.dart';
import 'write.dart';

class TsuzuriApp extends StatelessWidget {
  const TsuzuriApp({super.key, required this.backend, this.runDemoWorld = true});
  final TsuzuriBackend backend;

  /// Periodically lets the fictional writers answer. Off in widget tests.
  final bool runDemoWorld;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'つづり',
        debugShowCheckedModeBanner: false,
        theme: tsuzuriTheme(),
        home: ListenableBuilder(
          listenable: backend,
          builder: (context, _) {
            if (!backend.ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
            if (backend.me == null) return OnboardingPage(backend: backend);
            return HomeShell(backend: backend, runDemoWorld: runDemoWorld);
          },
        ),
      );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.backend, required this.runDemoWorld});
  final TsuzuriBackend backend;
  final bool runDemoWorld;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int tab = 0;
  Timer? _demo;

  DemoBackend? get _demoBackend {
    final b = widget.backend;
    return b is DemoBackend ? b : null;
  }

  @override
  void initState() {
    super.initState();
    final demo = _demoBackend;
    if (demo != null && widget.runDemoWorld) {
      _demo = Timer.periodic(const Duration(seconds: 2), (_) => demo.tickDemo().catchError((Object _) => false));
    }
  }

  @override
  void dispose() {
    _demo?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.backend;
    final hasNew = b.incomingLetters().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('つづり'),
        actions: [
          IconButton(
            tooltip: '設定',
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => SettingsPage(backend: b)),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(index: tab, children: [
          ReadTab(backend: b),
          WriteTab(backend: b),
          TogetherTab(backend: b, demoDelay: _demoBackend?.demoDelay),
        ]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.menu_book_outlined), label: '読む'),
          const NavigationDestination(icon: Icon(Icons.edit_outlined), label: '書く'),
          NavigationDestination(
            icon: Badge(isLabelVisible: hasNew, smallSize: 7, child: const Icon(Icons.people_outline)),
            label: 'ふたり',
          ),
        ],
      ),
    );
  }
}
