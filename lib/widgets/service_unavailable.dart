import 'package:flutter/material.dart';
import '../core/runtime_config.dart';
import 'common.dart';
class ServiceUnavailable extends StatelessWidget {
  final String title;
  const ServiceUnavailable({super.key, this.title = 'الخدمة غير متاحة حاليًا'});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(child: Padding(padding: const EdgeInsets.all(24),
      child: InfoBanner(text: AppRuntime.config['maintenanceMode'] == true ? AppRuntime.text('maintenanceMessage', 'التطبيق تحت الصيانة مؤقتًا.') : 'هذه الخدمة متوقفة مؤقتًا. يمكنك العودة لاحقًا.', icon: Icons.hourglass_empty))),
  );
}
