// lib/models/prediction_result.dart

class PredictionResult {
  final String objectClass;
  final double confidence;
  // Bounding box coordinates (for drawing later)
  final double x; 
  final double y;
  final double width;
  final double height;

  PredictionResult({
    required this.objectClass,
    required this.confidence,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  // Factory method to create from Roboflow JSON
  factory PredictionResult.fromJson(Map<String, dynamic> json) {
    return PredictionResult(
      objectClass: json['class'] as String,
      confidence: json['confidence'] as double,
      x: json['x'] as double,
      y: json['y'] as double,
      width: json['width'] as double,
      height: json['height'] as double,
    );
  }
}