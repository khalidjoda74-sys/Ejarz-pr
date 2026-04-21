import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../data/services/entity_audit_service.dart';
import '../../data/services/user_scope.dart' as scope;

class _AuditDialogData {
  final String addBy;
  final String addAt;
  final String editBy;
  final String editAt;

  const _AuditDialogData({
    required this.addBy,
    required this.addAt,
    required this.editBy,
    required this.editAt,
  });
}

class EntityAuditInfoButton extends StatelessWidget {
  final String collectionName;
  final String entityId;
  final bool preferLocalFirst;
  final Color color;
  final EdgeInsetsGeometry padding;
  final BoxConstraints? constraints;

  const EntityAuditInfoButton({
    super.key,
    required this.collectionName,
    required this.entityId,
    this.preferLocalFirst = false,
    this.color = Colors.white70,
    this.padding = EdgeInsets.zero,
    this.constraints,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: 'تفاصيل الإضافة والتعديل',
      iconSize: 16,
      splashRadius: 16,
      color: color,
      padding: padding,
      constraints: constraints,
      icon: const Icon(Icons.info_outline_rounded),
      onPressed: () => _showAuditDialog(context),
    );
  }

  Future<void> _showAuditDialog(BuildContext context) async {
    final workspaceUid = scope.effectiveUid().trim();
    debugPrint(
      '[AuditTrace][UI] open collection=$collectionName entityId=$entityId scopeUid=$workspaceUid authUid=${FirebaseAuth.instance.currentUser?.uid ?? ''}',
    );

    if (preferLocalFirst &&
        workspaceUid.isNotEmpty &&
        workspaceUid != 'guest') {
      try {
        final localInfo = await EntityAuditService.instance.loadLocalEntityAudit(
          workspaceUid: workspaceUid,
          collectionName: collectionName,
          entityId: entityId,
        );
        if (localInfo != null && context.mounted) {
          final derivedCreateAt = _deriveDateFromEntityId(entityId);
          final hasRealEdit = _hasRealEdit(localInfo, derivedCreateAt);
          await _showDialogCard(
            context,
            loader: SynchronousFuture(
              _AuditDialogData(
                addBy: _addByLabel(localInfo, workspaceUid),
                addAt: _fmt(localInfo.createdAt ?? derivedCreateAt),
                editBy:
                    hasRealEdit ? _editByLabel(localInfo, workspaceUid) : 'لا يوجد',
                editAt: hasRealEdit ? _fmt(localInfo.updatedAt) : 'لا يوجد',
              ),
            ),
          );
          return;
        }
      } catch (_) {}
    }

    await _showDialogCard(
      context,
      loader: _loadAuditDialogData(workspaceUid),
    );
  }

  Future<_AuditDialogData> _loadAuditDialogData(String workspaceUid) async {
    if (workspaceUid.isEmpty || workspaceUid == 'guest') {
      return const _AuditDialogData(
        addBy: 'غير متاح',
        addAt: 'غير متاح',
        editBy: 'غير متاح',
        editAt: 'غير متاح',
      );
    }

    EntityAuditInfo? info;
    try {
      info = await EntityAuditService.instance.loadEntityAudit(
        workspaceUid: workspaceUid,
        collectionName: collectionName,
        entityId: entityId,
      );
    } catch (_) {}

    if (info == null) {
      return const _AuditDialogData(
        addBy: 'لا يوجد',
        addAt: 'لا يوجد',
        editBy: 'لا يوجد',
        editAt: 'لا يوجد',
      );
    }

    final derivedCreateAt = _deriveDateFromEntityId(entityId);
    final hasRealEdit = _hasRealEdit(info, derivedCreateAt);

    return _AuditDialogData(
      addBy: _addByLabel(info, workspaceUid),
      addAt: _fmt(info.createdAt ?? derivedCreateAt),
      editBy: hasRealEdit ? _editByLabel(info!, workspaceUid) : 'لا يوجد',
      editAt: hasRealEdit ? _fmt(info.updatedAt) : 'لا يوجد',
    );
  }

  String _fmt(DateTime? d) {
    if (d == null) return 'غير متاح';
    return DateFormat('yyyy/MM/dd - HH:mm').format(d);
  }

  DateTime? _deriveDateFromEntityId(String id) {
    final n = int.tryParse(id.trim());
    if (n == null || n <= 0) return null;
    if (n >= 1000000000000000) {
      return DateTime.fromMicrosecondsSinceEpoch(n);
    }
    if (n >= 1000000000000) {
      return DateTime.fromMillisecondsSinceEpoch(n);
    }
    if (n >= 1000000000) {
      return DateTime.fromMillisecondsSinceEpoch(n * 1000);
    }
    return null;
  }

  String _addByLabel(EntityAuditInfo? info, String workspaceUid) {
    if (info == null) return 'الإدارة';
    final createdUid = info.createdByUid.trim();
    if (createdUid.isNotEmpty && createdUid == workspaceUid.trim()) {
      return 'الإدارة';
    }
    final name = info.createdByName.trim();
    if (name.isNotEmpty) return name;
    final email = info.createdByEmail.trim();
    if (email.isNotEmpty) return email;
    if (createdUid.isNotEmpty) return createdUid;
    return 'الإدارة';
  }

  String _editByLabel(EntityAuditInfo info, String workspaceUid) {
    final updatedUid = info.updatedByUid.trim();
    if (updatedUid.isNotEmpty && updatedUid == workspaceUid.trim()) {
      return 'الإدارة';
    }
    final name = info.updatedByName.trim();
    if (name.isNotEmpty) return name;
    final email = info.updatedByEmail.trim();
    if (email.isNotEmpty) return email;
    if (updatedUid.isNotEmpty) return updatedUid;
    return 'غير متاح';
  }

  bool _hasRealEdit(EntityAuditInfo? info, DateTime? derivedCreateAt) {
    if (info == null) return false;
    final updatedAt = info.updatedAt;
    if (updatedAt == null) return false;

    final createdAt = info.createdAt ?? derivedCreateAt;
    final sameUid = info.updatedByUid.trim().isNotEmpty &&
        info.updatedByUid.trim() == info.createdByUid.trim();
    final sameName = info.updatedByName.trim().isNotEmpty &&
        info.updatedByName.trim() == info.createdByName.trim();
    final sameActor = sameUid || sameName;

    if (createdAt != null) {
      final deltaMs =
          (updatedAt.millisecondsSinceEpoch - createdAt.millisecondsSinceEpoch)
              .abs();
      if (sameActor && deltaMs <= 1000) return false;
    }

    final hasUpdatedIdentity = info.updatedByUid.trim().isNotEmpty ||
        info.updatedByName.trim().isNotEmpty ||
        info.updatedByEmail.trim().isNotEmpty;
    return hasUpdatedIdentity;
  }

  Future<void> _showDialogCard(
    BuildContext context, {
    required Future<_AuditDialogData> loader,
  }) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Dialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 8,
            backgroundColor: Colors.white,
            child: FutureBuilder<_AuditDialogData>(
              future: loader,
              builder: (context, snapshot) {
                final isLoading =
                    snapshot.connectionState != ConnectionState.done &&
                        !snapshot.hasData;
                final data = snapshot.data;
                return Container(
                  constraints: const BoxConstraints(maxWidth: 400),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 20,
                        ),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(20),
                            topRight: Radius.circular(20),
                          ),
                          border: Border(
                            bottom: BorderSide(
                              color: Color(0xFFE2E8F0),
                              width: 1,
                            ),
                          ),
                        ),
                        child: Text(
                          'تفاصيل السجل',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.cairo(
                            color: const Color(0xFF1E293B),
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                        child: isLoading
                            ? Column(
                                children: [
                                  const SizedBox(
                                    width: 26,
                                    height: 26,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: Color(0xFF0F766E),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    'جارٍ تحميل تفاصيل السجل...',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.cairo(
                                      color: const Color(0xFF475569),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                children: [
                                  _infoTile(
                                    label: 'إضافة',
                                    value: data?.addBy ?? 'غير متاح',
                                  ),
                                  const SizedBox(height: 10),
                                  _infoTile(
                                    label: 'وقت الإضافة',
                                    value: data?.addAt ?? 'غير متاح',
                                  ),
                                  const SizedBox(height: 10),
                                  _infoTile(
                                    label: 'آخر تعديل',
                                    value: data?.editBy ?? 'غير متاح',
                                  ),
                                  const SizedBox(height: 10),
                                  _infoTile(
                                    label: 'وقت آخر تعديل',
                                    value: data?.editAt ?? 'غير متاح',
                                  ),
                                ],
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
                        child: Center(
                          child: SizedBox(
                            width: 170,
                            child: ElevatedButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0F766E),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                'إغلاق',
                                style: GoogleFonts.cairo(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _infoTile({required String label, required String value}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: GoogleFonts.cairo(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F172A),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.cairo(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF334155),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
