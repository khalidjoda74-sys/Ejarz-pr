import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/contract_calculation_engine.dart';

import '../core/theme.dart';

/// A bounded quantity, with accessible step buttons and direct numeric entry.
class UnitCountField extends StatefulWidget {
  final String label;
  final String value;
  final IconData icon;
  final ValueChanged<String> onChanged;
  final int maximum;

  const UnitCountField(
      {super.key,
      required this.label,
      required this.value,
      required this.icon,
      required this.onChanged,
      this.maximum = 50});

  @override
  State<UnitCountField> createState() => _UnitCountFieldState();
}

class _UnitCountFieldState extends State<UnitCountField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(UnitCountField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      final value = widget.value;
      final previousText = _controller.text;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            widget.value != value ||
            _controller.text != previousText) {
          return;
        }
        setState(() {
          _controller.value = TextEditingValue(
              text: value,
              selection: TextSelection.collapsed(offset: value.length));
        });
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _step(int delta) {
    final next = ((int.tryParse(_controller.text) ?? 0) + delta)
        .clamp(0, widget.maximum)
        .toString();
    _controller.text = next;
    widget.onChanged(next);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final number = int.tryParse(_controller.text) ?? 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: .22)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(widget.icon, color: AppColors.primary, size: 21),
          const SizedBox(width: 8),
          Expanded(
              child: Text(widget.label,
                  style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          IconButton.filledTonal(
            tooltip: 'زيادة ${widget.label}',
            onPressed: number < widget.maximum ? () => _step(1) : null,
            icon: const Icon(Icons.add_rounded),
          ),
          const SizedBox(width: 8),
          Expanded(
              child: TextFormField(
            controller: _controller,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: [
              TextInputFormatter.withFunction((oldValue, newValue) =>
                  newValue.copyWith(
                      text: ContractCalculationEngine.normalizeDigits(
                          newValue.text))),
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(2)
            ],
            decoration: InputDecoration(
                isDense: true,
                hintText: '0',
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12))),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            validator: (value) {
              final count = int.tryParse(value ?? '');
              return count == null || count < 0 || count > widget.maximum
                  ? 'من 0 إلى ${widget.maximum}'
                  : null;
            },
            onChanged: (value) {
              widget.onChanged(value);
              setState(() {});
            },
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          )),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'تقليل ${widget.label}',
            onPressed: number > 0 ? () => _step(-1) : null,
            icon: const Icon(Icons.remove_rounded),
          ),
        ]),
      ]),
    );
  }
}
