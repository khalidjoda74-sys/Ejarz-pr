/// Published, non-secret app settings. Defaults keep existing installations usable.
class AppRuntime {
  static Map<String, dynamic> config = {};
  static Map<String, dynamic> payments = {};
  static int get revision => (config['revision'] as num?)?.toInt() ?? 0;
  static bool service(String name) => (config['services'] as Map?)?[name] != false;
  static bool get assistantEnabled => config['assistantEnabled'] == true;
  static String text(String name, String fallback) {
    final value = config[name];
    return value is String && value.trim().isNotEmpty ? value.trim() : fallback;
  }
  static double price(String key, double fallback) {
    final value = (config['pricing'] as Map?)?[key];
    return value is num && value >= 0 ? value.toDouble() : fallback;
  }
  static bool attachment(String key, bool fallback) =>
      (config['attachments'] as Map?)?[key] as bool? ?? fallback;
  static List<Map<String, dynamic>> entries(String key) =>
      (config[key] is List ? config[key] as List : const [])
          .whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList();
}
