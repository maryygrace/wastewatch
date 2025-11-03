import 'dart:convert';
import 'dart:io';
import '../services/logging_service.dart';

class ImageConverter {
  static Future<String?> imageFileToBase64(File? imageFile) async {
    if (imageFile == null) {
      return null;
    }
    try {
      // 1. Read the file bytes
      final List<int> imageBytes = await imageFile.readAsBytes();

      // 2. Encode the bytes to a PURE Base64 string
      final String base64Image = base64Encode(imageBytes); // This is correct!

      return base64Image;
    } catch (e, stackTrace) {
      Log.e("ImageConverter: Failed to convert image to Base64", e, stackTrace);
      return null;
    }
  }
}