import 'package:flutter/material.dart';

import '../navigation/app_page.dart';
import '../util/session_prefs.dart';
import 'app_shell.dart';
import 'login_screen.dart';

/// Restores the last session on launch instead of always showing login.
class BootstrapScreen extends StatefulWidget {
  const BootstrapScreen({super.key});

  @override
  State<BootstrapScreen> createState() => _BootstrapScreenState();
}

class _BootstrapScreenState extends State<BootstrapScreen> {
  late final Future<_BootstrapData> _boot;

  @override
  void initState() {
    super.initState();
    _boot = _load();
  }

  Future<_BootstrapData> _load() async {
    final loggedIn = await SessionPrefs.isLoggedIn();
    if (!loggedIn) return _BootstrapData(loggedIn: false);
    final page = await SessionPrefs.getLastPage();
    return _BootstrapData(loggedIn: true, lastPage: page);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_BootstrapData>(
      future: _boot,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final data = snapshot.data!;
        if (data.loggedIn) {
          return AppShell(initialPage: data.lastPage ?? AppPage.home);
        }
        return const LoginScreen();
      },
    );
  }
}

class _BootstrapData {
  const _BootstrapData({required this.loggedIn, this.lastPage});

  final bool loggedIn;
  final AppPage? lastPage;
}
