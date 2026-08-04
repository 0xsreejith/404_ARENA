import 'package:arena_os/app/theme/arena_colors.dart';
import 'package:arena_os/app/theme/arena_theme.dart';
import 'package:arena_os/app/theme/breakpoints.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('palette matches UI_SPEC.md §2 exactly', () {
    test('base tokens', () {
      expect(ArenaColors.background, const Color(0xFF07070A));
      expect(ArenaColors.surface, const Color(0xFF101018));
      expect(ArenaColors.surfaceRaised, const Color(0xFF171A20));
      expect(ArenaColors.textPrimary, const Color(0xFFE8EAF0));
      expect(ArenaColors.accent, const Color(0xFF7CFF4F));
      expect(ArenaColors.warning, const Color(0xFFFFB020));
      expect(ArenaColors.danger, const Color(0xFFFF4444));
    });

    test('muted is 45% opacity on primary text', () {
      expect(ArenaColors.textMuted.a, closeTo(0.45, 0.005));
      expect(ArenaColors.textMuted.r, ArenaColors.textPrimary.r);
      expect(ArenaColors.textMuted.g, ArenaColors.textPrimary.g);
      expect(ArenaColors.textMuted.b, ArenaColors.textPrimary.b);
    });

    test('state colours follow the green/amber/red meaning', () {
      expect(ArenaColors.stateLive, ArenaColors.accent);
      expect(ArenaColors.stateEnding, ArenaColors.warning);
      expect(ArenaColors.stateOvertime, ArenaColors.danger);
    });

    test('every station state is visually distinct', () {
      final states = <Color>{
        ArenaColors.stateIdle,
        ArenaColors.stateLive,
        ArenaColors.stateEnding,
        ArenaColors.stateOvertime,
        ArenaColors.statePaused,
        ArenaColors.stateMaintenance,
      };
      expect(states, hasLength(6));
    });
  });

  group('theme', () {
    final theme = ArenaTheme.dark();

    test('is dark and uses the specified background', () {
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, ArenaColors.background);
    });

    test('touch targets clear the 48dp Material floor (UI_SPEC.md §1)', () {
      expect(ArenaTheme.minTouchTarget, greaterThanOrEqualTo(48));
      final size = theme.filledButtonTheme.style?.minimumSize?.resolve(<WidgetState>{});
      expect(size?.height, ArenaTheme.minTouchTarget);
    });

    test('no decorative splash animation (UI_SPEC.md §1)', () {
      expect(theme.splashFactory, NoSplash.splashFactory);
    });

    test('numeric style uses tabular figures so timers do not jitter', () {
      expect(ArenaTheme.numeric.fontFeatures, contains(const FontFeature.tabularFigures()));
    });
  });

  group('breakpoints match ARCHITECTURE.md §14', () {
    test('classify by width', () {
      expect(Breakpoints.forWidth(320), LayoutClass.phone);
      expect(Breakpoints.forWidth(599.9), LayoutClass.phone);
      expect(Breakpoints.forWidth(600), LayoutClass.smallTablet);
      expect(Breakpoints.forWidth(1023.9), LayoutClass.smallTablet);
      expect(Breakpoints.forWidth(1024), LayoutClass.tablet);
      expect(Breakpoints.forWidth(1600), LayoutClass.tablet);
    });

    test('navigation affordances follow the class', () {
      expect(LayoutClass.phone.usesBottomNavigation, isTrue);
      expect(LayoutClass.phone.usesNavigationRail, isFalse);
      expect(LayoutClass.smallTablet.usesNavigationRail, isTrue);
      expect(LayoutClass.tablet.supportsSideDetailPanel, isTrue);
      expect(LayoutClass.smallTablet.supportsSideDetailPanel, isFalse);
    });
  });
}
