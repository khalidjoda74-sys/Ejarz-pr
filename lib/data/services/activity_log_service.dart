class ActivityLogService {
  ActivityLogService._();
  static final ActivityLogService instance = ActivityLogService._();

  Future<void> logEntityAction({
    required String actionType,
    required String entityType,
    String? entityId,
    String? entityName,
    String? description,
    Map<String, dynamic>? oldData,
    Map<String, dynamic>? newData,
    Map<String, dynamic>? metadata,
    String? workspaceUidOverride,
  }) async {
    // Activity log is disabled by product request.
  }

  Future<void> logAuth({
    required String actionType,
    String? description,
  }) async {
    // Activity log is disabled by product request.
  }
}
