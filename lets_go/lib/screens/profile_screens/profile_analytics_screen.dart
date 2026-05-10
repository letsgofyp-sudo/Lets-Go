import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';

import '../../controllers/profile/profile_analytics_controller.dart';

class _DailyPoint {
  final String? dayIso;
  final double value;

  const _DailyPoint({required this.dayIso, required this.value});
}

class ProfileAnalyticsScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const ProfileAnalyticsScreen({
    super.key,
    required this.userData,
  });

  @override
  State<ProfileAnalyticsScreen> createState() => _ProfileAnalyticsScreenState();
}

class _ProfileAnalyticsScreenState extends State<ProfileAnalyticsScreen> with AutomaticKeepAliveClientMixin {
  late ProfileAnalyticsController _controller;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _controller = ProfileAnalyticsController(
      initialUser: widget.userData,
      onStateChanged: () {
        if (!mounted) return;
        setState(() {});
      },
      onError: (msg) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.load();
    });
  }

  String _money(int v) => 'Rs. $v';

  String _num(dynamic v, {int digits = 1}) {
    if (v is num) return v.toStringAsFixed(digits);
    final dv = double.tryParse(v?.toString() ?? '');
    if (dv == null) return '0.0';
    return dv.toStringAsFixed(digits);
  }

  String _pct(int numerator, int denominator) {
    if (denominator <= 0) return '0%';
    final p = (numerator / denominator) * 100.0;
    return '${p.toStringAsFixed(0)}%';
  }

  Widget _windowChip({required String label, required int? value}) {
    final selected = _controller.windowDays == value;
    final scheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
        ),
      ),
      selected: selected,
      onSelected: (_) => _controller.setWindowDays(value),
      selectedColor: scheme.primaryContainer,
      backgroundColor: scheme.surfaceContainerHighest,
      checkmarkColor: scheme.onPrimaryContainer,
    );
  }

  String _fmtDay(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso);
      const months = <String>[
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      final m = (dt.month >= 1 && dt.month <= 12) ? months[dt.month - 1] : dt.month.toString();
      return '${dt.day.toString().padLeft(2, '0')} $m';
    } catch (_) {
      return iso;
    }
  }

  String _fmtMonthYear(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso);
      const months = <String>[
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      final m = (dt.month >= 1 && dt.month <= 12) ? months[dt.month - 1] : dt.month.toString();
      return '$m\n${dt.year}';
    } catch (_) {
      return iso;
    }
  }

  List<_DailyPoint> _pointsFromDaily(List<dynamic> rows, String key) {
    final out = <_DailyPoint>[];
    for (final r in rows) {
      if (r is Map) {
        final v = r[key];
        final dv = (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '');
        if (dv != null) {
          out.add(_DailyPoint(dayIso: r['day']?.toString(), value: dv));
        }
      }
    }
    return out;
  }

  Widget _lineChart({
    required List<_DailyPoint> points,
    required Color color,
    required String unitPrefix,
  }) {
    final scheme = Theme.of(context).colorScheme;

    final normalizedPoints = points.isEmpty ? <_DailyPoint>[const _DailyPoint(dayIso: null, value: 0.0)] : points;
    final spots = <FlSpot>[];
    for (int i = 0; i < normalizedPoints.length; i++) {
      spots.add(FlSpot(i.toDouble(), normalizedPoints[i].value));
    }

    final minV = normalizedPoints.map((e) => e.value).reduce(math.min);
    final maxV = normalizedPoints.map((e) => e.value).reduce(math.max);
    final minY = math.min(0.0, minV);
    final maxY = (maxV == minV) ? (maxV + 1.0) : maxV;
    final yRange = (maxY - minY).abs();
    final yInterval = (yRange <= 2.0) ? 1.0 : (yRange / 2.0).clamp(1.0, double.infinity);

    String fmt(double v) => '$unitPrefix${v.toStringAsFixed(0)}';
    final xInterval = (normalizedPoints.length <= 9)
        ? 1.0
        : (normalizedPoints.length / 6).ceil().toDouble().clamp(1.0, double.infinity);

    return SizedBox(
      width: double.infinity,
      height: 140,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (normalizedPoints.length - 1).toDouble(),
          minY: minY,
          maxY: maxY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: yInterval,
            getDrawingHorizontalLine: (value) => FlLine(
              color: scheme.outline.withValues(alpha: 0.18),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border(
              bottom: BorderSide(color: scheme.outline.withValues(alpha: 0.22)),
              left: BorderSide(color: scheme.outline.withValues(alpha: 0.22)),
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: normalizedPoints.length > 1,
                reservedSize: 46,
                interval: xInterval,
                getTitlesWidget: (value, meta) {
                  final i = value.round();
                  if (i < 0 || i >= normalizedPoints.length) return const SizedBox.shrink();

                  final label = _fmtMonthYear(normalizedPoints[i].dayIso);
                  if (label.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w800, fontSize: 10),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 60,
                interval: yInterval,
                getTitlesWidget: (value, meta) {
                  return Text(
                    fmt(value),
                    style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700, fontSize: 10),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => scheme.surface,
              tooltipBorder: BorderSide(color: scheme.outlineVariant),
              tooltipBorderRadius: BorderRadius.circular(10),
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((s) {
                  final idx = s.x.round();
                  final dayLabel = (idx >= 0 && idx < normalizedPoints.length)
                      ? _fmtDay(normalizedPoints[idx].dayIso)
                      : '';
                  return LineTooltipItem(
                    '${dayLabel.isEmpty ? 'Day' : dayLabel}\n${fmt(s.y)}',
                    TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w900),
                  );
                }).toList();
              },
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: false,
              color: scheme.onSurface,
              barWidth: 4,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: 6.0,
                    color: scheme.onSurface,
                    strokeWidth: 2.5,
                    strokeColor: scheme.surface,
                  );
                },
              ),
              belowBarData: BarAreaData(
                show: false,
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  Widget _metricCard({
    required IconData icon,
    required String title,
    required String value,
    String? subtitle,
    Color? color,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.primary;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: c),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    final bg = Theme.of(context).scaffoldBackgroundColor;

    final a = _controller.analytics;
    final err = _controller.errorMessage;

    final createdTotal = int.tryParse((a['created_total'] ?? 0).toString()) ?? 0;
    final createdCompleted = int.tryParse((a['created_completed'] ?? 0).toString()) ?? 0;
    final createdCancelled = int.tryParse((a['created_cancelled'] ?? 0).toString()) ?? 0;
    final createdBookings = int.tryParse((a['created_total_bookings'] ?? 0).toString()) ?? 0;
    final createdDistance = a['created_distance_km'];

    final revenue = int.tryParse((a['revenue_earned'] ?? 0).toString()) ?? 0;
    final avgEarn = double.tryParse((a['avg_earning_per_ride'] ?? 0).toString()) ?? 0.0;

    final bookedTotal = int.tryParse((a['booked_total'] ?? 0).toString()) ?? 0;
    final bookedCompleted = int.tryParse((a['booked_completed'] ?? 0).toString()) ?? 0;
    final spent = int.tryParse((a['spent_total'] ?? 0).toString()) ?? 0;
    final avgSpend = double.tryParse((a['avg_spend_per_booking'] ?? 0).toString()) ?? 0.0;

    final sampleSizeBooked = int.tryParse((a['sample_size_booked'] ?? 0).toString()) ?? 0;

    final driverByDay = (a['driver_by_day'] is List) ? (a['driver_by_day'] as List) : const [];
    final passengerByDay = (a['passenger_by_day'] is List) ? (a['passenger_by_day'] as List) : const [];
    final driverRevenuePoints = _pointsFromDaily(driverByDay, 'revenue');
    final passengerSpentPoints = _pointsFromDaily(passengerByDay, 'spent');

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Analytics',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ),
        backgroundColor: const Color(0xFF00897B),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => _controller.load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _controller.load(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_controller.isLoading) ...[
              const SizedBox(height: 160),
              const Center(child: CircularProgressIndicator()),
            ] else if (err != null && err.isNotEmpty) ...[
              Text(err, style: TextStyle(color: scheme.error, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => _controller.load(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ] else ...[
              Text(
                'Based on your archived ride history.',
                style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _windowChip(label: 'All-time', value: null),
                  _windowChip(label: 'Last 30 days', value: 30),
                  _windowChip(label: 'Last 7 days', value: 7),
                ],
              ),
              const SizedBox(height: 14),
              if (_controller.isDriver) ...[
                Text('Driver summary', style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                _metricCard(
                  icon: Icons.directions_car_filled,
                  title: 'Created rides',
                  value: createdTotal.toString(),
                  subtitle:
                      'Completed: $createdCompleted (${_pct(createdCompleted, createdTotal)})  Cancelled: $createdCancelled',
                  color: scheme.primary,
                ),
                _metricCard(
                  icon: Icons.groups_2,
                  title: 'Total bookings on your rides',
                  value: createdBookings.toString(),
                  subtitle:
                      'Avg per ride: ${(createdTotal > 0 ? (createdBookings / createdTotal) : 0.0).toStringAsFixed(1)}',
                  color: scheme.secondary,
                ),
                _metricCard(
                  icon: Icons.payments_outlined,
                  title: 'Estimated revenue earned',
                  value: _money(revenue),
                  subtitle:
                      'Avg per ride: ${_money(avgEarn.round())}  Avg per booking: ${_money((createdBookings > 0 ? (revenue / createdBookings) : 0).round())}',
                  color: scheme.tertiary,
                ),
                _metricCard(
                  icon: Icons.straighten,
                  title: 'Total distance (created rides)',
                  value: '${_num(createdDistance, digits: 1)} km',
                  subtitle:
                      'Avg per ride: ${(createdTotal > 0 ? (double.tryParse(_num(createdDistance, digits: 3)) ?? 0.0) / createdTotal : 0.0).toStringAsFixed(2)} km',
                  color: scheme.secondary,
                ),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: scheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Revenue trend', style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 10),
                        _lineChart(points: driverRevenuePoints, color: scheme.tertiary, unitPrefix: 'Rs. '),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
              ],
              Text('Passenger summary', style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              _metricCard(
                icon: Icons.event_seat,
                title: 'Booked rides',
                value: bookedTotal.toString(),
                subtitle: 'Completed: $bookedCompleted (${_pct(bookedCompleted, bookedTotal)})',
                color: scheme.primary,
              ),
              _metricCard(
                icon: Icons.receipt_long,
                title: 'Total spent',
                value: _money(spent),
                subtitle: 'Avg per booking: ${_money(avgSpend.round())}  Sample: $sampleSizeBooked',
                color: scheme.secondary,
              ),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: scheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Spending trend', style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 10),
                      _lineChart(points: passengerSpentPoints, color: scheme.secondary, unitPrefix: 'Rs. '),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: scheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Notes', style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 6),
                      Text(
                        'Rides may take a little time to appear here.',
                        style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}


