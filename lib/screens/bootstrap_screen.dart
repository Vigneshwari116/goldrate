import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../api/api_client.dart';
import '../navigation/app_page.dart';
import '../theme/app_theme.dart';
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
  late Future<_BootstrapData> _boot;

  @override
  void initState() {
    super.initState();
    _boot = _load();
  }

  void _retry() {
    setState(() {
      _boot = _load();
    });
  }

  Future<_BootstrapData> _load() async {
    if (ApiConfig.useRemoteApi) {
      final healthy = await ApiClient.checkHealth();
      if (!healthy) {
        return _BootstrapData(
          loggedIn: false,
          serverError: true,
        );
      }
    }

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
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return _InitErrorView(
            message: snapshot.error.toString(),
            onRetry: _retry,
          );
        }

        final data = snapshot.data ?? const _BootstrapData(loggedIn: false);
        if (data.serverError) {
          return _InitErrorView(
            message:
                'Cannot reach the server at ${ApiConfig.baseUrl}.\n'
                'Check mobile data/Wi‑Fi and that the VPS API is running.',
            onRetry: _retry,
          );
        }

        if (data.loggedIn) {
          return AppShell(initialPage: data.lastPage ?? AppPage.home);
        }
        return const LoginScreen();
      },
    );
  }
}

class _InitErrorView extends StatelessWidget {
  const _InitErrorView({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 56),
                const SizedBox(height: 16),
                const Text(
                  'Unable to initialize application',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: onRetry,
                    child: const Text('RETRY'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BootstrapData {
  const _BootstrapData({
    required this.loggedIn,
    this.lastPage,
    this.serverError = false,
  });

  final bool loggedIn;
  final AppPage? lastPage;
  final bool serverError;
}
