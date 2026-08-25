import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// One picker for the whole app. Mime types match the backend allowlist in
/// backend/src/lib/upload.js — keep the two in step.
///
/// ponytail: gallery/file browser only. Camera capture needs a second plugin
/// (image_picker) and its permission plumbing; add it when someone actually asks
/// to photograph a report in-app.
Future<({Uint8List bytes, String name})?> pickAttachment({bool imagesOnly = false}) async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: imagesOnly
        ? const ['jpg', 'jpeg', 'png', 'webp', 'heic']
        : const ['jpg', 'jpeg', 'png', 'webp', 'heic', 'pdf'],
  );
  if (file == null) return null;
  return (bytes: await file.readAsBytes(), name: file.name);
}
