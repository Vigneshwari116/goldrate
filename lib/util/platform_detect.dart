import 'package:flutter/foundation.dart';

bool get isMobileNative =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;
