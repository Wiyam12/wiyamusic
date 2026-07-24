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
import 'package:wiyamusic/utilities/search_navigation.dart';
import 'package:wiyamusic/widgets/custom_search_bar.dart';

/// Tap-only search entry that visually matches [CustomSearchBar].
///
/// Does not perform searching — it only opens the Search page.
class SearchEntryBar extends StatefulWidget {
  const SearchEntryBar({
    super.key,
    required this.hintText,
    this.onTap,
  });

  final String hintText;
  final VoidCallback? onTap;

  @override
  State<SearchEntryBar> createState() => _SearchEntryBarState();
}

class _SearchEntryBarState extends State<SearchEntryBar> {
  final GlobalKey _barKey = GlobalKey();
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode(canRequestFocus: false, skipTraversal: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (widget.onTap != null) {
      widget.onTap!();
      return;
    }

    final box = _barKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;

    await SearchNavigation.openSearch(context, origin: origin);
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _barKey,
      child: GestureDetector(
        onTap: _handleTap,
        behavior: HitTestBehavior.opaque,
        child: AbsorbPointer(
          child: CustomSearchBar(
            controller: _controller,
            focusNode: _focusNode,
            labelText: widget.hintText,
            onSubmitted: (_) {},
          ),
        ),
      ),
    );
  }
}
