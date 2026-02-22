import 'package:flutter/material.dart';
import '../services/websocket_service.dart';
import '../theme.dart';

class RouteStopsSheet extends StatelessWidget {
  final String busId;
  final String routeName;
  final List<BusStop> stops;
  final int currentStopIdx; // -1 = before first stop
  final String busStatus;
  final VoidCallback onClose;

  const RouteStopsSheet({
    super.key,
    required this.busId,
    required this.routeName,
    required this.stops,
    required this.currentStopIdx,
    required this.busStatus,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.handleBar,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
            child: Row(
              children: [
                GestureDetector(
                  onTap: onClose,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.arrow_back_rounded,
                        color: AppColors.textSubtle, size: 20),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        busId,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        routeName,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                // Stop counter chip
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    '${currentStopIdx + 1}/${stops.length}',
                    style: TextStyle(
                      color: AppColors.accent.withValues(alpha: 0.8),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Divider
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            color: AppColors.divider,
          ),

          // Stops list
          Flexible(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: stops.length,
              itemBuilder: (context, index) {
                return _StopTile(
                  stop: stops[index],
                  index: index,
                  totalStops: stops.length,
                  currentStopIdx: currentStopIdx,
                  isAtStop: busStatus == 'at_stop' && index == currentStopIdx,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StopTile extends StatelessWidget {
  final BusStop stop;
  final int index;
  final int totalStops;
  final int currentStopIdx;
  final bool isAtStop;

  const _StopTile({
    required this.stop,
    required this.index,
    required this.totalStops,
    required this.currentStopIdx,
    required this.isAtStop,
  });

  @override
  Widget build(BuildContext context) {
    final isPassed = index <= currentStopIdx;
    final isCurrent = index == currentStopIdx;
    final isNext = index == currentStopIdx + 1;
    final isFirst = index == 0;
    final isLast = index == totalStops - 1;

    // Colors
    final lineColor = isPassed
        ? AppColors.accent
        : AppColors.divider;
    final dotColor = isCurrent
        ? AppColors.accent
        : isPassed
            ? AppColors.accent.withValues(alpha: 0.6)
            : AppColors.textFaint;
    final textColor = isCurrent
        ? AppColors.textPrimary
        : isPassed
            ? AppColors.textSecondary
            : AppColors.textFaint;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Timeline column
            SizedBox(
              width: 36,
              child: Column(
                children: [
                  // Top line
                  if (!isFirst)
                    Expanded(
                      child: Container(
                        width: 2.5,
                        color: lineColor,
                      ),
                    ),
                  if (isFirst) const Spacer(),

                  // Dot / Bus icon
                  if (isCurrent)
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.accent, width: 2),
                      ),
                      child: Icon(
                        Icons.directions_bus_rounded,
                        color: AppColors.accent,
                        size: 14,
                      ),
                    )
                  else if (isFirst || isLast)
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: isPassed ? AppColors.accent : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: dotColor,
                          width: 2.5,
                        ),
                      ),
                    )
                  else
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: isPassed ? dotColor : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: dotColor,
                          width: isPassed ? 0 : 2,
                        ),
                      ),
                    ),

                  // Bottom line
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2.5,
                        color: isNext || isPassed
                            ? (isPassed ? AppColors.accent : lineColor)
                            : lineColor,
                      ),
                    ),
                  if (isLast) const Spacer(),
                ],
              ),
            ),

            const SizedBox(width: 14),

            // Stop info
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      stop.name,
                      style: TextStyle(
                        color: textColor,
                        fontSize: isCurrent ? 16 : 14,
                        fontWeight:
                            isCurrent ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    if (isCurrent && isAtStop) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: AppColors.warning,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Bus is here',
                            style: TextStyle(
                              color: AppColors.warning.withValues(alpha: 0.8),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (isNext) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Next stop',
                        style: TextStyle(
                          color: AppColors.accent.withValues(alpha: 0.6),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Passed checkmark
            if (isPassed && !isCurrent)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.accent.withValues(alpha: 0.35),
                  size: 18,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
