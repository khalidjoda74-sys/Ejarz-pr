import 'package:flutter/material.dart';
import '../core/app_controller.dart';

class LoadMoreRecords extends StatelessWidget {
  final String collection;
  const LoadMoreRecords(this.collection, {super.key});
  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    if (!controller.hasMoreRecords(collection)) return const SizedBox.shrink();
    final busy = controller.loadingRecords(collection);
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(children: [
          if (controller.recordsError.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(controller.recordsError, textAlign: TextAlign.center),
            ),
          OutlinedButton.icon(
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.expand_more),
            label: Text(busy ? 'جارٍ تحميل المزيد…' : 'عرض المزيد — 20 سجلًا'),
            onPressed:
                busy ? null : () => controller.loadMoreRecords(collection),
          )
        ]));
  }
}
