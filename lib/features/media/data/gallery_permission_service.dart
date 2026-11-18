import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class GalleryPermissionService {
  const GalleryPermissionService._();

  static Future<bool> requestSavePermission() async {
    if (Platform.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      if (info.version.sdkInt >= 29) {
        // MediaStore scoped storage allows writes without broad storage access.
        return true;
      }
      return (await Permission.storage.request()).isGranted;
    }

    if (Platform.isIOS) {
      final info = await DeviceInfoPlugin().iosInfo;
      final majorVersion =
          int.tryParse(info.systemVersion.split('.').first) ?? 14;
      final status = majorVersion >= 14
          ? await Permission.photosAddOnly.request()
          : await Permission.photos.request();
      return status.isGranted;
    }

    return true;
  }
}
