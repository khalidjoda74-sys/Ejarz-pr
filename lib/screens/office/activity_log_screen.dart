import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'dart:ui' as ui;

import 'package:darvoo/data/models/activity_log.dart';
import 'package:darvoo/data/services/user_scope.dart' as scope;

class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  static const Color _primary = Color(0xFF0F766E);

  final TextEditingController _searchCtrl = TextEditingController();

  bool _accessLoading = true;
  bool _canViewAll = false;
  bool _onlyMine = false;

  String _selectedAction = 'all';
  String _selectedEntity = 'all';
  String _selectedUser = 'all';
  String _quickDate = 'all';

  DateTime? _fromDate;
  DateTime? _toDate;

  String get _currentUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  String get _workspaceUid {
    final scoped = scope.effectiveUid().trim();
    if (scoped.isNotEmpty && scoped != 'guest') return scoped;
    return _currentUid;
  }

  CollectionReference<Map<String, dynamic>>? get _logsRef {
    final uid = _workspaceUid;
    if (uid.isEmpty) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('activity_logs');
  }

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
    _resolveAccess();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _resolveAccess() async {
    final currentUid = _currentUid;
    final workspaceUid = _workspaceUid;
    var canViewAll = currentUid.isNotEmpty && currentUid == workspaceUid;

    if (!canViewAll && currentUid.isNotEmpty) {
      try {
        final claims =
            (await FirebaseAuth.instance.currentUser?.getIdTokenResult(true))
                    ?.claims ??
                const <String, dynamic>{};
        final role = (claims['role'] ?? '').toString();
        final officePermission =
            (claims['officePermission'] ?? claims['permission'] ?? '')
                .toString();
        if (role == 'admin' ||
            role == 'owner' ||
            role == 'office' ||
            officePermission == 'full') {
          canViewAll = true;
        }
      } catch (_) {}
    }

    if (!canViewAll && currentUid.isNotEmpty) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUid)
            .get();
        final data = doc.data() ?? const <String, dynamic>{};
        final role = (data['role'] ?? '').toString();
        final officePermission =
            (data['officePermission'] ?? data['permission'] ?? '').toString();
        if (role == 'admin' ||
            role == 'owner' ||
            role == 'office' ||
            officePermission == 'full') {
          canViewAll = true;
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _canViewAll = canViewAll;
      _onlyMine = !canViewAll;
      _accessLoading = false;
    });
  }

  bool _matchesDate(ActivityLogEntry entry) {
    final dt = entry.occurredAt.toLocal();
    final now = DateTime.now();

    if (_quickDate == 'today') {
      return dt.year == now.year && dt.month == now.month && dt.day == now.day;
    }

    if (_quickDate == 'week') {
      final start = now.subtract(Duration(days: now.weekday - 1));
      final startOnly = DateTime(start.year, start.month, start.day);
      final endOnly = DateTime(now.year, now.month, now.day, 23, 59, 59);
      return !dt.isBefore(startOnly) && !dt.isAfter(endOnly);
    }

    if (_quickDate == 'month') {
      return dt.year == now.year && dt.month == now.month;
    }

    if (_fromDate != null) {
      final from = DateTime(_fromDate!.year, _fromDate!.month, _fromDate!.day);
      if (dt.isBefore(from)) return false;
    }
    if (_toDate != null) {
      final to =
          DateTime(_toDate!.year, _toDate!.month, _toDate!.day, 23, 59, 59);
      if (dt.isAfter(to)) return false;
    }

    return true;
  }

  List<ActivityLogEntry> _applyFilters(List<ActivityLogEntry> source) {
    final query = _searchCtrl.text.trim().toLowerCase();
    return source.where((e) {
      if ((_onlyMine || !_canViewAll) && e.actorUid != _currentUid) {
        return false;
      }
      if (_selectedUser != 'all' && e.actorUid != _selectedUser) {
        return false;
      }
      if (_selectedAction != 'all' && e.actionType != _selectedAction) {
        return false;
      }
      if (_selectedEntity != 'all' && e.entityType != _selectedEntity) {
        return false;
      }
      if (!_matchesDate(e)) {
        return false;
      }
      if (query.isEmpty) return true;

      final hay = <String>[
        e.actorName,
        e.actorEmail,
        _labelForAction(e.actionType),
        _labelForEntity(e.entityType),
        e.entityName,
        e.entityId,
        e.description,
      ].join(' ').toLowerCase();

      return hay.contains(query);
    }).toList(growable: false);
  }

  String _labelForAction(String raw) {
    switch (raw) {
      case 'create':
        return 'إضافة';
      case 'update':
        return 'تعديل';
      case 'delete':
        return 'حذف';
      case 'archive':
        return 'أرشفة';
      case 'unarchive':
        return 'فك الأرشفة';
      case 'terminate':
        return 'إنهاء';
      case 'status_change':
        return 'تغيير حالة';
      case 'login':
        return 'تسجيل دخول';
      case 'logout':
        return 'تسجيل خروج';
      case 'payment_add':
        return 'إضافة دفعة';
      case 'payment_update':
        return 'تعديل دفعة';
      case 'payment_delete':
        return 'حذف دفعة';
      case 'password_reset_link':
        return 'توليد رابط كلمة المرور';
      default:
        return raw;
    }
  }

  String _labelForEntity(String raw) {
    switch (raw) {
      case 'property':
        return 'عقار';
      case 'tenant':
        return 'مستأجر';
      case 'contract':
        return 'عقد';
      case 'invoice':
        return 'دفعة/فاتورة';
      case 'maintenance':
        return 'صيانة';
      case 'office_user':
        return 'مستخدم مكتب';
      case 'auth':
        return 'الحساب';
      default:
        return raw;
    }
  }

  String _fmtDateTime(DateTime dt) {
    return DateFormat('yyyy/MM/dd - HH:mm', 'ar').format(dt.toLocal());
  }

  Future<void> _pickDate({required bool from}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDate: from ? (_fromDate ?? now) : (_toDate ?? _fromDate ?? now),
      helpText: from ? 'من تاريخ' : 'إلى تاريخ',
    );
    if (picked == null) return;
    setState(() {
      if (from) {
        _fromDate = picked;
      } else {
        _toDate = picked;
      }
      _quickDate = 'all';
    });
  }

  Widget _buildFilterBar(List<ActivityLogEntry> entries) {
    final users = <String, String>{};
    final actions = <String>{};
    final entities = <String>{};

    for (final e in entries) {
      actions.add(e.actionType);
      entities.add(e.entityType);
      if (e.actorUid.isNotEmpty) {
        users[e.actorUid] = e.actorName.isNotEmpty ? e.actorName : e.actorUid;
      }
    }

    final dropdownTextStyle = GoogleFonts.cairo(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: const Color(0xFF0F172A),
    );
    final actionItems = actions.toList()..sort();
    final entityItems = entities.toList()..sort();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedAction,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'العملية',
                    border: OutlineInputBorder(),
                  ),
                  style: dropdownTextStyle,
                  items: <DropdownMenuItem<String>>[
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('كل العمليات'),
                    ),
                    ...actionItems.map(
                      (v) => DropdownMenuItem(
                        value: v,
                        child: Text(_labelForAction(v)),
                      ),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => _selectedAction = v ?? 'all'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedEntity,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'العنصر',
                    border: OutlineInputBorder(),
                  ),
                  style: dropdownTextStyle,
                  items: <DropdownMenuItem<String>>[
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('كل العناصر'),
                    ),
                    ...entityItems.map(
                      (v) => DropdownMenuItem(
                        value: v,
                        child: Text(_labelForEntity(v)),
                      ),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => _selectedEntity = v ?? 'all'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedUser,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'المستخدم',
                    border: OutlineInputBorder(),
                  ),
                  style: dropdownTextStyle,
                  items: <DropdownMenuItem<String>>[
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('كل المستخدمين'),
                    ),
                    ...users.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                  ],
                  onChanged: _canViewAll
                      ? (v) => setState(() => _selectedUser = v ?? 'all')
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _quickDate,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'التاريخ',
                    border: OutlineInputBorder(),
                  ),
                  style: dropdownTextStyle,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('الكل')),
                    DropdownMenuItem(value: 'today', child: Text('اليوم')),
                    DropdownMenuItem(value: 'week', child: Text('هذا الأسبوع')),
                    DropdownMenuItem(value: 'month', child: Text('هذا الشهر')),
                  ],
                  onChanged: (v) => setState(() => _quickDate = v ?? 'all'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickDate(from: true),
                  icon: const Icon(Icons.date_range_rounded, size: 18),
                  label: Text(
                    _fromDate == null
                        ? 'من تاريخ'
                        : DateFormat('yyyy/MM/dd', 'ar').format(_fromDate!),
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickDate(from: false),
                  icon: const Icon(Icons.event_rounded, size: 18),
                  label: Text(
                    _toDate == null
                        ? 'إلى تاريخ'
                        : DateFormat('yyyy/MM/dd', 'ar').format(_toDate!),
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
          if (_canViewAll)
            SwitchListTile.adaptive(
              value: _onlyMine,
              onChanged: (v) => setState(() => _onlyMine = v),
              dense: true,
              title: Text(
                'نشاطي فقط',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
              ),
              contentPadding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }

  void _openDetails(ActivityLogEntry e) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        final changed = e.changedFields;
        return Directionality(
          textDirection: ui.TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'تفاصيل العملية',
                    style: GoogleFonts.cairo(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _detailLine('المستخدم', e.actorName),
                  _detailLine(
                      'الإيميل', e.actorEmail.isEmpty ? '-' : e.actorEmail),
                  _detailLine('الدور', e.actorRole.isEmpty ? '-' : e.actorRole),
                  _detailLine('العملية', _labelForAction(e.actionType)),
                  _detailLine('نوع العنصر', _labelForEntity(e.entityType)),
                  _detailLine(
                      'اسم العنصر', e.entityName.isEmpty ? '-' : e.entityName),
                  _detailLine(
                      'معرف العنصر', e.entityId.isEmpty ? '-' : e.entityId),
                  _detailLine('التاريخ والوقت', _fmtDateTime(e.occurredAt)),
                  const SizedBox(height: 8),
                  Text(
                    e.description,
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF334155),
                      height: 1.5,
                    ),
                  ),
                  if (changed.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      'الحقول التي تغيرت',
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...changed.map((field) {
                      final c = (e.changes[field] is Map)
                          ? Map<String, dynamic>.from(e.changes[field] as Map)
                          : const <String, dynamic>{};
                      final oldV = c['old'];
                      final newV = c['new'];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              field,
                              style: GoogleFonts.cairo(
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'قبل: ${oldV ?? '-'}',
                              style: GoogleFonts.cairo(
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFFB91C1C),
                              ),
                            ),
                            Text(
                              'بعد: ${newV ?? '-'}',
                              style: GoogleFonts.cairo(
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF166534),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _detailLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.cairo(
            color: const Color(0xFF334155),
            fontWeight: FontWeight.w700,
          ),
          children: [
            TextSpan(text: '$label: '),
            TextSpan(
              text: value,
              style: GoogleFonts.cairo(
                color: const Color(0xFF0F172A),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ref = _logsRef;

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF0F172A),
          elevation: 0.5,
          iconTheme: const IconThemeData(color: _primary),
          title: Text(
            'سجل النشاط',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w800),
          ),
        ),
        body: _accessLoading
            ? const Center(child: CircularProgressIndicator())
            : ref == null
                ? Center(
                    child: Text(
                      'تعذر تحديد حساب المكتب.',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
                    ),
                  )
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                        child: TextField(
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            hintText:
                                'بحث باسم المستخدم أو العملية أو العنصر...',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _searchCtrl.text.isNotEmpty
                                ? IconButton(
                                    onPressed: _searchCtrl.clear,
                                    icon: const Icon(Icons.close_rounded),
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                        ),
                      ),
                      Expanded(
                        child:
                            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: ref
                              .orderBy('occurredAt', descending: true)
                              .limit(500)
                              .snapshots(),
                          builder: (context, snap) {
                            if (snap.hasError) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    'تعذر قراءة سجل النشاط: ${snap.error}',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.cairo(
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFFB91C1C),
                                    ),
                                  ),
                                ),
                              );
                            }
                            if (snap.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                  child: CircularProgressIndicator());
                            }

                            final all = (snap.data?.docs ?? const [])
                                .map((d) => ActivityLogEntry.fromFirestore(
                                    d.id, d.data()))
                                .toList(growable: false);

                            final filtered = _applyFilters(all);

                            return Column(
                              children: [
                                _buildFilterBar(all),
                                Expanded(
                                  child: filtered.isEmpty
                                      ? Center(
                                          child: Text(
                                            'لا يوجد نشاط مطابق للفلاتر.',
                                            style: GoogleFonts.cairo(
                                              fontWeight: FontWeight.w700,
                                              color: const Color(0xFF475569),
                                            ),
                                          ),
                                        )
                                      : ListView.separated(
                                          padding: const EdgeInsets.fromLTRB(
                                              12, 0, 12, 12),
                                          itemCount: filtered.length,
                                          separatorBuilder: (_, __) =>
                                              const SizedBox(height: 8),
                                          itemBuilder: (ctx, i) {
                                            final e = filtered[i];
                                            return InkWell(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              onTap: () => _openDetails(e),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.all(12),
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  border: Border.all(
                                                    color:
                                                        const Color(0xFFE2E8F0),
                                                  ),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                            horizontal: 8,
                                                            vertical: 4,
                                                          ),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: const Color(
                                                                0xFFEFF4FF),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        20),
                                                          ),
                                                          child: Text(
                                                            _labelForAction(
                                                                e.actionType),
                                                            style: GoogleFonts
                                                                .cairo(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800,
                                                              color: _primary,
                                                              fontSize: 11,
                                                            ),
                                                          ),
                                                        ),
                                                        const Spacer(),
                                                        Text(
                                                          _fmtDateTime(
                                                              e.occurredAt),
                                                          style:
                                                              GoogleFonts.cairo(
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: const Color(
                                                                0xFF64748B),
                                                            fontSize: 11,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      e.description,
                                                      style: GoogleFonts.cairo(
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color: const Color(
                                                            0xFF0F172A),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'بواسطة: ${e.actorName} • ${_labelForEntity(e.entityType)}',
                                                      style: GoogleFonts.cairo(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: const Color(
                                                            0xFF475569),
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
