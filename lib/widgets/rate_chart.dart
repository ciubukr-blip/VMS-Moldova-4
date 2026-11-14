import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/format.dart';
import '../theme/app_theme.dart';

/// Înălțimea graficelor pe ecranul Dobânzi: o secțiune întreagă (BT sau OS)
/// încape pe un singur ecran de telefon.
const double kRatesChartHeight = 190;

/// Un punct al graficului de rate: data licitației/emiterii și rata (%).
class RatePoint {
  final DateTime date;
  final double rate;
  const RatePoint(this.date, this.rate);
}

class RateSeries {
  final Color color;
  final List<RatePoint> points; // sortate după dată
  const RateSeries(this.color, this.points);
}

/// Axa X în „ani fracționari”, cu lunile egale: 1 ianuarie = an întreg, 1 iulie = an + 0,5.
/// Astfel etichetele anilor și ale lunilor cad exact la începutul perioadei.
double yearFrac(DateTime d) => d.year + (d.month - 1 + (d.day - 1) / DateUtils.getDaysInMonth(d.year, d.month)) / 12;

/// Grafic de rate cu deplasare (stânga–dreapta) și zoom (ciupire cu două degete, butoane +/−).
///
/// * micșorat la maxim: toți anii, etichete scurte („09”, „10” …) care nu se suprapun;
/// * mărit: etichete pe semestre, trimestre și luni; axa Y se adaptează perioadei vizibile;
/// * mărit suficient (o singură serie): procentele apar lângă puncte, cât timp încap fără suprapunere.
class ZoomableRateChart extends StatefulWidget {
  final List<RateSeries> series;
  final double height;
  const ZoomableRateChart({super.key, required this.series, this.height = 240});

  @override
  State<ZoomableRateChart> createState() => _ZoomableRateChartState();
}

class _ZoomableRateChartState extends State<ZoomableRateChart> {
  static const _leftReserved = 34.0;
  static const _labelGapPx = 40.0; // distanța minimă între două procente afișate
  static const _labelsBelowYears = 2.6; // procentele apar când se văd cel mult ~2,5 ani

  final _ctl = TransformationController();
  Timer? _settle;
  double _plotWidth = 300;
  int _scaleStep = 0; // scara cuantizată (reconstruim doar la schimbări vizibile)
  double _visStart = 0, _visEnd = 1; // fracțiunea vizibilă din axa X (pentru axa Y)

  @override
  void initState() {
    super.initState();
    _ctl.addListener(_onTransform);
  }

  @override
  void dispose() {
    _settle?.cancel();
    _ctl.removeListener(_onTransform);
    _ctl.dispose();
    super.dispose();
  }

  double get _scale => _ctl.value.entry(0, 0);

  (double, double) _visible() {
    final s = _scale;
    final tx = _ctl.value.entry(0, 3);
    final start = (-tx / (s * _plotWidth)).clamp(0.0, 1.0);
    return (start, math.min(1.0, start + 1 / s));
  }

  void _onTransform() {
    final step = (math.log(math.max(1.0, _scale)) / math.log(1.12)).round();
    if (step != _scaleStep) {
      setState(() => _scaleStep = step);
    }
    // axa Y se ajustează după ce degetul s-a oprit
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      final (a, b) = _visible();
      if ((a - _visStart).abs() > 0.002 || (b - _visEnd).abs() > 0.002) {
        setState(() {
          _visStart = a;
          _visEnd = b;
        });
      }
    });
  }

  double get _maxScale {
    final (minX, maxX) = _xRange();
    return math.max(1.0, (maxX - minX) / 0.25); // cel mult ~3 luni pe ecran
  }

  /// Zoom programatic în jurul centrului vizibil.
  void _zoomBy(double factor) {
    final s0 = _scale;
    final s = (s0 * factor).clamp(1.0, _maxScale);
    final (a, b) = _visible();
    final center = (a + b) / 2;
    _setView(s, center);
  }

  void _setView(double s, double centerFrac) {
    final w = _plotWidth;
    var tx = -(centerFrac * w * s - w / 2);
    tx = tx.clamp(w - w * s, 0.0);
    _ctl.value = Matrix4.diagonal3Values(s, 1.0, 1.0)..setTranslationRaw(tx, 0.0, 0.0);
  }

  (double, double) _xRange() {
    var lo = double.infinity, hi = -double.infinity;
    for (final s in widget.series) {
      for (final p in s.points) {
        final x = yearFrac(p.date);
        lo = math.min(lo, x);
        hi = math.max(hi, x);
      }
    }
    if (!lo.isFinite) return (0, 1);
    if (hi - lo < 1 / 24) hi = lo + 1 / 24;
    return (lo, hi);
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.series.where((s) => s.points.isNotEmpty).toList();
    if (series.isEmpty) {
      return SizedBox(
          height: widget.height,
          child: const Center(child: Text('Nu există date pentru selecție.', style: TextStyle(color: AppColors.textMuted))));
    }
    final zoomed = _scale > 1.01;
    return Column(children: [
      SizedBox(
        height: widget.height,
        child: LayoutBuilder(builder: (context, c) {
          _plotWidth = math.max(50.0, c.maxWidth - _leftReserved);
          return _chart(series);
        }),
      ),
      const SizedBox(height: 4),
      Row(children: [
        const Expanded(
          child: Text('Trage stânga–dreapta · ciupește cu două degete pentru zoom',
              style: TextStyle(fontSize: 10.5, color: AppColors.textFaint)),
        ),
        _iconBtn(Icons.remove, zoomed ? () => _zoomBy(1 / 1.8) : null),
        _iconBtn(Icons.add, _scale < _maxScale - 0.01 ? () => _zoomBy(1.8) : null),
        _iconBtn(Icons.fullscreen_exit, zoomed ? () => _ctl.value = Matrix4.identity() : null, tooltip: 'Toți anii'),
      ]),
    ]);
  }

  Widget _iconBtn(IconData icon, VoidCallback? onTap, {String? tooltip}) => IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        color: AppColors.primary,
        disabledColor: AppColors.divider,
      );

  Widget _chart(List<RateSeries> series) {
    final (minX, maxX) = _xRange();
    final span = maxX - minX;
    final s = _scale;
    final visYears = span / s;
    final pxPerYear = _plotWidth / visYears;

    // axa Y: doar punctele vizibile (cu o margine), ca evoluția să se vadă și la zoom
    final vLo = minX + _visStart * span - span / s * 0.05, vHi = minX + _visEnd * span + span / s * 0.05;
    final ys = <double>[];
    for (final se in series) {
      for (final p in se.points) {
        final x = yearFrac(p.date);
        if (x >= vLo && x <= vHi) ys.add(p.rate);
      }
    }
    if (ys.isEmpty) ys.addAll(series.expand((e) => e.points).map((p) => p.rate));
    final lo = ys.reduce(math.min), hi = ys.reduce(math.max);
    final range = hi - lo;
    final step = range <= 1.5 ? 0.5 : range <= 3 ? 1.0 : range <= 8 ? 2.0 : range <= 16 ? 4.0 : 5.0;
    final minY = math.max(0.0, ((lo - step * 0.4) / step).floorToDouble() * step);
    var maxY = ((hi + step * 0.6) / step).ceilToDouble() * step;
    if (maxY <= minY) maxY = minY + step;

    // axa X: an întreg / semestru / trimestru / lună, după spațiul disponibil
    final double xInterval;
    var shortYears = false;
    if (pxPerYear >= 12 * 34) {
      xInterval = 1 / 12;
    } else if (pxPerYear >= 4 * 34) {
      xInterval = 1 / 4;
    } else if (pxPerYear >= 2 * 34) {
      xInterval = 1 / 2;
    } else if (pxPerYear >= 34) {
      xInterval = 1;
    } else if (pxPerYear >= 14) {
      xInterval = 1;
      shortYears = true;
    } else {
      xInterval = 2;
      shortYears = true;
    }

    final single = series.length == 1;
    final showLabels = single && visYears <= _labelsBelowYears;
    final gapX = _labelGapPx / pxPerYear;

    final bars = <LineChartBarData>[];
    for (final se in series) {
      final spots = [for (final p in se.points) FlSpot(yearFrac(p.date), p.rate)];
      final labeled = <int>{};
      if (showLabels) {
        var lastX = -double.infinity;
        for (var i = 0; i < spots.length; i++) {
          if (spots[i].x - lastX >= gapX) {
            labeled.add(i);
            lastX = spots[i].x;
          }
        }
      }
      final lastIndex = spots.length - 1;
      bars.add(LineChartBarData(
        spots: spots,
        color: se.color,
        barWidth: 2,
        isCurved: false,
        dotData: FlDotData(
          show: single || showLabels,
          checkToShowDot: (spot, bar) => true,
          getDotPainter: (spot, percent, bar, i) {
            if (labeled.contains(i)) return _LabelDotPainter(se.color, pct(spot.y));
            if (i == lastIndex && single) {
              return FlDotCirclePainter(radius: 3.5, color: se.color, strokeWidth: 2, strokeColor: Colors.white);
            }
            return _NoDot(se.color);
          },
        ),
        belowBarData: BarAreaData(
          show: single,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [se.color.withValues(alpha: 0.14), se.color.withValues(alpha: 0.0)],
          ),
        ),
      ));
    }

    final lastRate = single ? series.first.points.last.rate : null;
    final lastColor = single ? series.first.color : AppColors.primary;

    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        clipData: const FlClipData.all(),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.text,
            tooltipBorderRadius: BorderRadius.circular(10),
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (spots) => spots.map((sp) {
              final d = series[sp.barIndex].points[sp.spotIndex].date;
              final first = sp == spots.first;
              return LineTooltipItem(
                '${first ? '${date(d)}\n' : ''}${pct(sp.y)}',
                TextStyle(color: sp.bar.color ?? Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
              );
            }).toList(),
          ),
        ),
        lineBarsData: bars,
        extraLinesData: ExtraLinesData(horizontalLines: [
          if (lastRate != null && !showLabels)
            HorizontalLine(
              y: lastRate,
              color: lastColor.withValues(alpha: 0.45),
              strokeWidth: 1,
              dashArray: const [3, 4],
              label: HorizontalLineLabel(
                show: true,
                alignment: Alignment.topLeft,
                padding: const EdgeInsets.only(left: 2, bottom: 2),
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: lastColor),
                labelResolver: (l) => 'ultima: ${pct(l.y)}',
              ),
            ),
        ]),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: _leftReserved,
              interval: step,
              minIncluded: false,
              maxIncluded: false,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                meta: meta,
                space: 4,
                child: Text('${step < 1 ? v.toStringAsFixed(1) : v.toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: xInterval,
              minIncluded: false,
              maxIncluded: false,
              getTitlesWidget: (v, meta) {
                final text = _xLabel(v, xInterval, shortYears);
                if (text == null) return const SizedBox.shrink();
                final isYear = !text.contains(RegExp(r'[a-z]'));
                return SideTitleWidget(
                  meta: meta,
                  space: 5,
                  child: Text(text,
                      style: TextStyle(
                        fontSize: shortYears ? 8.5 : 10,
                        fontWeight: isYear && xInterval < 1 ? FontWeight.w600 : FontWeight.w400,
                        color: isYear && xInterval < 1 ? AppColors.text : AppColors.textMuted,
                      )),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: xInterval < 1,
          verticalInterval: xInterval < 1 ? 1 : null,
          horizontalInterval: step,
          getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.divider, strokeWidth: 1),
          getDrawingVerticalLine: (_) => const FlLine(color: AppColors.divider, strokeWidth: 1, dashArray: [2, 3]),
        ),
      ),
      duration: const Duration(milliseconds: 200),
      transformationConfig: FlTransformationConfig(
        scaleAxis: FlScaleAxis.horizontal,
        minScale: 1,
        maxScale: _maxScale,
        transformationController: _ctl,
      ),
    );
  }

  /// Eticheta axei X: „2015” la început de an, apoi „apr”, „iul” …; „09” când sunt mulți ani.
  static String? _xLabel(double v, double interval, bool short) {
    final k = v / interval;
    if ((k - k.round()).abs() > 1e-6) return null; // doar valorile aliniate
    var year = v.floor();
    var month = ((v - year) * 12).round();
    if (month == 12) {
      year += 1;
      month = 0;
    }
    if (month == 0) return short ? (year % 100).toString().padLeft(2, '0') : '$year';
    return shortMonth(DateTime(year, month + 1));
  }
}

/// Punct mic + procentul deasupra (sub, dacă e prea aproape de marginea de sus).
class _LabelDotPainter extends FlDotPainter {
  final Color color;
  final String text;
  const _LabelDotPainter(this.color, this.text);

  @override
  void draw(Canvas canvas, FlSpot spot, Offset offsetInCanvas) {
    canvas.drawCircle(offsetInCanvas, 3, Paint()..color = Colors.white);
    canvas.drawCircle(offsetInCanvas, 2.2, Paint()..color = color);
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    final above = offsetInCanvas.dy - tp.height - 5 >= 0;
    final pos = Offset(offsetInCanvas.dx - tp.width / 2, above ? offsetInCanvas.dy - tp.height - 5 : offsetInCanvas.dy + 5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(pos.dx - 2, pos.dy - 1, tp.width + 4, tp.height + 2), const Radius.circular(3)),
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );
    tp.paint(canvas, pos);
  }

  @override
  Size getSize(FlSpot spot) => const Size(6, 6);

  @override
  Color get mainColor => color;

  @override
  FlDotPainter lerp(FlDotPainter a, FlDotPainter b, double t) => b;

  @override
  List<Object?> get props => [color, text];
}

/// Punct invizibil (păstrează atingerea pentru tooltip, fără desen).
class _NoDot extends FlDotPainter {
  final Color color;
  const _NoDot(this.color);

  @override
  void draw(Canvas canvas, FlSpot spot, Offset offsetInCanvas) {}

  @override
  Size getSize(FlSpot spot) => Size.zero;

  @override
  Color get mainColor => color;

  @override
  FlDotPainter lerp(FlDotPainter a, FlDotPainter b, double t) => b;

  @override
  List<Object?> get props => [color];
}
