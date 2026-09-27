import 'package:flutter/material.dart';

import '../api/api_reachability.dart';
import '../theme/app_theme.dart';

/// Small banner showing Online vs Offline — Local Database.
class ConnectivityBanner extends StatelessWidget {
  const ConnectivityBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ApiReachability.instance.isOnline,
      builder: (context, online, _) {
        final label = online ? 'Online' : 'Offline — Local Database';
        final bg = online ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0);
        final fg = online ? const Color(0xFF2E7D32) : AppColors.navy;
        return Material(
          color: bg,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Icon(
                    online ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                    size: 16,
                    color: fg,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
