import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/medical_profile.dart';
import '../../services/medical_profile_store.dart';

const bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

/// Medical card editor (master plan §5).
///
/// Two sections: fields broadcast openly in an SOS, and sensitive fields that
/// (from Phase 3) travel encrypted. Persisted locally via
/// [MedicalProfileStore]; re-opens pre-populated.
class MedicalCardForm extends StatefulWidget {
  const MedicalCardForm({super.key});

  @override
  State<MedicalCardForm> createState() => _MedicalCardFormState();
}

class _MedicalCardFormState extends State<MedicalCardForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _allergies = TextEditingController();
  final _contactName = TextEditingController();
  final _contactPhone = TextEditingController();
  final _conditions = TextEditingController();
  final _medications = TextEditingController();
  final _insuranceProvider = TextEditingController();
  final _insurancePolicy = TextEditingController();
  String? _bloodGroup;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    context.read<MedicalProfileStore>().load().then((profile) {
      final p = profile.plaintext;
      final s = profile.sensitive;
      setState(() {
        _name.text = p.name ?? '';
        _bloodGroup = p.bloodGroup;
        _allergies.text = p.allergies.join(', ');
        _contactName.text = p.emergencyContact?.name ?? '';
        _contactPhone.text = p.emergencyContact?.phone ?? '';
        _conditions.text = s.conditions ?? '';
        _medications.text = s.medications ?? '';
        _insuranceProvider.text = s.insuranceProvider ?? '';
        _insurancePolicy.text = s.insurancePolicyNumber ?? '';
      });
    });
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _allergies,
      _contactName,
      _contactPhone,
      _conditions,
      _medications,
      _insuranceProvider,
      _insurancePolicy,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _optional(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    final profile = MedicalProfile(
      plaintext: PlaintextMedical(
        name: _optional(_name),
        bloodGroup: _bloodGroup,
        allergies: _allergies.text
            .split(',')
            .map((a) => a.trim())
            .where((a) => a.isNotEmpty)
            .toList(),
        emergencyContact: EmergencyContact(
          name: _optional(_contactName),
          phone: _optional(_contactPhone),
        ),
      ),
      // TODO(phase3): encrypt with AES-GCM before it leaves the device.
      sensitive: SensitiveMedical(
        conditions: _optional(_conditions),
        medications: _optional(_medications),
        insuranceProvider: _optional(_insuranceProvider),
        insurancePolicyNumber: _optional(_insurancePolicy),
      ),
    );
    await context.read<MedicalProfileStore>().save(profile);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Your medical card')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Shared openly with responders',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
                'Responders see this instantly if you send an SOS — no extra steps.'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Full name'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _bloodGroup,
              decoration: const InputDecoration(labelText: 'Blood group'),
              items: bloodGroups
                  .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                  .toList(),
              onChanged: (v) => setState(() => _bloodGroup = v),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _allergies,
              decoration: const InputDecoration(
                labelText: 'Known allergies',
                hintText: 'e.g. penicillin, peanuts',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _contactName,
              decoration:
                  const InputDecoration(labelText: 'Emergency contact name'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _contactPhone,
              decoration:
                  const InputDecoration(labelText: 'Emergency contact phone'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 28),
            Text('Encrypted — only responders can read',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
                'This travels sealed. Only rescue responders can open it.'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _conditions,
              decoration: const InputDecoration(
                  labelText: 'Medical conditions / notes'),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _medications,
              decoration:
                  const InputDecoration(labelText: 'Current medications'),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _insuranceProvider,
              decoration:
                  const InputDecoration(labelText: 'Insurance provider'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _insurancePolicy,
              decoration:
                  const InputDecoration(labelText: 'Insurance policy number'),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: const Text('Save medical card'),
            ),
          ],
        ),
      ),
    );
  }
}
