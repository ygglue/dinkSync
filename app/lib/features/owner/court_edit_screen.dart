import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'court_repository.dart';

/// Edit a court's name, entry fee, and address (not slot count — that touches
/// court_slots). Uses the direct `updateCourt` path (allowed by courts_update_owner).
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
  late final TextEditingController _addressCtl =
      TextEditingController(text: widget.court.address ?? '');

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameCtl.dispose();
    _feeCtl.dispose();
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
          );
      if (mounted) widget.onSaved();
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Edit court')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
