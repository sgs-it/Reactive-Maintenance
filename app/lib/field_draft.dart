import 'package:hive_flutter/hive_flutter.dart';

/// Only opened by a signed-in user's action or photo form.
class FieldDraft {
  FieldDraft(this.key);
  final String key;
  static Future<LazyBox<dynamic>>? _opening;

  static Future<LazyBox<dynamic>> _open() async {
    await Hive.initFlutter();
    return Hive.openLazyBox('rmcs_field_drafts');
  }

  Future<LazyBox<dynamic>> get box async {
    try {
      return await (_opening ??= _open());
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  static String prefix(String origin, String user) => '$origin|$user|';
  static Future<List<String>> pending(String prefix) async {
    final box = await FieldDraft('').box;
    return box.keys
        .whereType<String>()
        .where((key) => key.startsWith(prefix))
        .map((key) => key.substring(prefix.length))
        .toList();
  }

  Future<Map?> read() async => (await (await box).get(key)) as Map?;
  Future<void> save(Map value) async => (await box).put(key, value);
  Future<void> remove() async => (await box).delete(key);
}
