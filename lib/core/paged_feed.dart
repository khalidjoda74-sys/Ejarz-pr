import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

/// One bounded live query; older pages are fetched only on explicit demand.
/// Updates entering the live window replace cached rows by ID, never duplicate them.
class PagedFeed {
  static const pageSize = 20;
  final Query<Map<String, dynamic>> query;
  final void Function(List<QueryDocumentSnapshot<Map<String, dynamic>>>) onData;
  final void Function(Object) onError;
  final void Function() onState;
  final _rows = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  QueryDocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool loading = false, hasMore = true, _closed = false, _paged = false;
  PagedFeed(
      {required this.query,
      required this.onData,
      required this.onError,
      required this.onState});

  void start() {
    _subscription = query
        .limit(pageSize)
        .snapshots(includeMetadataChanges: true)
        .listen((snapshot) {
      if (_closed) return;
      for (final row in snapshot.docs) {
        _rows[row.id] = row;
      }
      if (!_paged && !snapshot.metadata.isFromCache) {
        _cursor = snapshot.docs.lastOrNull;
        hasMore = snapshot.docs.length == pageSize;
      }
      onData(_rows.values.toList());
    }, onError: (Object error) {
      if (!_closed) onError(error);
    });
  }

  Future<void> loadMore() async {
    if (_closed || loading || !hasMore) return;
    loading = true;
    onState();
    try {
      var next = query;
      if (_cursor != null) next = next.startAfterDocument(_cursor!);
      final snapshot = await next
          .limit(pageSize)
          .get(const GetOptions(source: Source.server));
      if (_closed) return;
      _paged = true;
      for (final row in snapshot.docs) {
        _rows[row.id] = row;
      }
      if (snapshot.docs.isNotEmpty) _cursor = snapshot.docs.last;
      hasMore = snapshot.docs.length == pageSize;
      onData(_rows.values.toList());
    } catch (error) {
      if (!_closed) onError(error);
    } finally {
      loading = false;
      if (!_closed) onState();
    }
  }

  void dispose() {
    _closed = true;
    _subscription?.cancel();
    _rows.clear();
  }
}
