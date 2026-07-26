/*
 *     Copyright (C) 2026 Valeri Gokadze
 *
 *     WiyaMusic is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version.
 *
 *     WiyaMusic is distributed in the hope that it will be useful,
 *     but WITHOUT ANY WARRANTY; without even the implied warranty of
 *     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *     GNU General Public License for more details.
 *
 *     You should have received a copy of the GNU General Public License
 *     along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 *
 *     For more information about WiyaMusic, including how to contribute,
 *     please visit: https://github.com/Wiyam12/wiyamusic
 */

import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

OverlayEntry? _activeToast;
Timer? _toastTimer;

void _dismissToast() {
  _toastTimer?.cancel();
  _toastTimer = null;
  _activeToast?.remove();
  _activeToast = null;
}

void showToast(
  BuildContext context,
  String text, {
  Duration duration = const Duration(seconds: 3),
  IconData? icon,
}) {
  _showTopToast(
    context,
    duration: duration,
    builder: (colorScheme, textStyle, dismiss) {
      return Row(
        children: [
          Icon(
            icon ?? FluentIcons.checkmark_circle_20_regular,
            color: colorScheme.onSecondaryContainer,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: textStyle)),
        ],
      );
    },
  );
}

void showToastWithButton(
  BuildContext context,
  String text,
  String buttonName,
  VoidCallback onPressedToast, {
  Duration duration = const Duration(seconds: 3),
  IconData? icon,
}) {
  final actionColor =
      Theme.of(context).snackBarTheme.actionTextColor ??
      Theme.of(context).colorScheme.primary;

  _showTopToast(
    context,
    duration: duration,
    builder: (colorScheme, textStyle, dismiss) {
      return Row(
        children: [
          Icon(
            icon ?? FluentIcons.info_20_regular,
            color: colorScheme.onSecondaryContainer,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: textStyle)),
          TextButton(
            onPressed: () {
              dismiss();
              onPressedToast();
            },
            child: Text(
              buttonName,
              style: TextStyle(color: actionColor, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );
    },
  );
}

/// Resolves the overlay to host the toast.
///
/// Callers often pass a navigator's own context (such as
/// `NavigationManager().context`). A navigator builds its overlay as a child,
/// so the usual ancestor lookup finds nothing there and the toast would be
/// dropped; fall back to searching downwards in that case.
OverlayState? _resolveOverlay(BuildContext context) {
  final ancestor = Overlay.maybeOf(context);
  if (ancestor != null) return ancestor;

  OverlayState? descendant;
  void visit(Element element) {
    if (descendant != null) return;
    if (element is StatefulElement && element.state is OverlayState) {
      descendant = element.state as OverlayState;
      return;
    }
    element.visitChildren(visit);
  }

  context.visitChildElements(visit);
  return descendant;
}

void _showTopToast(
  BuildContext context, {
  required Duration duration,
  required Widget Function(
    ColorScheme colorScheme,
    TextStyle? textStyle,
    VoidCallback dismiss,
  )
  builder,
}) {
  final overlay = _resolveOverlay(context);
  if (overlay == null) return;

  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  final snackTheme = theme.snackBarTheme;
  final background =
      snackTheme.backgroundColor ?? colorScheme.secondaryContainer;
  final textStyle =
      snackTheme.contentTextStyle ??
      TextStyle(
        color: colorScheme.onSecondaryContainer,
        fontWeight: FontWeight.w500,
      );
  final shape =
      snackTheme.shape ??
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(20));

  _dismissToast();

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (overlayContext) {
      final top = MediaQuery.paddingOf(overlayContext).top + 12;

      return Positioned(
        top: top,
        left: 16,
        right: 16,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Material(
              color: background,
              elevation: snackTheme.elevation ?? 0,
              shape: shape,
              clipBehavior: Clip.antiAlias,
              child: Dismissible(
                key: const ValueKey('top-toast'),
                direction: DismissDirection.up,
                onDismissed: (_) => _dismissToast(),
                child: SafeArea(
                  top: false,
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: builder(colorScheme, textStyle, _dismissToast),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  _activeToast = entry;
  overlay.insert(entry);
  _toastTimer = Timer(duration, () {
    if (_activeToast == entry) _dismissToast();
  });
}
