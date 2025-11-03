import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'logging_service.dart'; // Import your logging service

/// A service for interacting with the Roboflow Hosted Inference API.
class RoboflowApiService {
  // Retrieve configuration details from the .env file
  static final String _apiKey = dotenv.env['ROBOFLOW_API_KEY'] ?? '';
  static final String _endpoint = dotenv.env['MODEL_ENDPOINT'] ?? '';
  static final String _version = dotenv.env['MODEL_VERSION'] ?? '';
  
  // The base URL for Roboflow inference. We use the 'detect' endpoint.
  static const String _baseUrl = 'https://detect.roboflow.com';

  /// Performs object detection inference on a Base64 encoded image.
  ///
  /// [base64Image] is the image string converted from a [File].
  /// Returns a Map of the inference results, or null on failure.
  static Future<Map<String, dynamic>?> getInference(String base64Image) async {
    // 1. Configuration check
    if (_apiKey.isEmpty || _endpoint.isEmpty || _version.isEmpty) {
      Log.e("Roboflow config missing", "API key, endpoint, or version is not set in .env.");
      return null;
    }

    // URL includes the API Key
    final String url = '$_baseUrl/$_endpoint/$_version?api_key=$_apiKey';
    
    // --- CHANGE 1: THE REQUEST BODY ---
    // Use the raw Base64 string as the body.
    final String requestBody = base64Image;

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          // --- CHANGE 2: THE HEADER ---
          // Use 'application/x-www-form-urlencoded' to be compatible with raw POST data.
          'Content-Type': 'application/x-www-form-urlencoded', 
          'Accept': 'application/json', 
        },
        body: requestBody, // Send the raw Base64 string
      );

      // 2. HTTP Status Code Handling
      if (response.statusCode == 200) {
        // Successful response
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        // Log the specific API error message
        Log.e(
          "Roboflow API call failed with status ${response.statusCode}", 
          "Roboflow Response Body: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)} (truncated)"
        );
        return null;
      }
    } catch (e, stackTrace) {
      // 3. Network or other exceptions
      Log.e("Roboflow API network error", e, stackTrace);
      return null;
    }
  }
}