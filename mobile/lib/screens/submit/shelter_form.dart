import 'package:flutter/material.dart';

import '../../models/mesh_message.dart';
import 'submission_base.dart';

/// Shelter / relief camp form (Phase 2 §6): name + contact + GPS + nudge.
class ShelterForm extends StatefulWidget {
  const ShelterForm({super.key});

  @override
  State<ShelterForm> createState() => _ShelterFormState();
}

class _ShelterFormState extends SubmissionFormState<ShelterForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _contact = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    submitMessage(MessageType.shelter, {
      'name': _name.text.trim(),
      'lat': effectivePin.latitude,
      'lng': effectivePin.longitude,
      if (_contact.text.trim().isNotEmpty) 'contact_info': _contact.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add a shelter')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Shelter name',
                hintText: 'e.g. Govt. HSS Relief Camp — Edappally',
              ),
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'A name helps people find it'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _contact,
              decoration: const InputDecoration(
                labelText: 'Contact info (optional)',
                hintText: 'phone number or person to ask for',
              ),
            ),
            const SizedBox(height: 20),
            Text('Where is it?',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            locationSection(),
            const SizedBox(height: 24),
            submitButton(label: 'Share shelter', onPressed: _submit),
          ],
        ),
      ),
    );
  }
}
