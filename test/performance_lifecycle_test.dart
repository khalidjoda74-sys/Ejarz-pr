import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:majalisna/core/navigation/app_page_route.dart';
import 'package:majalisna/core/navigation/app_route_observer.dart';
import 'package:majalisna/core/utils/reference_counted_watch_registry.dart';
import 'package:majalisna/core/widgets/tab_activity_scope.dart';
import 'package:majalisna/navigation/main_shell.dart';

void main() {
  testWidgets('main shell creates tabs lazily and preserves visited state',
      (tester) async {
    final initCounts = List<int>.filled(5, 0);
    final buildCounts = List<int>.filled(5, 0);
    final builders = List<WidgetBuilder>.generate(
      5,
      (index) => (_) => _ProbeTab(
            index: index,
            onInit: () => initCounts[index]++,
            onBuild: () => buildCounts[index]++,
          ),
    );

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [appPageRouteObserver],
        home: MainShell(debugTabBuilders: builders),
      ),
    );

    expect(initCounts, <int>[1, 0, 0, 0, 0]);
    expect(buildCounts, <int>[1, 0, 0, 0, 0]);
    await tester.tap(find.byKey(const ValueKey('probe_increment_0')));
    await tester.pump();
    expect(find.text('tab 0 value 1'), findsOneWidget);
    expect(buildCounts, <int>[2, 0, 0, 0, 0]);

    await tester.tap(find.byKey(const ValueKey('bottom_nav_1')));
    await tester.pumpAndSettle();
    expect(initCounts, <int>[1, 1, 0, 0, 0]);
    expect(buildCounts, <int>[2, 1, 0, 0, 0]);

    await tester.tap(find.byKey(const ValueKey('bottom_nav_0')));
    await tester.pumpAndSettle();
    expect(initCounts, <int>[1, 1, 0, 0, 0]);
    expect(buildCounts, <int>[2, 1, 0, 0, 0]);
    expect(find.text('tab 0 value 1'), findsOneWidget);
  });

  testWidgets('covered shell deactivates its current tab until route returns',
      (tester) async {
    final activityChanges = <bool>[];
    final selectionChanges = <bool>[];
    final builders = List<WidgetBuilder>.generate(
      5,
      (index) => (_) => _ProbeTab(
            index: index,
            onInit: () {},
            onBuild: () {},
            onActivity: activityChanges.add,
            onSelection: selectionChanges.add,
          ),
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [appPageRouteObserver],
        home: MainShell(debugTabBuilders: builders),
      ),
    );
    expect(activityChanges.last, isTrue);
    expect(selectionChanges.last, isTrue);

    final navigator = Navigator.of(tester.element(find.byType(MainShell)));
    final route = AppPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('subpage')),
    );
    final routeFuture = navigator.push<void>(route);
    await tester.pump();
    await tester.pump(route.transitionDuration);
    expect(find.text('subpage'), findsOneWidget);
    expect(find.byKey(const ValueKey('probe_increment_0')), findsNothing);
    expect(activityChanges.last, isFalse);
    expect(selectionChanges.last, isTrue);
    expect(route.transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, Duration.zero);
    expect(route.allowSnapshotting, isFalse);

    navigator.pop();
    await tester.pump();
    await tester.pump(route.reverseTransitionDuration);
    await routeFuture;
    expect(find.text('subpage'), findsNothing);
    expect(find.byKey(const ValueKey('probe_increment_0')), findsOneWidget);
    expect(activityChanges.last, isTrue);
    expect(selectionChanges.last, isTrue);
  });

  testWidgets('dialog keeps the current page active', (tester) async {
    final activityChanges = <bool>[];
    final builders = List<WidgetBuilder>.generate(
      5,
      (index) => (_) => _ProbeTab(
            index: index,
            onInit: () {},
            onBuild: () {},
            onActivity: activityChanges.add,
          ),
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [appPageRouteObserver],
        home: MainShell(debugTabBuilders: builders),
      ),
    );

    final shellContext = tester.element(find.byType(MainShell));
    final dialogFuture = showDialog<void>(
      context: shellContext,
      builder: (_) => const AlertDialog(content: Text('dialog')),
    );
    await tester.pumpAndSettle();
    expect(activityChanges.last, isTrue);

    Navigator.of(tester.element(find.text('dialog'))).pop();
    await tester.pumpAndSettle();
    await dialogFuture;
    expect(activityChanges.last, isTrue);
  });

  test('comment watch references return to zero after repeated navigation', () {
    final registry = ReferenceCountedWatchRegistry<String>();

    for (var cycle = 0; cycle < 20; cycle++) {
      expect(registry.acquire('council-$cycle'), isTrue);
      expect(registry.activeReferenceCount, 1);
      expect(registry.release('council-$cycle'), isTrue);
      expect(registry.activeReferenceCount, 0);
      expect(registry.activeKeyCount, 0);
    }
  });

  test('shared comment watches close only after the final viewer leaves', () {
    final registry = ReferenceCountedWatchRegistry<String>();

    expect(registry.acquire('council'), isTrue);
    expect(registry.acquire('council'), isFalse);
    expect(registry.activeReferenceCount, 2);
    expect(registry.release('council'), isFalse);
    expect(registry.activeReferenceCount, 1);
    expect(registry.release('council'), isTrue);
    expect(registry.activeReferenceCount, 0);
  });
}

class _ProbeTab extends StatefulWidget {
  const _ProbeTab({
    required this.index,
    required this.onInit,
    required this.onBuild,
    this.onActivity,
    this.onSelection,
  });

  final int index;
  final VoidCallback onInit;
  final VoidCallback onBuild;
  final ValueChanged<bool>? onActivity;
  final ValueChanged<bool>? onSelection;

  @override
  State<_ProbeTab> createState() => _ProbeTabState();
}

class _ProbeTabState extends State<_ProbeTab> {
  int _value = 0;

  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) {
    widget.onBuild();
    widget.onActivity?.call(TabActivityScope.isActiveOf(context));
    widget.onSelection?.call(TabActivityScope.isSelectedOf(context));
    return Center(
      child: TextButton(
        key: ValueKey('probe_increment_${widget.index}'),
        onPressed: () => setState(() => _value++),
        child: Text('tab ${widget.index} value $_value'),
      ),
    );
  }
}
