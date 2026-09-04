import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Small map preview with a center pin. The user pans/zooms the map until the
/// pin sits on the right spot — auto-captured GPS + manual nudge (master
/// plan §3). Value changes on every map move.
class PinEditor extends StatelessWidget {
  const PinEditor({
    super.key,
    required this.initial,
    required this.onChanged,
    this.height = 220,
  });

  final LatLng initial;
  final ValueChanged<LatLng> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: initial,
              initialZoom: 15,
              onPositionChanged: (position, hasGesture) {
                onChanged(position.center);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                // OSM blocks/throttles tile requests without this.
                userAgentPackageName: 'in.relink.relink_mobile',
              ),
            ],
          ),
          const Center(
            child: Padding(
              // Lift the pin so its tip, not its center, marks the point.
              padding: EdgeInsets.only(bottom: 36),
              child: Icon(Icons.location_pin,
                  size: 40, color: Colors.black87),
            ),
          ),
          const Positioned(
            left: 8,
            bottom: 8,
            child: Card(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text('Drag the map to nudge the pin',
                    style: TextStyle(fontSize: 12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
