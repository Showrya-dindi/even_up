import 'dart:io';
import 'package:flutter/foundation.dart';

class AppConfig {
  static const bool isLocal = true;

  static String get localBaseUrl {
    if (kIsWeb) return 'http://localhost:3000';
    // For physical devices, run: adb reverse tcp:3000 tcp:3000
    if (Platform.isAndroid) return 'http://localhost:3000';
    return 'http://localhost:3000';
  }

  static const String cloudBaseUrl =
      'https://your-api-gateway-url.amazonaws.com/prod';

  static String get baseUrl => isLocal ? localBaseUrl : cloudBaseUrl;
}
