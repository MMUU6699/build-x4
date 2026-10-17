import 'package:flutter/foundation.dart';
import '../services/workspace/workspace_runtime.dart';

class ExternalMountItem {
  final String id;
  final String guestPath;
  const ExternalMountItem({required this.id, required this.guestPath});
}

class ExternalMountsProvider extends ChangeNotifier {
  Future<List<Mount>> resolveMounts() async => const [];
  ExternalMountItem? byId(String id) => null;
  Future<void> requireWritableHostPaths(Iterable<String> paths) async {}
}
