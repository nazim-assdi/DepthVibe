import 'package:file_picker/file_picker.dart';

class MediaPickerService {
  const MediaPickerService._();

  static Future<String?> pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
      withData: false,
    );
    return result?.files.single.path;
  }

  static Future<List<String>> pickVideos() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: true,
      withData: false,
    );
    return result?.files
            .map((file) => file.path)
            .whereType<String>()
            .toList(growable: false) ??
        const [];
  }

  static Future<String?> pickAudio() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
      withData: false,
    );
    return result?.files.single.path;
  }

  static Future<String?> pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
    );
    return result?.files.single.path;
  }
}
