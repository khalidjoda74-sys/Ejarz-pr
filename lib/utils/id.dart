import 'package:uuid/uuid.dart';

const Uuid _uuid = Uuid();

String generateId() => _uuid.v4(); // UUID v4 عشوائي
