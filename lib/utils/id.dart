import 'package:uuid/uuid.dart';
final Uuid _uuid = const Uuid();

String generateId() => _uuid.v4(); // UUID v4 عشوائي
