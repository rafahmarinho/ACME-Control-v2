import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/equipment.dart';

/// Interactive P&ID-style diagram of the water treatment process.
///
/// * Tanks are drawn as shaded cylinders whose water level animates.
/// * Pipes show moving water particles whose speed follows the measured flow.
/// * Pump impellers spin when running; valves show position and travel.
/// * In 3D mode the whole plant is tilted in perspective and can be orbited by dragging.
/// * On narrow screens the flow is laid out vertically.
class ProcessDiagram extends StatefulWidget {
  const ProcessDiagram({
    super.key,
    required this.equipment,
    required this.onSelect,
    this.selectedTag,
    this.animate = true,
    this.enable3d = true,
    this.portrait = false,
    this.onToggle3d,
  });

  final Map<String, Equipment> equipment;
  final ValueChanged<String> onSelect;
  final String? selectedTag;
  final bool animate;
  final bool enable3d;
  final bool portrait;
  final ValueChanged<bool>? onToggle3d;

  @override
  State<ProcessDiagram> createState() => _ProcessDiagramState();
}

class _ProcessDiagramState extends State<ProcessDiagram> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _time = ValueNotifier<double>(0);
  static const _defaultRx = 0.36;
  static const _defaultRy = -0.08;
  double _rx = _defaultRx;
  double _ry = _defaultRy;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) => _time.value = elapsed.inMicroseconds / 1e6);
    if (widget.animate) _ticker.start();
  }

  @override
  void didUpdateWidget(covariant ProcessDiagram old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_ticker.isActive) _ticker.start();
    if (!widget.animate && _ticker.isActive) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = widget.portrait ? DiagramLayout.portrait() : DiagramLayout.landscape();
    final threeD = widget.enable3d;

    Widget canvas = LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth, c.maxHeight);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          final tag = layout.hitTest(d.localPosition, size, widget.equipment);
          if (tag != null) widget.onSelect(tag);
        },
        child: RepaintBoundary(
          child: CustomPaint(
            size: size,
            painter: _DiagramPainter(
              layout: layout,
              equipment: widget.equipment,
              selectedTag: widget.selectedTag,
              time: _time,
              depth: threeD,
            ),
          ),
        ),
      );
    });

    if (threeD) {
      canvas = Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0008)
          ..rotateX(_rx)
          ..rotateZ(_ry * 0.25)
          ..rotateY(_ry)
          ..scaleByDouble(1.04, 1.04, 1.04, 1),
        child: canvas,
      );
      canvas = GestureDetector(
        onPanUpdate: (d) => setState(() {
          _rx = (_rx - d.delta.dy * 0.004).clamp(0.0, 0.85);
          _ry = (_ry + d.delta.dx * 0.004).clamp(-0.6, 0.6);
        }),
        child: canvas,
      );
    }

    return Stack(children: [
      Positioned.fill(child: ClipRect(child: canvas)),
      Positioned(
        right: 8,
        top: 8,
        child: Material(
          color: AppColors.surfaceHigh.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (widget.onToggle3d != null)
              Tooltip(
                message: threeD ? 'Switch to flat 2D view' : 'Switch to 3D perspective (drag to orbit)',
                child: TextButton.icon(
                  onPressed: () => widget.onToggle3d!(!threeD),
                  icon: Icon(threeD ? Icons.view_in_ar : Icons.crop_square, size: 18),
                  label: Text(threeD ? '3D' : '2D'),
                ),
              ),
            if (threeD)
              IconButton(
                tooltip: 'Reset view',
                icon: const Icon(Icons.center_focus_strong, size: 18),
                onPressed: () => setState(() {
                  _rx = _defaultRx;
                  _ry = _defaultRy;
                }),
              ),
          ]),
        ),
      ),
      const Positioned(left: 10, bottom: 8, child: _Legend()),
    ]);
  }
}

class _Legend extends StatelessWidget {
  const _Legend();
  @override
  Widget build(BuildContext context) {
    Widget item(Color c, String t) => Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text(t, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: AppColors.surface.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(8)),
      child: Wrap(children: [
        item(AppColors.running, 'Running / open'),
        item(AppColors.stopped, 'Stopped / closed'),
        item(AppColors.warning, 'Interlocked'),
        item(AppColors.fault, 'Fault'),
        item(AppColors.lockout, 'Locked out'),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Layout (model coordinates, scaled to fit)
// ---------------------------------------------------------------------------

class DiagramPipe {
  const DiagramPipe(this.points, this.flowKey);
  final List<Offset> points;
  final String flowKey; // inlet | suction | p101 | p102 | transfer | dist
}

class DiagramLayout {
  DiagramLayout({
    required this.size,
    required this.tanks,
    required this.pumps,
    required this.valves,
    required this.instruments,
    required this.pipes,
    required this.source,
    required this.sink,
    required this.areaLabels,
    required this.portrait,
  });

  final Size size;
  final Map<String, Rect> tanks;
  final Map<String, Offset> pumps;
  final Map<String, Offset> valves;
  final Map<String, Offset> instruments;
  final List<DiagramPipe> pipes;
  final Offset source;
  final Offset sink;
  final Map<String, Offset> areaLabels;
  final bool portrait;

  factory DiagramLayout.landscape() => DiagramLayout(
        portrait: false,
        size: const Size(1200, 560),
        tanks: {
          'T-101': const Rect.fromLTRB(230, 110, 400, 420),
          'T-102': const Rect.fromLTRB(800, 110, 990, 420),
        },
        pumps: const {'P-101': Offset(540, 320), 'P-102': Offset(540, 470), 'P-201': Offset(1060, 390)},
        valves: const {'XV-101': Offset(150, 200), 'XV-102': Offset(700, 320), 'XV-201': Offset(1130, 390)},
        instruments: const {
          'FT-101': Offset(95, 140),
          'LT-101': Offset(430, 150),
          'PT-101': Offset(640, 255),
          'FT-102': Offset(740, 255),
          'LT-102': Offset(1020, 150),
          'PT-201': Offset(1060, 300),
          'FT-201': Offset(1160, 300),
        },
        pipes: const [
          DiagramPipe([Offset(40, 200), Offset(232, 200)], 'inlet'),
          DiagramPipe([Offset(400, 392), Offset(470, 392)], 'suction'),
          DiagramPipe([Offset(470, 392), Offset(470, 320), Offset(540, 320), Offset(620, 320)], 'p101'),
          DiagramPipe([Offset(470, 392), Offset(470, 470), Offset(540, 470), Offset(620, 470), Offset(620, 320)], 'p102'),
          DiagramPipe([Offset(620, 320), Offset(770, 320), Offset(770, 170), Offset(802, 170)], 'transfer'),
          DiagramPipe([Offset(990, 392), Offset(1060, 392), Offset(1195, 392)], 'dist'),
        ],
        source: const Offset(40, 200),
        sink: const Offset(1195, 392),
        areaLabels: const {
          'INTAKE': Offset(170, 470),
          'TRANSFER': Offset(580, 535),
          'TREATED WATER': Offset(895, 470),
          'DISTRIBUTION': Offset(1110, 470),
        },
      );

  factory DiagramLayout.portrait() => DiagramLayout(
        portrait: true,
        size: const Size(600, 1150),
        tanks: {
          'T-101': const Rect.fromLTRB(190, 175, 410, 360),
          'T-102': const Rect.fromLTRB(180, 655, 420, 860),
        },
        pumps: const {'P-101': Offset(180, 455), 'P-102': Offset(420, 455), 'P-201': Offset(300, 925)},
        valves: const {'XV-101': Offset(300, 88), 'XV-102': Offset(300, 572), 'XV-201': Offset(300, 1000)},
        instruments: const {
          'FT-101': Offset(410, 120),
          'LT-101': Offset(480, 200),
          'PT-101': Offset(420, 545),
          'FT-102': Offset(420, 605),
          'LT-102': Offset(490, 690),
          'PT-201': Offset(420, 915),
          'FT-201': Offset(420, 1060),
        },
        pipes: const [
          DiagramPipe([Offset(300, 25), Offset(300, 177)], 'inlet'),
          DiagramPipe([Offset(300, 360), Offset(300, 400)], 'suction'),
          DiagramPipe([Offset(300, 400), Offset(180, 400), Offset(180, 455), Offset(180, 515), Offset(300, 515)], 'p101'),
          DiagramPipe([Offset(300, 400), Offset(420, 400), Offset(420, 455), Offset(420, 515), Offset(300, 515)], 'p102'),
          DiagramPipe([Offset(300, 515), Offset(300, 657)], 'transfer'),
          DiagramPipe([Offset(300, 860), Offset(300, 925), Offset(300, 1135)], 'dist'),
        ],
        source: const Offset(300, 25),
        sink: const Offset(300, 1135),
        areaLabels: const {
          'INTAKE': Offset(90, 270),
          'TRANSFER': Offset(70, 515),
          'TREATED WATER': Offset(90, 760),
          'DISTRIBUTION': Offset(150, 1090),
        },
      );

  (double, Offset) fit(Size canvas) {
    final s = math.min(canvas.width / size.width, canvas.height / size.height);
    final off = Offset((canvas.width - size.width * s) / 2, (canvas.height - size.height * s) / 2);
    return (s, off);
  }

  String? hitTest(Offset p, Size canvas, Map<String, Equipment> equipment) {
    final (s, off) = fit(canvas);
    final m = (p - off) / s;
    for (final e in tanks.entries) {
      if (e.value.inflate(10).contains(m) && equipment.containsKey(e.key)) return e.key;
    }
    String? best;
    var bestD = 44.0;
    for (final map in [pumps, valves, instruments]) {
      for (final e in map.entries) {
        final d = (e.value - m).distance;
        if (d < bestD && equipment.containsKey(e.key)) {
          bestD = d;
          best = e.key;
        }
      }
    }
    return best;
  }
}

// ---------------------------------------------------------------------------
// Painter
// ---------------------------------------------------------------------------

class _DiagramPainter extends CustomPainter {
  _DiagramPainter({
    required this.layout,
    required this.equipment,
    required this.selectedTag,
    required this.time,
    required this.depth,
  }) : super(repaint: time);

  final DiagramLayout layout;
  final Map<String, Equipment> equipment;
  final String? selectedTag;
  final ValueNotifier<double> time;
  final bool depth;

  double get t => time.value;

  double _flow(String key) {
    double f(String tag) => equipment[tag]?.flow ?? 0;
    return switch (key) {
      'inlet' => f('XV-101'),
      'p101' => f('P-101'),
      'p102' => f('P-102'),
      'suction' => f('P-101') + f('P-102'),
      'transfer' => f('XV-102'),
      'dist' => f('XV-201'),
      _ => 0,
    };
  }

  @override
  void paint(Canvas canvas, Size size) {
    final (s, off) = layout.fit(size);
    canvas.save();
    canvas.translate(off.dx, off.dy);
    canvas.scale(s);

    if (depth) _drawFloor(canvas);
    _drawAreaLabels(canvas);

    final maxFlow = equipment.values.fold<double>(1, (m, e) => math.max(m, e.ratedFlow ?? 0));
    for (final p in layout.pipes) {
      _drawPipe(canvas, p, _flow(p.flowKey), maxFlow);
    }
    _drawSource(canvas);
    _drawSink(canvas);

    for (final e in layout.tanks.entries) {
      final eq = equipment[e.key];
      if (eq != null) _drawTank(canvas, e.value, eq);
    }
    for (final e in layout.pumps.entries) {
      final eq = equipment[e.key];
      if (eq != null) _drawPump(canvas, e.value, eq);
    }
    for (final e in layout.valves.entries) {
      final eq = equipment[e.key];
      if (eq != null) _drawValve(canvas, e.value, eq);
    }
    for (final e in layout.instruments.entries) {
      final eq = equipment[e.key];
      if (eq != null) _drawInstrument(canvas, e.value, eq);
    }
    canvas.restore();
  }

  // Floor / platform for the 3D perspective view.
  void _drawFloor(Canvas canvas) {
    final r = Offset.zero & layout.size;
    final plate = RRect.fromRectAndRadius(r.inflate(18), const Radius.circular(26));
    canvas.drawRRect(plate.shift(const Offset(0, 14)), Paint()..color = Colors.black.withValues(alpha: 0.55)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18));
    canvas.drawRRect(
      plate,
      Paint()
        ..shader = const LinearGradient(colors: [Color(0xFF15202B), Color(0xFF0E151C)], begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(r),
    );
    final grid = Paint()
      ..color = const Color(0xFF1D2A37)
      ..strokeWidth = 1;
    for (double x = 0; x <= layout.size.width; x += 40) {
      canvas.drawLine(Offset(x, -10), Offset(x, layout.size.height + 10), grid);
    }
    for (double y = 0; y <= layout.size.height; y += 40) {
      canvas.drawLine(Offset(-10, y), Offset(layout.size.width + 10, y), grid);
    }
    canvas.drawRRect(plate, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = const Color(0xFF2A3A4A));
  }

  void _drawAreaLabels(Canvas canvas) {
    for (final e in layout.areaLabels.entries) {
      _text(canvas, e.key, e.value, size: 12, color: const Color(0xFF4F6275), weight: FontWeight.w700, letterSpacing: 2.5);
    }
  }

  // -- Pipes -------------------------------------------------------------------

  void _drawPipe(Canvas canvas, DiagramPipe pipe, double flow, double maxFlow) {
    final path = Path()..moveTo(pipe.points.first.dx, pipe.points.first.dy);
    for (final p in pipe.points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    final join = StrokeJoin.round;
    if (depth) {
      canvas.drawPath(path.shift(const Offset(0, 8)), Paint()..style = PaintingStyle.stroke..strokeWidth = 16..strokeJoin = join..color = Colors.black.withValues(alpha: 0.45)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    }
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 16..strokeJoin = join..strokeCap = StrokeCap.round..color = const Color(0xFF1B2530));
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 12..strokeJoin = join..strokeCap = StrokeCap.round..color = const Color(0xFF34424F));

    // Specular highlight (gives the pipe a cylindrical look)
    for (var i = 0; i < pipe.points.length - 1; i++) {
      final a = pipe.points[i], b = pipe.points[i + 1];
      final d = b - a;
      if (d.distance == 0) continue;
      final n = Offset(-d.dy, d.dx) / d.distance;
      canvas.drawLine(a - n * 3, b - n * 3, Paint()..strokeWidth = 2.2..color = const Color(0xFF5E7184));
    }

    final active = flow > 0.5;
    if (!active) return;
    final ratio = (flow / maxFlow).clamp(0.05, 1.0);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeJoin = join
        ..strokeCap = StrokeCap.round
        ..color = AppColors.water.withValues(alpha: 0.35 + 0.3 * ratio),
    );

    // Moving water particles
    final metrics = path.computeMetrics().toList();
    final speed = 25 + 95 * ratio; // model px / s
    const spacing = 22.0;
    final phase = (t * speed) % spacing;
    final particle = Paint()..color = const Color(0xFFBDEBFF);
    final glow = Paint()
      ..color = AppColors.water.withValues(alpha: 0.6)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    var carried = 0.0;
    for (final m in metrics) {
      for (double d = (phase - carried) % spacing; d < m.length; d += spacing) {
        final pos = m.getTangentForOffset(d)?.position;
        if (pos == null) continue;
        canvas.drawCircle(pos, 3.6, glow);
        canvas.drawCircle(pos, 2.2, particle);
      }
      carried += m.length;
    }

    // Direction chevron at the middle of the longest segment
    final longest = metrics.isEmpty ? null : metrics.reduce((a, b) => a.length > b.length ? a : b);
    final tan = longest?.getTangentForOffset(longest.length / 2);
    if (tan != null) {
      canvas.save();
      canvas.translate(tan.position.dx, tan.position.dy);
      canvas.rotate(-tan.angle);
      final chevron = Path()
        ..moveTo(-4, -5)
        ..lineTo(3, 0)
        ..lineTo(-4, 5);
      canvas.drawPath(chevron, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.2..color = Colors.white.withValues(alpha: 0.8)..strokeCap = StrokeCap.round);
      canvas.restore();
    }
  }

  void _drawSource(Canvas canvas) {
    final c = layout.source;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..color = AppColors.water
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final y = c.dy - 34 + i * 7.0;
      final wave = Path()..moveTo(c.dx - 22, y);
      for (double x = -22; x <= 22; x += 2) {
        wave.lineTo(c.dx + x, y + math.sin((x / 6) + t * 3 + i) * 2.2);
      }
      canvas.drawPath(wave, p);
    }
    _text(canvas, layout.portrait ? 'River intake' : 'River\nintake', layout.portrait ? c.translate(-80, 0) : c.translate(0, 34), size: 11, color: AppColors.textMuted);
  }

  void _drawSink(Canvas canvas) {
    final c = layout.sink;
    final arrow = Path();
    if (layout.portrait) {
      arrow
        ..moveTo(c.dx - 10, c.dy - 6)
        ..lineTo(c.dx, c.dy + 6)
        ..lineTo(c.dx + 10, c.dy - 6);
    } else {
      arrow
        ..moveTo(c.dx - 6, c.dy - 10)
        ..lineTo(c.dx + 6, c.dy)
        ..lineTo(c.dx - 6, c.dy + 10);
    }
    canvas.drawPath(arrow, Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = AppColors.water..strokeCap = StrokeCap.round);
    _text(canvas, 'To distribution\nnetwork', layout.portrait ? c.translate(-90, -10) : c.translate(-30, 40), size: 11, color: AppColors.textMuted);
  }

  // -- Tanks ---------------------------------------------------------------------

  void _drawTank(Canvas canvas, Rect r, Equipment e) {
    final level = ((e.levelPct ?? 0) / 100).clamp(0.0, 1.0);
    final ellH = r.width * 0.2;
    final top = r.top + ellH / 2;
    final bottom = r.bottom - ellH / 2;
    final body = Rect.fromLTRB(r.left, top, r.right, bottom);
    final status = e.actualState;
    final selected = selectedTag == e.tag;

    if (depth) {
      canvas.drawOval(Rect.fromCenter(center: Offset(r.center.dx + 8, r.bottom + 6), width: r.width * 1.15, height: ellH * 1.1),
          Paint()..color = Colors.black.withValues(alpha: 0.55)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    }

    // Interior (back wall)
    canvas.drawRect(body, Paint()..shader = const LinearGradient(colors: [Color(0xFF0D141B), Color(0xFF17212B), Color(0xFF0D141B)]).createShader(body));
    canvas.drawOval(Rect.fromCenter(center: Offset(r.center.dx, bottom), width: r.width, height: ellH), Paint()..color = const Color(0xFF0D141B));

    // Water column with an animated surface
    if (level > 0.002) {
      final waterTop = bottom - (bottom - top) * level;
      final waterRect = Rect.fromLTRB(r.left + 3, waterTop, r.right - 3, bottom);
      canvas.drawRect(
        waterRect,
        Paint()..shader = LinearGradient(colors: [AppColors.water.withValues(alpha: 0.85), AppColors.waterDeep.withValues(alpha: 0.95)], begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(waterRect),
      );
      canvas.drawOval(Rect.fromCenter(center: Offset(r.center.dx, bottom), width: r.width - 6, height: ellH - 4), Paint()..color = AppColors.waterDeep);
      final surface = Rect.fromCenter(center: Offset(r.center.dx, waterTop), width: r.width - 6, height: ellH - 4);
      canvas.drawOval(surface, Paint()..color = const Color(0xFF7DD3FC).withValues(alpha: 0.85));
      // ripples
      canvas.save();
      canvas.clipPath(Path()..addOval(surface));
      final ripple = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: 0.35);
      for (var i = 0; i < 3; i++) {
        final k = ((t * 0.35 + i / 3) % 1.0);
        canvas.drawOval(Rect.fromCenter(center: surface.center, width: surface.width * k, height: surface.height * k), ripple..color = Colors.white.withValues(alpha: 0.35 * (1 - k)));
      }
      canvas.restore();
    }

    // Glass/metal front shell
    canvas.drawRect(
      body,
      Paint()
        ..shader = LinearGradient(colors: [
          Colors.white.withValues(alpha: 0.10),
          Colors.white.withValues(alpha: 0.02),
          Colors.white.withValues(alpha: 0.16),
          Colors.white.withValues(alpha: 0.02),
          Colors.black.withValues(alpha: 0.25),
        ], stops: const [0, 0.25, 0.42, 0.6, 1]).createShader(body),
    );
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF5B6B7D);
    canvas.drawLine(body.topLeft, body.bottomLeft, outline);
    canvas.drawLine(body.topRight, body.bottomRight, outline);
    canvas.drawArc(Rect.fromCenter(center: Offset(r.center.dx, bottom), width: r.width, height: ellH), 0, math.pi, false, outline);
    // Roof
    final roof = Rect.fromCenter(center: Offset(r.center.dx, top), width: r.width, height: ellH);
    canvas.drawOval(roof, Paint()..shader = const LinearGradient(colors: [Color(0xFF3E4D5D), Color(0xFF26313D)]).createShader(roof));
    canvas.drawOval(roof, outline);
    canvas.drawRect(Rect.fromCenter(center: Offset(r.center.dx, top - 4), width: 22, height: 8), Paint()..color = const Color(0xFF4A5A6B));

    // Level scale + alarm marks
    final scale = Paint()
      ..color = const Color(0xFF6B7D90)
      ..strokeWidth = 1;
    for (var i = 0; i <= 10; i++) {
      final y = bottom - (bottom - top) * i / 10;
      canvas.drawLine(Offset(r.right + 4, y), Offset(r.right + (i % 5 == 0 ? 12 : 8), y), scale);
    }
    for (final (pct, color) in [(0.95, AppColors.fault), (0.10, AppColors.warning)]) {
      final y = bottom - (bottom - top) * pct;
      canvas.drawLine(Offset(r.right + 2, y), Offset(r.right + 14, y), Paint()..color = color..strokeWidth = 2);
    }

    // Status / selection ring
    final ringColor = switch (status) {
      'overflow' || 'empty' => AppColors.fault,
      'high' || 'low' => AppColors.warning,
      _ => null,
    };
    if (ringColor != null || selected) {
      final rr = RRect.fromRectAndRadius(r.inflate(8), const Radius.circular(14));
      final pulse = 0.55 + 0.45 * math.sin(t * 4).abs();
      canvas.drawRRect(rr, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.5..color = (ringColor ?? AppColors.primary).withValues(alpha: ringColor != null ? pulse : 0.9));
    }

    // Labels
    _text(canvas, e.tag, Offset(r.center.dx, r.top - 26), size: 15, weight: FontWeight.w800);
    _text(canvas, e.name, Offset(r.center.dx, r.top - 10), size: 11, color: AppColors.textMuted);
    _pill(canvas, '${(e.levelPct ?? 0).toStringAsFixed(1)} %', Offset(r.center.dx, r.center.dy - 6), size: 20);
    _text(canvas, '${(e.volumeM3 ?? 0).toStringAsFixed(0)} / ${(e.capacityM3 ?? 0).toStringAsFixed(0)} m³', Offset(r.center.dx, r.center.dy + 22), size: 11, color: Colors.white.withValues(alpha: 0.85));
    if (status != 'normal') {
      _text(canvas, stateLabel(status).toUpperCase(), Offset(r.center.dx, r.bottom + 18), size: 11, weight: FontWeight.w800, color: stateColor(status));
    }
  }

  // -- Pumps ---------------------------------------------------------------------

  void _drawPump(Canvas canvas, Offset c, Equipment e) {
    const r = 24.0;
    final color = stateColor(e.actualState);
    final running = e.actualState == 'running';

    if (depth) {
      canvas.drawOval(Rect.fromCenter(center: c.translate(6, r + 14), width: r * 2.6, height: 14), Paint()..color = Colors.black.withValues(alpha: 0.5)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    }
    // Base plate & motor
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c.translate(0, r + 4), width: r * 2.4, height: 10), const Radius.circular(3)), Paint()..color = const Color(0xFF2B3744));
    final motor = Rect.fromCenter(center: c.translate(r + 16, 0), width: 26, height: 22);
    canvas.drawRRect(RRect.fromRectAndRadius(motor, const Radius.circular(4)),
        Paint()..shader = const LinearGradient(colors: [Color(0xFF4F6070), Color(0xFF263039)], begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(motor));
    for (var i = 0; i < 4; i++) {
      canvas.drawLine(Offset(motor.left + 5 + i * 5.0, motor.top + 3), Offset(motor.left + 5 + i * 5.0, motor.bottom - 3), Paint()..color = const Color(0xFF1B232B)..strokeWidth = 1.4);
    }

    // Casing
    canvas.drawCircle(c, r, Paint()..shader = const RadialGradient(colors: [Color(0xFF5E6F80), Color(0xFF222C36)], center: Alignment(-0.35, -0.4)).createShader(Rect.fromCircle(center: c, radius: r)));
    if (running) {
      canvas.drawCircle(c, r + 4, Paint()..color = color.withValues(alpha: 0.25 + 0.15 * math.sin(t * 5))..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    }
    canvas.drawCircle(c, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 3.4..color = color);

    // Impeller
    final angle = running ? t * 9 : 0.3;
    final blade = Paint()
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: running ? 0.9 : 0.45);
    for (var i = 0; i < 5; i++) {
      final a = angle + i * 2 * math.pi / 5;
      final p1 = c + Offset(math.cos(a), math.sin(a)) * 5;
      final p2 = c + Offset(math.cos(a + 0.5), math.sin(a + 0.5)) * 15;
      canvas.drawLine(p1, p2, blade);
    }
    canvas.drawCircle(c, 4, Paint()..color = const Color(0xFFDDE6EE));

    _badges(canvas, c, e, r);
    if (selectedTag == e.tag) {
      canvas.drawCircle(c, r + 9, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.4..color = AppColors.primary);
    }
    final below = c.dy + r + 22;
    _text(canvas, e.tag, Offset(c.dx, below), size: 13, weight: FontWeight.w800);
    _text(canvas, stateLabel(e.actualState), Offset(c.dx, below + 15), size: 11, weight: FontWeight.w700, color: color);
    if (running) _text(canvas, '${(e.flow ?? 0).toStringAsFixed(0)} m³/h', Offset(c.dx, below + 29), size: 10, color: AppColors.textMuted);
  }

  // -- Valves --------------------------------------------------------------------

  void _drawValve(Canvas canvas, Offset c, Equipment e) {
    const s = 17.0;
    final color = stateColor(e.actualState);
    final pos = ((e.positionPct ?? 0) / 100).clamp(0.0, 1.0);
    final moving = e.actualState == 'opening' || e.actualState == 'closing';
    final vertical = layout.portrait;

    canvas.save();
    canvas.translate(c.dx, c.dy);
    if (vertical) canvas.rotate(math.pi / 2);

    final left = Path()
      ..moveTo(-s, -s * 0.75)
      ..lineTo(-s, s * 0.75)
      ..lineTo(0, 0)
      ..close();
    final right = Path()
      ..moveTo(s, -s * 0.75)
      ..lineTo(s, s * 0.75)
      ..lineTo(0, 0)
      ..close();
    final fillAlpha = moving ? (0.4 + 0.5 * (math.sin(t * 8) * 0.5 + 0.5)) : (0.25 + 0.7 * pos);
    final fill = Paint()..color = Color.lerp(const Color(0xFF2B3542), color, pos == 0 && !moving ? 0.25 : 1)!.withValues(alpha: fillAlpha);
    canvas.drawPath(left, fill);
    canvas.drawPath(right, fill);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = color
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(left, stroke);
    canvas.drawPath(right, stroke);
    canvas.restore();

    // Actuator (always drawn upright)
    final stemTop = c.translate(0, -s - 10);
    canvas.drawLine(c, stemTop, Paint()..strokeWidth = 2.4..color = const Color(0xFF8899AA));
    final act = Rect.fromCenter(center: stemTop.translate(0, -5), width: 24, height: 12);
    canvas.drawRRect(RRect.fromRectAndRadius(act, const Radius.circular(3)), Paint()..color = const Color(0xFF3B4957));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(act.left + 2, act.top + 2, (act.width - 4) * pos, act.height - 4), const Radius.circular(2)), Paint()..color = color.withValues(alpha: 0.9));

    _badges(canvas, c, e, s + 4);
    if (selectedTag == e.tag) {
      canvas.drawCircle(c.translate(0, -6), s + 14, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.4..color = AppColors.primary);
    }
    final below = c.dy + s + (vertical ? 24 : 14);
    final labelX = vertical ? c.dx - 70 : c.dx;
    final labelY = vertical ? c.dy - 8 : below;
    _text(canvas, e.tag, Offset(labelX, labelY), size: 13, weight: FontWeight.w800);
    _text(canvas, '${stateLabel(e.actualState)} · ${(e.positionPct ?? 0).toStringAsFixed(0)}%', Offset(labelX, labelY + 15), size: 11, weight: FontWeight.w700, color: color);
  }

  // -- Instruments ----------------------------------------------------------------

  void _drawInstrument(Canvas canvas, Offset c, Equipment e) {
    const r = 15.0;
    final selected = selectedTag == e.tag;
    canvas.drawCircle(c, r, Paint()..color = AppColors.surfaceHigh);
    canvas.drawCircle(c, r, Paint()..style = PaintingStyle.stroke..strokeWidth = selected ? 2.6 : 1.6..color = selected ? AppColors.primary : const Color(0xFF7FA6C6));
    canvas.drawLine(c.translate(-r, 0), c.translate(r, 0), Paint()..color = const Color(0xFF7FA6C6)..strokeWidth = 1);
    final parts = e.tag.split('-');
    _text(canvas, parts.first, c.translate(0, -6), size: 9, weight: FontWeight.w800, color: const Color(0xFFB8D4EA));
    _text(canvas, parts.length > 1 ? parts[1] : '', c.translate(0, 6), size: 9, color: const Color(0xFFB8D4EA));
    final v = e.value ?? 0;
    final txt = e.unit == 'bar' ? '${v.toStringAsFixed(2)} bar' : '${v.toStringAsFixed(e.unit == '%' ? 1 : 0)} ${e.unit ?? ''}';
    _pill(canvas, txt, c.translate(0, r + 13), size: 11, bg: const Color(0xFF0B1118));
  }

  // -- Shared decorations ----------------------------------------------------------

  void _badges(Canvas canvas, Offset c, Equipment e, double r) {
    if (e.controlMode != null) {
      final b = c.translate(-r - 6, -r - 4);
      final auto = e.isAuto;
      canvas.drawCircle(b, 9, Paint()..color = auto ? AppColors.secondary : AppColors.warning);
      _text(canvas, auto ? 'A' : 'M', b, size: 10, weight: FontWeight.w900, color: const Color(0xFF0B0F14));
    }
    if (e.inMaintenance) {
      final b = c.translate(r + 6, -r - 4);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: b, width: 34, height: 16), const Radius.circular(4)), Paint()..color = AppColors.lockout);
      _text(canvas, 'LOTO', b, size: 9, weight: FontWeight.w900, color: const Color(0xFF1B0B2B));
    } else if (e.hasMismatch) {
      final b = c.translate(r + 4, -r - 4);
      final tri = Path()
        ..moveTo(b.dx, b.dy - 9)
        ..lineTo(b.dx + 9, b.dy + 7)
        ..lineTo(b.dx - 9, b.dy + 7)
        ..close();
      canvas.drawPath(tri, Paint()..color = AppColors.warning);
      _text(canvas, '!', b.translate(0, 1), size: 11, weight: FontWeight.w900, color: const Color(0xFF1A1200));
    }
  }

  void _pill(Canvas canvas, String text, Offset center, {double size = 12, Color bg = const Color(0xCC0B1118)}) {
    final tp = _layout(text, size: size, weight: FontWeight.w800);
    final rect = Rect.fromCenter(center: center, width: tp.width + 14, height: tp.height + 6);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)), Paint()..color = bg);
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  void _text(Canvas canvas, String text, Offset center,
      {double size = 12, Color color = Colors.white, FontWeight weight = FontWeight.w500, double letterSpacing = 0}) {
    final tp = _layout(text, size: size, color: color, weight: weight, letterSpacing: letterSpacing);
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  TextPainter _layout(String text, {double size = 12, Color color = Colors.white, FontWeight weight = FontWeight.w500, double letterSpacing = 0}) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: size, color: color, fontWeight: weight, letterSpacing: letterSpacing, height: 1.15, fontFeatures: const [FontFeature.tabularFigures()]),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
  }

  @override
  bool shouldRepaint(covariant _DiagramPainter old) =>
      old.equipment != equipment || old.selectedTag != selectedTag || old.depth != depth || old.layout.portrait != layout.portrait;
}
