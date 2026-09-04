import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../config.dart';
import '../../models/mesh_message.dart';
import '../../services/location_service.dart';
import '../../services/sync_service.dart';
import '../../storage/outbox_dao.dart';
import '../map/pin_editor.dart';

/// Shared plumbing for the three submission forms (Phase 2 §6):
/// one-shot GPS fix on open (8 s timeout, manual-pin fallback), draggable pin
/// nudge, mesh-envelope build, outbox-first submit, calm snackbar outcome.
abstract class SubmissionFormState<T extends StatefulWidget> extends State<T> {
  Position? _fix;
  LatLng? _pin; // user-nudged position; defaults to the GPS fix
  String? _locationError;
  bool _submitting = false;

  LatLng get effectivePin =>
      _pin ??
      (_fix != null
          ? LatLng(_fix!.latitude, _fix!.longitude)
          : const LatLng(kDemoCenterLat, kDemoCenterLng));

  bool get locating => _fix == null && _locationError == null;

  @override
  void initState() {
    super.initState();
    _acquireLocation();
  }

  Future<void> _acquireLocation() async {
    final result = await context.read<LocationService>().getCurrent();
    if (!mounted) return;
    setState(() {
      _fix = result.position;
      _locationError = result.error;
      if (result.position != null) {
        _pin ??= LatLng(result.position!.latitude, result.position!.longitude);
      }
    });
  }

  Widget locationSection() {
    if (locating) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 10),
              Text('Locating…'),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_locationError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '$_locationError Drag the map to set the spot manually.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: PinEditor(
            initial: effectivePin,
            onChanged: (p) => _pin = p,
          ),
        ),
      ],
    );
  }

  /// Enqueue (always) then attempt one immediate flush; calm snackbar either
  /// way; pops the form on success so the user lands back at the hub.
  Future<void> submitMessage(MessageType type, Map<String, dynamic> payload) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    // Capture context-bound services before any await (context use across
    // async gaps below is guarded by `mounted`, but reads are cheap to hoist).
    final outbox = context.read<OutboxDao>();
    final sync = context.read<SyncService>();
    try {
      final message = MeshMessage(
        id: const Uuid().v4(),
        type: type,
        originDeviceId: await getDeviceId(),
        ttl: 6,
        priority: MessagePriority.normal,
        timestamp: DateTime.now().toUtc().toIso8601String(),
        payload: payload,
      );
      await outbox.enqueue(message);
      await sync.flushOnce();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(sync.lastFlushSentAll
              ? 'Submitted ✓ — thank you, this helps people nearby.'
              : 'Saved — will send when connected.'),
        ),
      );
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget submitButton({required String label, required VoidCallback? onPressed}) {
    return FilledButton.icon(
      onPressed: _submitting ? null : onPressed,
      icon: _submitting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : const Icon(Icons.send_outlined),
      label: Text(label),
    );
  }
}
