import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../mesh/mesh_manager.dart';
import '../../services/location_service.dart';
import '../../services/medical_profile_store.dart';
import '../../services/sync_service.dart';
import '../../storage/outbox_dao.dart';
import '../../theme.dart';
import 'medical_card_form.dart';
import 'sos_controller.dart';

/// The SOS screen — one large button, one confirmation step, then the outbox
/// owns the message (Phase 2 §5).
class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

enum _SosState { idle, locating, sent, queued }

class _SosScreenState extends State<SosScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  _SosState _state = _SosState.idle;

  @override
  void initState() {
    super.initState();
    // Gentle ~1 Hz pulse — the one place motion is allowed to feel urgent.
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _onSosTap() async {
    setState(() => _state = _SosState.locating);
    final location = context.read<LocationService>();
    final store = context.read<MedicalProfileStore>();

    final result = await location.getCurrent();
    final profile = await store.load();
    if (!mounted) return;
    setState(() => _state = _SosState.idle);

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _ConfirmSheet(
        position: result.position,
        locationError: result.error,
        permanentlyDenied: result.permanentlyDenied,
        hasMedicalCard: profile.hasPlaintextInfo,
      ),
    );
    if (confirmed != true || !mounted) return;
    await _sendSos(result.position);
  }

  Future<void> _sendSos(Position? position) async {
    final store = context.read<MedicalProfileStore>();
    final controller = SosController(
      outbox: context.read<OutboxDao>(),
      sync: context.read<SyncService>(),
      meshManager: context.read<MeshManager?>(),
    );

    // No GPS fix — fall back to the demo region center so the SOS is still
    // actionable; the confirmation sheet already told the user this.
    final lat = position?.latitude ?? kDemoCenterLat;
    final lng = position?.longitude ?? kDemoCenterLng;

    final sent = await controller.sendSos(
      lat: lat,
      lng: lng,
      profile: await store.load(),
      deviceId: await getDeviceId(),
    );
    if (!mounted) return;

    setState(() => _state = sent ? _SosState.sent : _SosState.queued);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: Tween(begin: 1.0, end: 1.04).animate(
                  CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
                ),
                child: SizedBox(
                  width: 180,
                  height: 180,
                  child: Material(
                    color: RelinkColors.alarmRed,
                    shape: const CircleBorder(),
                    elevation: 6,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _state == _SosState.locating ? null : _onSosTap,
                      child: Center(
                        child: _state == _SosState.locating
                            ? const CircularProgressIndicator(
                                color: Colors.white)
                            : const Text(
                                'SOS',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 44,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                "You're not alone — help gets this message as soon as any nearby phone has signal.",
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (_state == _SosState.sent)
                const _StatusBanner(
                  icon: Icons.check_circle_outline,
                  text: 'SOS sent to responders.',
                ),
              if (_state == _SosState.queued)
                const _StatusBanner(
                  icon: Icons.cloud_off_outlined,
                  text:
                      'No signal — your SOS is saved and will send automatically when any connection returns.',
                ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MedicalCardForm()),
                ),
                icon: const Icon(Icons.medical_information_outlined),
                label: const Text('Edit medical card'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: RelinkColors.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

/// Confirmation sheet — accidental presses are the top false-SOS source, so
/// this deliberate second step is intentional (Phase 2 §5).
class _ConfirmSheet extends StatelessWidget {
  const _ConfirmSheet({
    required this.position,
    required this.locationError,
    required this.permanentlyDenied,
    required this.hasMedicalCard,
  });

  final Position? position;
  final String? locationError;
  final bool permanentlyDenied;
  final bool hasMedicalCard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Send an SOS?', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.my_location, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: position != null
                    ? Text(
                        'Location: ${position!.latitude.toStringAsFixed(5)}, ${position!.longitude.toStringAsFixed(5)}')
                    : Text(locationError ??
                        'Locating… the SOS will use an approximate location'),
              ),
              if (permanentlyDenied)
                TextButton(
                  onPressed: () =>
                      context.read<LocationService>().openAppSettings(),
                  child: const Text('Settings'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                hasMedicalCard
                    ? Icons.medical_information
                    : Icons.medical_information_outlined,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: hasMedicalCard
                    ? const Text('Medical card ✓ attached')
                    : const Text('No medical info yet'),
              ),
              if (!hasMedicalCard)
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MedicalCardForm()),
                  ),
                  child: const Text('Add medical info'),
                ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(
              // RESERVED alarm red — SOS is its allowed use.
              backgroundColor: RelinkColors.alarmRed,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Send SOS'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
