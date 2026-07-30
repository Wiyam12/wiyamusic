import 'package:flutter/material.dart';
import 'package:wiyamusic/theme/design_tokens.dart';

const recommendedCubesNumber = 8;

const commonSingleChildScrollViewPadding = EdgeInsets.symmetric(horizontal: 10);
var commonBarRadius = BorderRadius.circular(WiyaDesign.cornerRadius);
var commonBarTitleStyle = const TextStyle(
  fontSize: 15,
  fontWeight: FontWeight.bold,
);
const commonMiniArtworkRadius = WiyaDesign.cornerRadiusSmall;

const commonCustomBarRadius = BorderRadius.all(
  Radius.circular(WiyaDesign.cornerRadius),
);
const commonCustomBarRadiusFirst = BorderRadius.vertical(
  top: Radius.circular(WiyaDesign.cornerRadius),
);
const commonCustomBarRadiusLast = BorderRadius.vertical(
  bottom: Radius.circular(WiyaDesign.cornerRadius),
);

const miniPlayerTotalHeight = 92.0;

/// Extra inset around the floating mini player on tablet / iPad layouts.
const miniPlayerTabletHorizontalMargin = 20.0;
const miniPlayerTabletBottomMargin = 20.0;

/// Space reserved below page content on tablet when the mini player is visible
/// (player height 72 + bottom margin + top breathing room).
const miniPlayerTabletTotalHeight = 104.0;

/// Height of the floating bottom navigation pill (excluding margins).
/// Matches simple_clean_navbar advanced floating bar height.
const floatingNavBarHeight = 70.0;

/// Outer margin under the floating bottom navigation pill.
/// Matches simple_clean_navbar floating margin (20 bottom / 20 horizontal).
const floatingNavBarMargin = 20.0;

/// Gap between the mini player and the floating nav when both are visible.
const floatingNavMiniPlayerGap = 8.0;

/// Minimum width (logical px) at which tablet/iPad sidebar navigation is used
/// instead of the floating bottom navigation bar.
const tabletNavigationBreakpoint = 600.0;

const commonListViewBottomPadding = EdgeInsets.only(bottom: 8);

const commonBarContentPadding = EdgeInsets.symmetric(
  vertical: 12,
  horizontal: 10,
);

const commonPlaylistArtworkDivision = 1.75;
