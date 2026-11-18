import 'package:file_picker/file_picker.dart';

class MediaPickerService {
  const MediaPickerService._();

  static Future<String?> pickVideo() async {
    final file = await FilePicker.pickFile(type: FileType.video);
    return file?.path;
  }

  static Future<List<String>> pickVideos() async {
    final files = await FilePicker.pickFiles(type: FileType.video);
    return files
        .map((file) => file.path)
        .whereType<String>()
        .toList(growable: false);
  }

  static Future<String?> pickAudio() async {
    final file = await FilePicker.pickFile(type: FileType.audio);
    return file?.path;
  }

  static Future<String?> pickImage() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    return file?.path;
  }
}
