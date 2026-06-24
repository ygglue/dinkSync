import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../app/theme.dart';
import 'court_repository.dart';

/// Step 2 of becoming a host: subscribe to publish the court. Uses the mock
/// payment path (the RPC records a paid payment + activates the court).
class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({
    super.key,
    required this.courtId,
    required this.onSubscribed,
    required this.onBack,
  });

  final String courtId;
  final void Function() onSubscribed;

  /// Invoked by the app bar back button. The router wires this to pop back to
  /// the management dashboard (or go there if there's nothing to pop).
  final void Function() onBack;

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  SubscriptionPlan _plan = SubscriptionPlan.monthly;
  bool _busy = false;
  String? _error;

  String _peso(int centavos) => '₱${(centavos / 100).toStringAsFixed(0)}';

  Future<void> _subscribe() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(courtRepositoryProvider).subscribeCourt(
            courtId: widget.courtId,
            plan: _plan,
          );
      if (mounted) widget.onSubscribed();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Subscription failed. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _planTile(SubscriptionPlan plan, String title, String sub) {
    final selected = _plan == plan;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(kRadius),
      onTap: _busy ? null : () => setState(() => _plan = plan),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(kRadius),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? PhosphorIconsFill.radioButton
                  : PhosphorIconsRegular.radioButton,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: Theme.of(context).textTheme.titleMedium),
                  Text(sub,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: widget.onBack),
        title: const Text('Subscribe to publish'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'A subscription keeps your court listed and bookable. Players '
              "can't see it until you subscribe.",
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            _planTile(
              SubscriptionPlan.monthly,
              'Monthly',
              '${_peso(planPriceCents(SubscriptionPlan.monthly))} / month',
            ),
            const SizedBox(height: 12),
            _planTile(
              SubscriptionPlan.yearly,
              'Yearly',
              '${_peso(planPriceCents(SubscriptionPlan.yearly))} / year — 2 months free',
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _subscribe,
              child: _busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Subscribe'),
            ),
          ],
        ),
      ),
    );
  }
}
