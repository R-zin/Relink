import 'package:flutter/material.dart';

// TODO(phase4): NDMA Sachet CAP/RSS feed + FCM push; deep-link from the
// system notification into this screen's alert detail.
class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.notifications_none, size: 56),
              SizedBox(height: 16),
              Text(
                'Official alerts for your region will appear here.',
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8),
              Text(
                "When authorities issue a warning, you'll get a notification — even if the app is closed.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
