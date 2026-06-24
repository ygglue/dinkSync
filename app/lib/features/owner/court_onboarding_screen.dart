import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'court_repository.dart';

/// Step 1 of becoming a host: enter venue details. Creating the court does NOT
/// publish it — the subscription step (next) does. On success, [onCreated] is
/// called with the new court id so the router can route to the subscription page.
class CourtOnboardingScreen extends ConsumerStatefulWidget {
  const CourtOnboardingScreen({super.key, required this.onCreated});

  final void Function(String courtId) onCreated;

  @override
  ConsumerState<CourtOnboardingScreen> createState() =>
      _CourtOnboardingScreenState();
}

class _CourtOnboardingScreenState
    extends ConsumerState<CourtOnboardingScreen> {
  final _nameCtl = TextEditingController();
  final _addressCtl = TextEditingController();
  final _feeCtl = TextEditingController();
  final _customFeeCtl = TextEditingController();
  final _slotsCtl = TextEditingController(text: '1');

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameCtl.dispose();
    _addressCtl.dispose();
    _feeCtl.dispose();
    _customFeeCtl.dispose();
    _slotsCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Court name is required');
      return;
    }
    final slots = int.tryParse(_slotsCtl.text.trim()) ?? 0;
    if (slots < 1) {
      setState(() => _error = 'Number of courts must be at least 1');
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
      final id = await ref.read(courtRepositoryProvider).createCourt(
            name: name,
            entryFeeCents: fee,
            currency: 'PHP',
            numCourts: slots,
            address: _addressCtl.text.trim().isEmpty
                ? null
                : _addressCtl.text.trim(),
            customFeeCents: customFeeCents,
          );
      if (mounted) widget.onCreated(id);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not create court. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Set up your court')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Tell us about your venue. You can edit these details later.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
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
                labelText: 'Entry fee (PHP)',
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
                labelText: 'Private booking rate (PHP/hr)',
                helperText:
                    'Enables "Book a Court" for players. Leave blank to disable.',
                prefixIcon: Icon(PhosphorIconsFill.lock),
              ),
            ),
            _SectionHeader('Capacity', theme),
            const SizedBox(height: 12),
            TextField(
              controller: _slotsCtl,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Number of courts',
                prefixIcon: Icon(PhosphorIconsFill.gridFour),
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
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Create court'),
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
