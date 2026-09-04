import 'package:flutter/material.dart';

// TODO(phase4): live hazard metrics (GET /stats) + AI risk review
// (GET /stats/ai-review) with fl_chart visualisations.
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.insights_outlined, size: 56),
              SizedBox(height: 16),
              Text(
                'Live hazard conditions and a plain-language risk summary will appear here.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
