import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:wiyamusic/extensions/l10n.dart';
import 'package:wiyamusic/utilities/playlist_image_picker.dart';

/// Presents the playlist editor as a modal bottom sheet and returns the updated
/// playlist map (or `null` when cancelled).
Future<Map?> showEditPlaylistSheet(
  BuildContext context, {
  required Map playlistData,
}) {
  return showModalBottomSheet<Map?>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => _EditPlaylistSheet(playlistData: playlistData),
  );
}

class _EditPlaylistSheet extends StatefulWidget {
  const _EditPlaylistSheet({required this.playlistData});

  final Map playlistData;

  @override
  State<_EditPlaylistSheet> createState() => _EditPlaylistSheetState();
}

class _EditPlaylistSheetState extends State<_EditPlaylistSheet> {
  late TextEditingController _titleController;
  late TextEditingController _imageUrlController;
  String? _imageBase64;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.playlistData['title'],
    );
    final image = widget.playlistData['image'] as String?;
    if (image != null && image.startsWith('data:')) {
      _imageBase64 = image;
      _imageUrlController = TextEditingController(text: '');
    } else {
      _imageBase64 = null;
      _imageUrlController = TextEditingController(text: image);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await pickImage();
    if (result != null) {
      setState(() {
        _imageBase64 = result;
        _imageUrlController.text = '';
      });
    }
  }

  void _submit() {
    final newPlaylist = {
      'ytid': widget.playlistData['ytid'],
      'title': _titleController.text,
      'source': widget.playlistData['source'] ?? 'user-created',
      if (_imageBase64 != null)
        'image': _imageBase64
      else if (_imageUrlController.text.isNotEmpty)
        'image': _imageUrlController.text,
      'list': widget.playlistData['list'],
      if (widget.playlistData['createdAt'] != null)
        'createdAt': widget.playlistData['createdAt'],
    };

    Navigator.pop(context, newPlaylist);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final bottomSafe = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, bottomSafe + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    FluentIcons.edit_24_regular,
                    color: colorScheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.l10n!.editPlaylist,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: context.l10n!.customPlaylistName,
                prefixIcon: Icon(
                  FluentIcons.text_field_20_regular,
                  color: colorScheme.onSurfaceVariant,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: colorScheme.surface,
              ),
            ),
            if (_imageBase64 == null) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _imageUrlController,
                decoration: InputDecoration(
                  labelText: context.l10n!.customPlaylistImgUrl,
                  prefixIcon: Icon(
                    FluentIcons.image_20_regular,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: colorScheme.surface,
                ),
                onChanged: (_) => setState(() => _imageBase64 = null),
              ),
            ],
            const SizedBox(height: 12),
            if (_imageUrlController.text.isEmpty || _imageBase64 != null) ...[
              buildImagePickerRow(context, _pickImage, _imageBase64 != null),
              Center(
                child: buildImagePreview(
                  imageBase64: _imageBase64,
                  imageUrl: _imageUrlController.text.isEmpty
                      ? null
                      : _imageUrlController.text,
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: colorScheme.outline),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(context.l10n!.cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(FluentIcons.save_20_regular),
                    label: Text(context.l10n!.update),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
