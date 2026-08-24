import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A one-pixel divider that can be dragged to resize the panel beside it.
/// The hit area is wider than the line so it stays grabbable.
class DragHandle extends StatefulWidget {
  /// Positive delta means the pointer moved right.
  final ValueChanged<double> onDrag;

  const DragHandle({super.key, required this.onDrag});

  @override
  State<DragHandle> createState() => _DragHandleState();
}

class _DragHandleState extends State<DragHandle> {
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _active = true),
      onExit: (_) => setState(() => _active = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
        child: SizedBox(
          width: 7,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: _active ? 3 : 1,
              color: _active ? colors.accent : colors.border,
            ),
          ),
        ),
      ),
    );
  }
}
