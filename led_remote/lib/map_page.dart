import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'stm32_telemetry.dart';
import 'theme/tx_palette.dart';

enum _MapBasemap { dark, standard, satellite }

enum _DrawMode { none, waypoint, area }

class _Waypoint {
  const _Waypoint({required this.id, required this.point, required this.name});
  final int id;
  final LatLng point;
  final String name;
}

class _Area {
  const _Area({required this.id, required this.points, required this.name});
  final int id;
  final List<LatLng> points; // closed by polygon renderer
  final String name;
}

/// OpenStreetMap / satellite tiles via [flutter_map] — free, no API key.
class MapPage extends StatefulWidget {
  const MapPage({
    super.key,
    required this.useEsp,
    this.fetchSerial,
  });

  final bool useEsp;
  final Future<List<String>> Function()? fetchSerial;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  static const _defaultCenter = LatLng(37.421998, -122.084);
  static final _pollPeriod = Duration(milliseconds: kIsWeb ? 2200 : 1800);

  final MapController _mapController = MapController();

  LatLng _home = _defaultCenter;
  LatLng? _drone;
  FcTelemetrySnapshot? _fc;
  Timer? _pollTimer;
  bool _polling = false;
  bool _mapReady = false;
  _MapBasemap _basemap = _MapBasemap.dark;

  _DrawMode _drawMode = _DrawMode.none;
  int _nextWaypointId = 1;
  int _nextAreaId = 1;
  final List<_Waypoint> _waypoints = <_Waypoint>[];
  final List<_Area> _areas = <_Area>[];
  final List<LatLng> _areaDraft = <LatLng>[];

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(MapPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.useEsp != widget.useEsp) {
      if (widget.useEsp) {
        _startPolling();
      } else {
        _pollTimer?.cancel();
        _pollTimer = null;
        setState(() => _drone = null);
      }
    }
  }

  void _startPolling() {
    if (!widget.useEsp || widget.fetchSerial == null) return;
    _pollTimer ??= Timer.periodic(_pollPeriod, (_) => _pollTelemetry());
    _pollTelemetry();
  }

  Future<void> _pollTelemetry() async {
    if (_polling || widget.fetchSerial == null) return;
    _polling = true;
    try {
      final lines = await widget.fetchSerial!();
      if (!mounted) return;
      final snap = FcTelemetrySnapshot.parse(lines);
      LatLng? drone;
      if (snap.hasGps) {
        drone = LatLng(snap.latitude!, snap.longitude!);
      }
      final droneMoved = drone != null &&
          (_drone == null ||
              _drone!.latitude != drone.latitude ||
              _drone!.longitude != drone.longitude);
      final fcChanged = snap.armed != _fc?.armed ||
          snap.throttlePercent != _fc?.throttlePercent;
      if (!droneMoved && !fcChanged && drone == _drone) return;
      setState(() {
        _fc = snap;
        _drone = drone;
      });
    } catch (_) {
      // Serial errors handled on Serial tab.
    } finally {
      _polling = false;
    }
  }

  void _recenter(LatLng target) {
    _mapController.move(target, _mapController.camera.zoom);
  }

  void _setHomeHere() {
    setState(() => _home = _mapController.camera.center);
  }

  void _onMapTap(LatLng p) {
    switch (_drawMode) {
      case _DrawMode.none:
        return;
      case _DrawMode.waypoint:
        _addWaypoint(p);
        return;
      case _DrawMode.area:
        _addAreaVertex(p);
        return;
    }
  }

  void _addWaypoint(LatLng p) {
    setState(() {
      final id = _nextWaypointId++;
      _waypoints.add(_Waypoint(id: id, point: p, name: 'WP$id'));
    });
  }

  void _addAreaVertex(LatLng p) {
    setState(() => _areaDraft.add(p));
  }

  void _finishArea() {
    if (_areaDraft.length < 3) return;
    setState(() {
      final id = _nextAreaId++;
      _areas.add(_Area(id: id, points: List<LatLng>.from(_areaDraft), name: 'A$id'));
      _areaDraft.clear();
      _drawMode = _DrawMode.none;
    });
  }

  void _cancelAreaDraft() {
    setState(() {
      _areaDraft.clear();
      _drawMode = _DrawMode.none;
    });
  }

  void _clearWaypoints() => setState(_waypoints.clear);
  void _clearAreas() => setState(() {
        _areas.clear();
        _areaDraft.clear();
      });
  void _clearAll() => setState(() {
        _waypoints.clear();
        _areas.clear();
        _areaDraft.clear();
        _drawMode = _DrawMode.none;
      });

  void _showDrawManager() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: TxPalette.panelDeep,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Waypoints & Areas',
                  style: TxPalette.labelStyle.copyWith(
                    color: TxPalette.amber,
                    fontSize: 10,
                    letterSpacing: 3,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                if (_waypoints.isEmpty && _areas.isEmpty)
                  Text(
                    'No items yet.\n\n'
                    'Use WPT to tap waypoints, or AREA to tap vertices then DONE.',
                    style: const TextStyle(color: TxPalette.labelMuted, height: 1.35),
                    textAlign: TextAlign.center,
                  ),
                if (_waypoints.isNotEmpty) ...[
                  Text('Waypoints', style: TxPalette.labelStyle.copyWith(fontSize: 9)),
                  const SizedBox(height: 6),
                  ..._waypoints.map((w) => _ManagerRow(
                        title: w.name,
                        subtitle:
                            '${w.point.latitude.toStringAsFixed(6)}, ${w.point.longitude.toStringAsFixed(6)}',
                        onDelete: () {
                          setState(() => _waypoints.removeWhere((x) => x.id == w.id));
                        },
                      )),
                  const SizedBox(height: 10),
                ],
                if (_areas.isNotEmpty) ...[
                  Text('Areas', style: TxPalette.labelStyle.copyWith(fontSize: 9)),
                  const SizedBox(height: 6),
                  ..._areas.map((a) => _ManagerRow(
                        title: a.name,
                        subtitle: '${a.points.length} points',
                        onDelete: () {
                          setState(() => _areas.removeWhere((x) => x.id == a.id));
                        },
                      )),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: _waypoints.isEmpty ? null : _clearWaypoints,
                        child: Text('Clear WPT', style: TextStyle(color: TxPalette.amber)),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: _areas.isEmpty ? null : _clearAreas,
                        child: Text('Clear Areas', style: TextStyle(color: TxPalette.amber)),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: (_waypoints.isEmpty && _areas.isEmpty) ? null : _clearAll,
                        child: Text('Clear All', style: TextStyle(color: TxPalette.amber)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Marker> get _markers {
    final markers = <Marker>[
      Marker(
        point: _home,
        width: 36,
        height: 36,
        alignment: Alignment.topCenter,
        child: const _MapPin(icon: Icons.home_rounded, color: TxPalette.amber),
      ),
    ];
    final d = _drone;
    if (d != null) {
      markers.add(
        Marker(
          point: d,
          width: 36,
          height: 36,
          alignment: Alignment.topCenter,
          child: _MapPin(
            icon: Icons.flight_rounded,
            color: TxPalette.armLed,
            label: _fc?.armed == true ? 'ARM' : null,
          ),
        ),
      );
    }

    for (final w in _waypoints) {
      markers.add(
        Marker(
          point: w.point,
          width: 56,
          height: 44,
          alignment: Alignment.topCenter,
          child: _WaypointPin(name: w.name),
        ),
      );
    }

    return markers;
  }

  List<Polyline> get _polylines {
    final lines = <Polyline>[];
    if (_areaDraft.length >= 2) {
      lines.add(
        Polyline(
          points: List<LatLng>.from(_areaDraft),
          color: TxPalette.amber.withValues(alpha: 0.85),
          strokeWidth: 3,
        ),
      );
    }
    for (final a in _areas) {
      lines.add(
        Polyline(
          points: a.points,
          color: TxPalette.amber.withValues(alpha: 0.65),
          strokeWidth: 2,
        ),
      );
    }
    return lines;
  }

  List<Polygon> get _polygons {
    return _areas
        .map(
          (a) => Polygon(
            points: a.points,
            color: TxPalette.amber.withValues(alpha: 0.18),
            borderColor: TxPalette.amber.withValues(alpha: 0.65),
            borderStrokeWidth: 2,
          ),
        )
        .toList();
  }

  void _showMapInfo() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TxPalette.panelDeep,
        title: Text('Map', style: TextStyle(color: TxPalette.amber)),
        content: const SingleChildScrollView(
          child: Text(
            'Free map tiles — no API key.\n\n'
            '• Dark / Lite = street maps (OSM + CARTO)\n'
            '• Sat = satellite imagery (Esri)\n'
            '• Orange = home (Set H pins map center)\n'
            '• Green = drone when STM32 sends lat/lon on serial\n'
            '• Example: lat 37.42 lon -122.08',
            style: TextStyle(
              color: TxPalette.labelMuted,
              height: 1.45,
              fontSize: 13,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('OK', style: TextStyle(color: TxPalette.amber)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: TxPalette.panel,
      child: Column(
        children: [
          _MapToolbar(
            hasDrone: _drone != null,
            basemap: _basemap,
            onRecenterHome: () => _recenter(_home),
            onRecenterDrone:
                _drone != null ? () => _recenter(_drone!) : null,
            onSetHome: _mapReady ? _setHomeHere : null,
            onBasemap: (b) => setState(() => _basemap = b),
              drawMode: _drawMode,
              areaDraftCount: _areaDraft.length,
              onWaypointsMode: () => setState(() {
                    _areaDraft.clear();
                    _drawMode = _drawMode == _DrawMode.waypoint ? _DrawMode.none : _DrawMode.waypoint;
                  }),
              onAreaMode: () => setState(() {
                    _drawMode = _drawMode == _DrawMode.area ? _DrawMode.none : _DrawMode.area;
                    if (_drawMode != _DrawMode.area) _areaDraft.clear();
                  }),
              onAreaDone: _areaDraft.length >= 3 ? _finishArea : null,
              onAreaCancel: _areaDraft.isNotEmpty ? _cancelAreaDraft : null,
              onManage: _showDrawManager,
            onInfo: _showMapInfo,
          ),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _home,
                    initialZoom: 16,
                    onTap: (tapPosition, point) => _onMapTap(point),
                    onMapReady: () {
                      if (mounted) setState(() => _mapReady = true);
                    },
                  ),
                  children: [
                    TileLayer(
                      key: ValueKey(_basemap),
                      urlTemplate: switch (_basemap) {
                        _MapBasemap.dark =>
                          'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                        _MapBasemap.standard =>
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        _MapBasemap.satellite =>
                          'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                      },
                      subdomains: switch (_basemap) {
                        _MapBasemap.dark => const ['a', 'b', 'c', 'd'],
                        _MapBasemap.standard => const ['a', 'b', 'c'],
                        _MapBasemap.satellite => const ['a'],
                      },
                      userAgentPackageName: 'com.example.led_remote',
                      retinaMode: RetinaMode.isHighDensity(context),
                    ),
                    if (_polygons.isNotEmpty) PolygonLayer(polygons: _polygons),
                    if (_polylines.isNotEmpty) PolylineLayer(polylines: _polylines),
                    MarkerLayer(markers: _markers),
                    RichAttributionWidget(
                      alignment: AttributionAlignment.bottomRight,
                      attributions: [
                        TextSourceAttribution(switch (_basemap) {
                          _MapBasemap.dark => '© OpenStreetMap · © CARTO',
                          _MapBasemap.standard => '© OpenStreetMap',
                          _MapBasemap.satellite =>
                            '© Esri · Maxar · Earthstar Geographics',
                        }),
                      ],
                    ),
                  ],
                ),
                if (_drone == null && widget.useEsp)
                  Positioned(
                    left: 12,
                    bottom: 28,
                    child: _HintChip(
                      text: _fc?.hasGps == true
                          ? 'GPS on serial'
                          : 'No GPS on serial — add lat/lon from STM32',
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin({
    required this.icon,
    required this.color,
    this.label,
  });

  final IconData icon;
  final Color color;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            margin: const EdgeInsets.only(bottom: 2),
            decoration: BoxDecoration(
              color: TxPalette.statusBg.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              label!,
              style: const TextStyle(
                color: TxPalette.armLed,
                fontSize: 7,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
              ),
            ),
          ),
        Icon(icon, color: color, size: 28, shadows: const [
          Shadow(color: Colors.black54, blurRadius: 4),
        ]),
      ],
    );
  }
}

class _WaypointPin extends StatelessWidget {
  const _WaypointPin({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          margin: const EdgeInsets.only(bottom: 2),
          decoration: BoxDecoration(
            color: TxPalette.statusBg.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: TxPalette.engraved),
          ),
          child: Text(
            name,
            style: const TextStyle(
              color: TxPalette.amber,
              fontSize: 8,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
        ),
        const Icon(Icons.place_rounded, color: TxPalette.amber, size: 24, shadows: [
          Shadow(color: Colors.black54, blurRadius: 4),
        ]),
      ],
    );
  }
}

class _MapToolbar extends StatelessWidget {
  const _MapToolbar({
    required this.hasDrone,
    required this.basemap,
    required this.onRecenterHome,
    this.onRecenterDrone,
    this.onSetHome,
    required this.onBasemap,
    required this.drawMode,
    required this.areaDraftCount,
    required this.onWaypointsMode,
    required this.onAreaMode,
    this.onAreaDone,
    this.onAreaCancel,
    required this.onManage,
    this.onInfo,
  });

  final bool hasDrone;
  final _MapBasemap basemap;
  final VoidCallback onRecenterHome;
  final VoidCallback? onRecenterDrone;
  final VoidCallback? onSetHome;
  final ValueChanged<_MapBasemap> onBasemap;
  final _DrawMode drawMode;
  final int areaDraftCount;
  final VoidCallback onWaypointsMode;
  final VoidCallback onAreaMode;
  final VoidCallback? onAreaDone;
  final VoidCallback? onAreaCancel;
  final VoidCallback onManage;
  final VoidCallback? onInfo;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TxPalette.panelDeep,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Row(
            children: [
              Icon(Icons.map_outlined, color: TxPalette.amber, size: 20),
              const SizedBox(width: 8),
              Text(
                'MAP',
                style: TxPalette.labelStyle.copyWith(
                  color: TxPalette.amber,
                  fontSize: 10,
                  letterSpacing: 3,
                ),
              ),
              const Spacer(),
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ToolBtn(
                        icon: Icons.home_work_outlined,
                        label: 'Home',
                        onTap: onRecenterHome,
                      ),
                      if (hasDrone && onRecenterDrone != null) ...[
                        const SizedBox(width: 6),
                        _ToolBtn(
                          icon: Icons.flight_outlined,
                          label: 'Drone',
                          onTap: onRecenterDrone!,
                        ),
                      ],
                      const SizedBox(width: 6),
                      _ToolBtn(
                        icon: Icons.push_pin_outlined,
                        label: 'Set H',
                        onTap: onSetHome,
                      ),
                      const SizedBox(width: 6),
                      _ToolBtn(
                        icon: Icons.place_outlined,
                        label: 'WPT',
                        selected: drawMode == _DrawMode.waypoint,
                        onTap: onWaypointsMode,
                      ),
                      const SizedBox(width: 6),
                      _ToolBtn(
                        icon: Icons.pentagon_outlined,
                        label: areaDraftCount > 0 ? 'AREA+$areaDraftCount' : 'AREA',
                        selected: drawMode == _DrawMode.area,
                        onTap: onAreaMode,
                      ),
                      if (drawMode == _DrawMode.area && areaDraftCount > 0) ...[
                        const SizedBox(width: 6),
                        _ToolBtn(
                          icon: Icons.check_rounded,
                          label: 'DONE',
                          onTap: onAreaDone,
                        ),
                        const SizedBox(width: 6),
                        _ToolBtn(
                          icon: Icons.close_rounded,
                          label: 'Cancel',
                          onTap: onAreaCancel,
                        ),
                      ],
                      const SizedBox(width: 6),
                      _ToolBtn(
                        icon: Icons.list_alt_rounded,
                        label: 'List',
                        onTap: onManage,
                      ),
                      const SizedBox(width: 6),
                      _ToolBtn(
                        icon: Icons.dark_mode_outlined,
                        label: 'Dark',
                        selected: basemap == _MapBasemap.dark,
                        onTap: () => onBasemap(_MapBasemap.dark),
                      ),
                      const SizedBox(width: 6),
                      _ToolBtn(
                        icon: Icons.light_mode_outlined,
                        label: 'Lite',
                        selected: basemap == _MapBasemap.standard,
                        onTap: () => onBasemap(_MapBasemap.standard),
                      ),
                      const SizedBox(width: 6),
                      _ToolBtn(
                        icon: Icons.satellite_alt_outlined,
                        label: 'Sat',
                        selected: basemap == _MapBasemap.satellite,
                        onTap: () => onBasemap(_MapBasemap.satellite),
                      ),
                      const SizedBox(width: 6),
                      _ToolBtn(
                        icon: Icons.info_outline,
                        label: 'Info',
                        onTap: onInfo,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolBtn extends StatelessWidget {
  const _ToolBtn({
    required this.icon,
    required this.label,
    this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? TxPalette.amber.withValues(alpha: 0.18)
          : TxPalette.matteCap,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: selected
                ? Border.all(color: TxPalette.amber.withValues(alpha: 0.65))
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: TxPalette.amber),
              const SizedBox(width: 4),
              Text(
                label,
                style: TxPalette.labelStyle.copyWith(
                  fontSize: 8,
                  color: selected ? TxPalette.amber : TxPalette.labelMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManagerRow extends StatelessWidget {
  const _ManagerRow({
    required this.title,
    required this.subtitle,
    required this.onDelete,
  });

  final String title;
  final String subtitle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: TxPalette.matteCap,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: TxPalette.engraved),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: TxPalette.amber, fontFamily: 'monospace')),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: TxPalette.labelMuted, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, color: TxPalette.amber),
            tooltip: 'Delete',
          ),
        ],
      ),
    );
  }
}

class _HintChip extends StatelessWidget {
  const _HintChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: TxPalette.statusBg.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: TxPalette.engraved),
      ),
      child: Text(
        text,
        style: TxPalette.labelStyle.copyWith(fontSize: 8, letterSpacing: 0.5),
      ),
    );
  }
}
