import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:relink_mobile/models/alert.dart';
import 'package:relink_mobile/screens/alerts/alerts_screen.dart';
import 'package:relink_mobile/screens/stats/stats_screen.dart';
import 'package:relink_mobile/services/api_client.dart';
import 'package:relink_mobile/theme.dart';

/// Builds the screen under test with a stubbed [ApiClient] backed by an
/// in-memory HTTP handler, so no real network or plugins are involved.
Widget _wrap(Widget child, Map<String, Object> routes) {
  final mock = MockClient((req) async {
    final path = req.url.path;
    // Longest-prefix-first so '/stats/ai-review' beats '/stats'.
    final keys = routes.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
    for (final key in keys) {
      if (path.startsWith(key)) {
        final body = routes[key]!;
        return http.Response(
          body is String ? body : jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
    }
    return http.Response('not found', 404);
  });
  return Provider<ApiClient>.value(
    value: ApiClient(httpClient: mock, baseUrl: 'http://test'),
    child: MaterialApp(theme: buildRelinkTheme(), home: Scaffold(body: child)),
  );
}

void main() {
  testWidgets('Alerts screen renders an urgent Red alert verbatim', (tester) async {
    final alert = {
      'id': 'a1',
      'cap_identifier': 'X1',
      'source': 'sachet',
      'state': 'kerala',
      'event': 'Flash Flood',
      'headline': 'Severe Flooding Alert: Aluva & Paravur taluks.',
      'description': 'Rapid inundation of low-lying areas.',
      'instruction': 'Move to the nearest relief camp.',
      'severity': 'Red',
      'urgency': 'Immediate',
      'certainty': 'Observed',
      'area_desc': 'Aluva, Paravur',
      'sender': 'RELINK demo trigger',
      'effective': null,
      'onset': null,
      'expires': null,
      'issued_at': '2026-09-05T09:00:00Z',
      'is_test': 1,
      'created_at': '2026-09-05T09:00:00Z',
    };
    await tester.pumpWidget(_wrap(const AlertsScreen(), {'/alerts': [alert]}));
    await tester.pumpAndSettle();

    expect(find.text('Severe Flooding Alert: Aluva & Paravur taluks.'), findsOneWidget);
    expect(find.text('RED'), findsOneWidget); // urgent severity chip
    expect(find.text('Move to the nearest relief camp.'), findsOneWidget);
  });

  testWidgets('Alert model flags urgent severities', (tester) async {
    Alert withSeverity(String s) => Alert.fromJson({
          'id': s,
          'severity': s,
          'event': null,
          'headline': null,
          'description': null,
          'instruction': null,
          'area_desc': null,
          'sender': null,
          'issued_at': null,
          'expires': null,
          'is_test': 0,
        });
    expect(withSeverity('Red').isUrgent, isTrue);
    expect(withSeverity('Severe').isUrgent, isTrue);
    expect(withSeverity('Orange').isUrgent, isTrue);
    expect(withSeverity('Moderate').isUrgent, isFalse);
    expect(withSeverity('Green').isUrgent, isFalse);
  });

  testWidgets('Stats screen renders AI review + river + dams', (tester) async {
    final stats = {
      'region': 'Kochi, Kerala',
      'fetched_at': '2026-09-05T09:00:00Z',
      'metrics': {
        'glofas': {
          'discharge_m3s': 6.08,
          'mean_m3s': 6.09,
          'trend': 'steady',
          'forecast': [
            {'date': '2026-09-05', 'discharge_m3s': 6.08, 'mean_m3s': 6.09},
            {'date': '2026-09-06', 'discharge_m3s': 5.76, 'mean_m3s': 5.74},
            {'date': '2026-09-07', 'discharge_m3s': 5.5, 'mean_m3s': 5.47},
          ],
          'source_label': 'GloFAS Flood API',
        },
        'weather': {
          'rainfall_24h_mm': 0.7,
          'max_gust_kmh': 35.3,
          'hourly': [
            {'time': '2026-09-04T00:00', 'precipitation_mm': 0.0, 'wind_gust_kmh': 10.0},
            {'time': '2026-09-04T01:00', 'precipitation_mm': 1.2, 'wind_gust_kmh': 12.0},
          ],
          'source_label': 'IMD (Open-Meteo)',
        },
        'dams': {
          'dams': [
            {'name': 'Mullaperiyar', 'storage_pct': 92.7, 'danger_level_pct': 95.0},
            {'name': 'Idukki', 'storage_pct': 88.4, 'danger_level_pct': 95.0},
          ],
          'count': 2,
          'source_label': 'CWC Dams',
        },
        'gfm': {
          'observed_at': '2026-09-04T18:00:00Z',
          'polygon_count': 4,
          'source_label': 'Copernicus GFM (Sentinel-1 SAR)',
        },
      },
    };
    final review = {
      'region': 'Kochi, Kerala',
      'summary_text': 'Periyar discharge is 6 m³/s. Mullaperiyar reservoir is at 92.7% storage. RISK TAG: Severe',
      'risk_tag': 'Severe',
      'source': 'rule',
      'generated_at': '2026-09-05T09:00:00Z',
      'stale': false,
    };
    await tester.pumpWidget(_wrap(const StatsScreen(), {
      '/stats/ai-review': review,
      '/stats': stats, // after /stats/ai-review so the longer prefix wins
    }));
    // Bounded pumps — fl_chart runs indefinite animations, so pumpAndSettle
    // would never return.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(find.text('Risk assessment'), findsOneWidget);
    expect(find.text('SEVERE'), findsOneWidget);
    expect(find.text('Periyar river discharge'), findsOneWidget);
    expect(find.text('Rainfall & wind'), findsOneWidget);
    // Off-screen cards (Reservoir levels / dam rows) are lazily built only
    // when scrolled into view; the fixtures flowing into them are covered by
    // the backend /stats test.
  });
}
