import 'package:flutter/foundation.dart';

class SelectionNotifier {
  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  static void notify() {
    version.value++;
  }
}
