// Test doubles for SDK interfaces only.
// ignore_for_file: subtype_of_sealed_class
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aqdak/core/paged_feed.dart';

class RowDoc extends Fake implements QueryDocumentSnapshot<Map<String,dynamic>> {
  @override final String id;
  RowDoc(this.id);
  @override Map<String,dynamic> data()=>{'id':id};
}
class Meta extends Fake implements SnapshotMetadata { @override bool get isFromCache=>false; }
class Snap extends Fake implements QuerySnapshot<Map<String,dynamic>> {
  @override final List<QueryDocumentSnapshot<Map<String,dynamic>>> docs;
  Snap(this.docs);
  @override SnapshotMetadata get metadata=>Meta();
}
class Source {
  final docs=List.generate(45,(i)=>RowDoc('$i'));
  final changes=StreamController<QuerySnapshot<Map<String,dynamic>>>.broadcast();
  int reads=0;
  bool fail=false;
}
class FakeQuery extends Fake implements Query<Map<String,dynamic>> {
  final Source source;final int offset,pageLength;
  FakeQuery(this.source,{this.offset=0,this.pageLength=99999});
  @override Query<Map<String,dynamic>> limit(int limit)=>FakeQuery(source,offset:offset,pageLength:limit);
  @override Query<Map<String,dynamic>> startAfterDocument(DocumentSnapshot snapshot)=>FakeQuery(source,offset:int.parse(snapshot.id)+1,pageLength:pageLength);
  @override Stream<QuerySnapshot<Map<String,dynamic>>> snapshots({bool includeMetadataChanges=false,ListenSource source=ListenSource.defaultSource})=>this.source.changes.stream;
  @override Future<QuerySnapshot<Map<String,dynamic>>> get([GetOptions? options])async {source.reads++;if(source.fail)throw StateError('offline');return Snap(source.docs.skip(offset).take(pageLength).toList());}
}
void main(){
 test('45 records are loaded in explicit 20-row pages without duplicate reads or rows',()async{
  final source=Source();var rows=<QueryDocumentSnapshot<Map<String,dynamic>>>[];
  final feed=PagedFeed(query:FakeQuery(source),onData:(v)=>rows=v,onError:(e)=>fail('$e'),onState:(){});
  feed.start();source.changes.add(Snap(source.docs.take(20).toList()));await Future<void>.delayed(Duration.zero);
  expect(rows.length,20);expect(source.reads,0);
  await Future.wait([feed.loadMore(),feed.loadMore()]);expect(source.reads,1);expect(rows.length,40);
  await feed.loadMore();expect(rows.length,45);expect(rows.map((r)=>r.id).toSet().length,45);expect(feed.hasMore,false);
  await feed.loadMore();expect(source.reads,2);
  source.changes.add(Snap(source.docs.take(20).toList()));await Future<void>.delayed(Duration.zero);expect(rows.length,45);
  feed.dispose();expect(source.changes.hasListener,false);await source.changes.close();
 });
 test('failed page preserves cached records and cursor; disposed feed ignores callbacks',()async{
  final source=Source();var count=0,errors=0;
  final feed=PagedFeed(query:FakeQuery(source),onData:(v)=>count=v.length,onError:(_)=>errors++,onState:(){});
  feed.start();source.changes.add(Snap(source.docs.take(20).toList()));await Future<void>.delayed(Duration.zero);
  source.fail=true;await feed.loadMore();expect(count,20);expect(errors,1);expect(feed.hasMore,true);
  source.fail=false;await feed.loadMore();expect(count,40);
  feed.dispose();source.changes.add(Snap([]));await Future<void>.delayed(Duration.zero);expect(count,40);await source.changes.close();
 });
}
