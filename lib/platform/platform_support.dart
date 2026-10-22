import 'package:flutter/foundation.dart';

bool get isIOSDevice => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
