import 'package:flutter/material.dart';

import '../../models/mesh_message.dart';
import '../../models/report.dart';
import 'submission_base.dart';

/// Hazard report form (Phase 2 §6): type chips + description + GPS + nudge.
class ReportForm extends StatefulWidget {
  const ReportForm({super.key});

  @override
  State<ReportForm> createState() => _ReportFormState();
}

class _ReportFormState extends SubmissionFormState<ReportForm> {
  static const _types = ['obstacle', 'disease', 'water'];

  String _type = 'obstacle';
  final _description = TextEditingController();

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  void _submit() => submitMessage(MessageType.report, {
        'type': _type,
        'lat': effectivePin.latitude,
        'lng': effectivePin.longitude,
        if (_description.text.trim().isNotEmpty)
          'description': _description.text.trim(),
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report a hazard')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('What kind of hazard?',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final t in _types)
                ChoiceChip(
                  label: Text(Report.typeLabel(t)),
                  selected: _type == t,
                  onSelected: (_) => setState(() => _type = t),
                ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _description,
            maxLength: 500,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
              hintText: 'e.g. knee-deep water near the bus stand',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          Text('Where is it?', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          locationSection(),
          const SizedBox(height: 24),
          submitButton(label: 'Send report', onPressed: _submit),
        ],
      ),
    );
  }
}
