import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

class _CourtOnboardingScreenState extends ConsumerState<CourtOnboardingScreen> {
  final _nameCtl = TextEditingController();
  final _feeCtl = TextEditingController(text: '0');
  final _slotsCtl = TextEditingController(text: '1');
  final _addressCtl = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameCtl.dispose();
    _feeCtl.dispose();
    _slotsCtl.dispose();
    _addressCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Court name is required');
      return;
    }
    final fee = parseAmountToMinor(_feeCtl.text) ?? 0;
    final slots = int.tryParse(_slotsCtl.text.trim()) ?? 0;
    if (slots < 1) {
      setState(() => _error = 'Number of courts must be at least 1');
      return;
    }

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
    return Scaffold(
      appBar: AppBar(title: const Text('Set up your court')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Tell us about your venue. You can edit these later.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _nameCtl,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Court name',
                prefixIcon: Icon(Icons.stadium_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _feeCtl,
              enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Entry fee (PHP)',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _slotsCtl,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Number of courts (playing surfaces)',
                prefixIcon: Icon(Icons.grid_view_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _addressCtl,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Address (optional)',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 24),
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
