import 'package:flutter/widgets.dart';

/// Layout classes from `ARCHITECTURE.md` §14.
///
/// One shared responsive scaffold uses these so that screens declare content,
/// not layout, and phone and tablet do not diverge screen by screen.
enum LayoutClass {
  /// `< 600` — bottom navigation, single column.
  phone,

  /// `600–1023` — navigation rail, two-column floor.
  smallTablet,

  /// `>= 1024` — persistent rail, multi-column floor, side detail panel.
  tablet;

  bool get usesBottomNavigation => this == LayoutClass.phone;
  bool get usesNavigationRail => this != LayoutClass.phone;
  bool get supportsSideDetailPanel => this == LayoutClass.tablet;
}

abstract final class Breakpoints {
  static const double smallTablet = 600;
  static const double tablet = 1024;

  static LayoutClass of(BuildContext context) => forWidth(MediaQuery.sizeOf(context).width);

  static LayoutClass forWidth(double width) {
    if (width >= tablet) return LayoutClass.tablet;
    if (width >= smallTablet) return LayoutClass.smallTablet;
    return LayoutClass.phone;
  }
}
