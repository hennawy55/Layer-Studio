import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

/// Selects photos with Android's native photo picker on Android. FilePicker's
/// Android document-copy path can rewrite image pixels/metadata on some
/// providers, which can make an otherwise-correct EXIF transform run twice.
class ImageImportPicker {
  ImageImportPicker({ImagePicker? imagePicker})
      : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  Future<String?> pickImage() async {
    if (Platform.isAndroid) {
      final selected = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: true,
      );
      return selected?.path;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
      allowCompression: false,
    );
    return result?.files.single.path;
  }

  /// Desktop keeps direct access to SVG files; on Android image imports use
  /// the native photo picker and SVGs are added from the saved logo library.
  Future<String?> pickImageOrSvg() async {
    if (Platform.isAndroid) return pickImage();

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif', 'svg'],
      allowMultiple: false,
      withData: false,
      allowCompression: false,
    );
    return result?.files.single.path;
  }

  Future<String?> pickSvg() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['svg'],
      allowMultiple: false,
      withData: false,
    );
    return result?.files.single.path;
  }
}
