import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config.dart';

class CloudinaryService {
  /// Uploads any file with an unsigned preset and returns its public URL.
  static Future<String> upload(File file, {required String name}) async {
    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/${Config.cloudinaryCloudName}/auto/upload',
    );
    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = Config.cloudinaryUploadPreset
      ..files.add(await http.MultipartFile.fromPath('file', file.path, filename: name));

    final response = await http.Response.fromStream(await request.send());
    if (response.statusCode != 200) {
      throw Exception('Upload failed (${response.statusCode}): ${response.body}');
    }
    return jsonDecode(response.body)['secure_url'] as String;
  }
}
