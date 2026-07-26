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

import 'package:flutter/material.dart';

// Closes the currently open custom bottom sheet. Stored so callers (e.g. tab
// switches) can force-dismiss the sheet even though it lives on the root
// navigator.
VoidCallback? _closeCurrentBottomSheet;

/// Shows the app's standard bottom sheet as a proper modal route.
///
/// Using [showModalBottomSheet] (instead of a persistent [showBottomSheet])
/// means the sheet is a real route: the Android back button dismisses it, a
/// scrim blocks taps on the content behind it, and it is removed correctly when
/// navigating elsewhere.
Future<T?> showCustomBottomSheet<T>(BuildContext context, Widget content) {
  final size = MediaQuery.sizeOf(context);
  final colorScheme = Theme.of(context).colorScheme;

  final future = showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      _closeCurrentBottomSheet = () {
        final navigator = Navigator.of(sheetContext);
        if (navigator.canPop()) navigator.pop();
      };

      return Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: GestureDetector(
                onTap: () => Navigator.pop(sheetContext),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: size.width * 0.92,
                maxHeight: size.height * 0.65,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 16),
                child: content,
              ),
            ),
          ],
        ),
      );
    },
  );

  return future
    ..whenComplete(() {
      _closeCurrentBottomSheet = null;
    });
}

void closeCurrentBottomSheet() {
  final close = _closeCurrentBottomSheet;
  _closeCurrentBottomSheet = null;
  try {
    close?.call();
  } catch (_) {}
}
