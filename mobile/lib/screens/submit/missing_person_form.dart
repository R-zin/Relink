import 'package:flutter/material.dart';

import '../../models/mesh_message.dart';
import 'submission_base.dart';

/// Missing-person form (Phase 2 §6): name + description + last-seen GPS.
/// Last-seen location + description only — no face matching (deferred).
class MissingPersonForm extends StatefulWidget {
  const MissingPersonForm({super.key});

  @override
  State<MissingPersonForm> createState() => _MissingPersonFormState();
}

class _MissingPersonFormState extends SubmissionFormState<MissingPersonForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    submitMessage(MessageType.missingPerson, {
      'name': _name.text.trim(),
      'last_seen_lat': effectivePin.latitude,
      'last_seen_lng': effectivePin.longitude,
      if (_description.text.trim().isNotEmpty)
        'description': _description.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report a missing person')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
                'This goes on the shared map so people nearby can keep an eye out.'),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Their name'),
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Please enter their name'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'age, clothing, identifying marks…',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            Text('Where were they last seen?',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            locationSection(),
            const SizedBox(height: 24),
            submitButton(label: 'Share missing-person report', onPressed: _submit),
          ],
        ),
      ),
    );
  }
}
