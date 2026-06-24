import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'court_repository.dart';

class CourtEditScreen extends ConsumerStatefulWidget {
  const CourtEditScreen({super.key, required this.court, required this.onSaved});

  final Court court;
  final void Function() onSaved;

  @override
  ConsumerState<CourtEditScreen> createState() => _CourtEditScreenState();
}

class _CourtEditScreenState extends ConsumerState<CourtEditScreen> {
  late final TextEditingController _nameCtl =
      TextEditingController(text: widget.court.name);
  late final TextEditingController _feeCtl = TextEditingController(
      text: (widget.court.entryFeeCents / 100).toStringAsFixed(0));
  late final TextEditingController _customFeeCtl = TextEditingController(
      text: widget.court.customFeeCents != null
          ? (widget.court.customFeeCents! / 100).toStringAsFixed(0)
          : '');
  late final TextEditingController _addressCtl =
      TextEditingController(text: widget.court.address ?? '');

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameCtl.dispose();
    _feeCtl.dispose();
    _customFeeCtl.dispose();
    _addressCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Court name is required');
      return;
    }
    final fee = parseAmountToMinor(_feeCtl.text) ?? 0;
    final rawCustomFee = parseAmountToMinor(_customFeeCtl.text);
    final customFeeCents =
        (rawCustomFee != null && rawCustomFee > 0) ? rawCustomFee : null;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(courtRepositoryProvider).updateCourt(
            courtId: widget.court.id,
            name: name,
            entryFeeCents: fee,
            address: _addressCtl.text.trim().isEmpty
                ? null
                : _addressCtl.text.trim(),
            customFeeCents: customFeeCents,
          );
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        widget.onSaved();
        messenger.showSnackBar(
          const SnackBar(content: Text('Court details saved.')),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currency = widget.court.currency;

    return Scaffold(
      appBar: AppBar(title: const Text('Edit court')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader('Venue', theme),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtl,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: 'Court name',
                prefixIcon: Icon(PhosphorIconsFill.buildings),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _addressCtl,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: 'Address (optional)',
                prefixIcon: Icon(PhosphorIconsFill.mapPin),
              ),
            ),
            _SectionHeader('Pricing', theme),
            const SizedBox(height: 12),
            TextField(
              controller: _feeCtl,
              enabled: !_busy,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Entry fee ($currency)',
                prefixIcon: Icon(PhosphorIconsFill.currencyDollar),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _customFeeCtl,
              enabled: !_busy,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Private booking rate ($currency/hr)',
                helperText:
                    'Enables "Book a Court" for players. Leave blank to disable.',
                prefixIcon: Icon(PhosphorIconsFill.lock),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(PhosphorIconsFill.warning, size: 16, color: scheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_error!,
                        style: TextStyle(color: scheme.error)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label, this.theme);
  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 0),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
