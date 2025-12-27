import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:io';
import '../../services/supabase_service.dart';
import '../../services/logging_service.dart';
import 'package:flutter_map/flutter_map.dart' show FlutterMap, MapController, MapOptions, TileLayer, MarkerLayer, Marker, TapPosition;
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';

// Import the necessary new files
import '../../utils/image_converter.dart';
import '../../services/roboflow_api_service.dart';
import '../../models/prediction_result.dart'; // <--- IMPORT THE NEW MODEL

// Define waste categories as a top-level constant for better code organization.
const List<String> _wasteCategories = [
  'plastic',
  'glass',
  'paper',
  'metal',
  'residual',
];

class ReportSubmissionScreen extends StatefulWidget {
  // Add an optional report object for editing
  final Map<String, dynamic>? reportToEdit;

  const ReportSubmissionScreen({super.key, this.reportToEdit});
  bool get isEditMode => reportToEdit != null;

  @override
  State<ReportSubmissionScreen> createState() => _ReportSubmissionScreenState();
}

class _ReportSubmissionScreenState extends State<ReportSubmissionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _contactNumberController = TextEditingController();
  final _locationSearchController = TextEditingController();
  final MapController _mapController = MapController();

  final List<String> _selectedCategories = [];
  File? _imageFile;
  LatLng? _selectedLocation;
  bool _isSubmitting = false; // Used for both report submission and image analysis loading
  bool _isSearching = false;
  bool _isLocating = true; 

  // NEW STATE: To hold the raw prediction JSON (for saving to Supabase)
  Map<String, dynamic>? _roboflowPrediction;
  
  // ADDED: To hold the structured prediction objects (for displaying in UI)
  List<PredictionResult> _predictions = [];
  String? _primaryWasteClass; // The highest confidence class

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    if (widget.isEditMode) {
      _populateFieldsForEditing();
    } else {
      _getCurrentLocation();
      _fetchUserContactInfo();
    }
  }

  void _populateFieldsForEditing() {
    final report = widget.reportToEdit!;
    _titleController.text = report['title'] ?? '';
    _descriptionController.text = report['description'] ?? '';
    _contactNumberController.text = report['contact_number'] ?? '';
    _selectedCategories.addAll((report['wasteCategory'] as String?)?.split(',') ?? []);
    if (report['latitude'] != null && report['longitude'] != null) {
      _selectedLocation = LatLng(report['latitude'], report['longitude']);
    }
    
    // Load and parse the existing prediction data
    if (report['roboflow_predictions'] != null && report['roboflow_predictions'] is String) {
        try {
            final Map<String, dynamic> rawPrediction = jsonDecode(report['roboflow_predictions']);
            _roboflowPrediction = rawPrediction;
            
            // Parse for UI display
            if (rawPrediction.containsKey('predictions')) {
              final List<dynamic> rawPredictionsList = rawPrediction['predictions'];
              _predictions.addAll(rawPredictionsList
                  .map((p) => PredictionResult.fromJson(p as Map<String, dynamic>))
                  .toList());
                  
              if (_predictions.isNotEmpty) {
                  _predictions.sort((a, b) => b.confidence.compareTo(a.confidence));
                  _primaryWasteClass = _predictions.first.objectClass;
              }
            }
        } catch (e) {
            Log.e('Failed to parse existing Roboflow predictions', e);
        }
    }
    
    // Note: We don't load the existing image file here as it would require a network call.
    setState(() => _isLocating = false);
  }

  Future<void> _fetchUserContactInfo() async {
    final user = SupabaseService.currentUser;
    if (user != null) {
      final userData = await SupabaseService.getUserData(user.id);
      if (userData != null && userData['phone_number'] != null) {
        if (mounted) {
          setState(() => _contactNumberController.text = userData['phone_number']);
        }
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 85,
      );
      
      if (pickedFile != null) {
        final File newImageFile = File(pickedFile.path);

        setState(() {
          _imageFile = newImageFile;
          _isSubmitting = true; // Show loading indicator during analysis
          _roboflowPrediction = null; // Clear previous raw JSON
          _predictions = []; // Clear previous structured predictions
          _primaryWasteClass = null; // Clear primary class
        });

        // 1. Convert image to Base64
        final String? base64Image = await ImageConverter.imageFileToBase64(newImageFile);

        if (base64Image != null) {
          // 2. Call Roboflow API
          final predictionResult = await RoboflowApiService.getInference(base64Image);

          // 3. Parse and store the results
          final newPredictions = <PredictionResult>[];
          String? determinedPrimaryClass;
          
          if (predictionResult != null && predictionResult.containsKey('predictions')) {
            final List<dynamic> rawPredictions = predictionResult['predictions'];
            
            newPredictions.addAll(rawPredictions
                .map((p) => PredictionResult.fromJson(p as Map<String, dynamic>))
                .toList());
                
            // Determine the primary class (highest confidence)
            if (newPredictions.isNotEmpty) {
                newPredictions.sort((a, b) => b.confidence.compareTo(a.confidence));
                determinedPrimaryClass = newPredictions.first.objectClass;
            }
          }
          
          setState(() {
            _roboflowPrediction = predictionResult; // Raw JSON for database
            _predictions = newPredictions; // Structured data for UI
            _primaryWasteClass = determinedPrimaryClass; // Primary class for quick view
            // Optionally, you could auto-select categories here based on the predictionResult
            _autoSelectCategories(predictionResult);
            _isSubmitting = false; // Analysis complete
          });

          if (predictionResult == null) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Failed to analyze image with Roboflow. Please try another image.')),
              );
            }
          } else {
             if (mounted) {
               final count = newPredictions.length;
               ScaffoldMessenger.of(context).showSnackBar(
                 SnackBar(content: Text('Image analysis complete. $count item(s) detected.')),
               );
            }
          }
        } else {
          setState(() {
            _isSubmitting = false; // Analysis failed
          });
        }
      }
    } catch (e, stackTrace) {
      Log.e("Image picking failed", e, stackTrace);
      if (mounted) {
        setState(() {
            _isSubmitting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to pick image.')),
        );
      }
    }
  }
  
  // Helper to auto-select categories based on Roboflow predictions
  void _autoSelectCategories(Map<String, dynamic>? predictionResult) {
    if (predictionResult == null || predictionResult['predictions'] == null) return;
    
    final List<dynamic> predictions = predictionResult['predictions'];
    final Set<String> detectedClasses = predictions
        .map((p) => (p['class'] as String).toLowerCase())
        .toSet();

    setState(() {
      _selectedCategories.clear();
      for (var category in _wasteCategories) {
        // Simple logic: if a detected class contains a waste category name
        if (detectedClasses.any((detectedClass) => detectedClass.contains(category))) {
          if (!_selectedCategories.contains(category)) {
            _selectedCategories.add(category);
          }
        }
      }
    });
  }

  void _onMapTapped(TapPosition tapPosition, LatLng latLng) async {
    setState(() {
      _selectedLocation = latLng;
      // Show a temporary loading state in the text field
      _locationSearchController.text = 'Fetching address...';
    });

    final address = await _getAddressFromLatLng(latLng);

    if (!mounted) return;

    // Update the text field with the fetched address
    _locationSearchController.text = address;
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLocating = true);
    Location location = Location();

    bool serviceEnabled;
    PermissionStatus permissionGranted;
    LocationData locationData;

    serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) {
        Log.w('Location service is disabled.');
        setState(() => _isLocating = false);
        return;
      }
    }

    permissionGranted = await location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) {
        Log.w('Location permission denied.');
        setState(() => _isLocating = false);
        return;
      }
    }

    locationData = await location.getLocation();
    final newLocation = LatLng(locationData.latitude!, locationData.longitude!);

    // Reverse geocode to get the address
    final address = await _getAddressFromLatLng(newLocation);
    if (!mounted) return;

    setState(() {
      _selectedLocation = newLocation;
      _locationSearchController.text = address; // Update text field
      _mapController.move(_selectedLocation!, 18.0);
      _isLocating = false;
    });
  }

  Future<String> _getAddressFromLatLng(LatLng latLng) async {
    try {
      final url = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?format=json&lat=${latLng.latitude}&lon=${latLng.longitude}');
      final response =
          await http.get(url, headers: {'User-Agent': 'WasteWatch/1.0'});

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        if (result != null && result['display_name'] != null) {
          return result['display_name'];
        }
      }
      return 'Unnamed Location';
    } catch (e, stackTrace) {
      Log.e("Reverse geocoding failed", e, stackTrace);
      return 'Could not fetch address';
    }
  }

  Future<void> _searchLocation() async {
    final query = _locationSearchController.text.trim();
    if (query.isEmpty) return;

    setState(() => _isSearching = true);

    try {
      final url = Uri.parse('https://nominatim.openstreetmap.org/search?q=$query&format=json&limit=1');
      final response = await http.get(url, headers: {'User-Agent': 'WasteWatch/1.0'});

      if (response.statusCode == 200) {
        final results = json.decode(response.body);
        if (results.isNotEmpty) {
          final lat = double.parse(results[0]['lat']);
          final lon = double.parse(results[0]['lon']);
          final displayName = results[0]['display_name'] as String;
          setState(() {
            _selectedLocation = LatLng(lat, lon);
            _locationSearchController.text = displayName; // Update text field
            _mapController.move(_selectedLocation!, 18.0);
          });
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Location not found.')),
            );
          }
        }
      }
    } catch (e, stackTrace) {
      Log.e("Location search failed", e, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to search for location.')));
      }
    } finally {
      setState(() => _isSearching = false);
    }
  }

  Future<void> _submitReport() async {
    // Centralize validation
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    // VALIDATION: Ensure all required fields are filled
    if (_selectedCategories.isEmpty || _selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields, including categories and location.')),
      );
      return;
    }
    
    if (_imageFile == null && !widget.isEditMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an image.')),
      );
      return;
    }
    
    // Check if a new image was picked but analysis hasn't completed
    // This logic handles both creation and editing when a *new* image is picked.
    if (_imageFile != null && _roboflowPrediction == null) {
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please wait for image analysis to complete.')),
      );
      return;
    }


    setState(() {
      _isSubmitting = true;
    });

    try {
      final user = SupabaseService.currentUser;
      if (user == null) {
        // Log out or prompt login if user is missing
        return; 
      }

      String? imageUrl;
      // Only upload a new image if one has been selected.
      if (_imageFile != null) {
        final String fileExtension = _imageFile!.path.split('.').last;
        final String path = '${user.id}/${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
        imageUrl = await SupabaseService.uploadImageToStorage('report_images', path, _imageFile!);
      }
      
      // Prepare Roboflow data to be saved as JSON string
      // Note: predictionJson will be non-null if _roboflowPrediction is not null (i.e., new analysis ran or we are populating existing data)
      final String? predictionJson = _roboflowPrediction != null
          ? jsonEncode(_roboflowPrediction)
          : null; 

      if (widget.isEditMode) {
        // UPDATE logic
        final reportId = widget.reportToEdit!['id'];
        final updateData = {
          'title': _titleController.text,
          'description': _descriptionController.text.trim(),
          'contact_number': _contactNumberController.text.trim(),
          'waste_category': _selectedCategories.join(','),
          'latitude': _selectedLocation!.latitude,
          'longitude': _selectedLocation!.longitude,
          'location': _locationSearchController.text.trim(),
          if (imageUrl != null) 'image_url': imageUrl, // Only update image if a new one was picked
          // Include prediction data if a new image was analyzed (predictionJson != null)
          // or if the old one should be explicitly set to null (not handled here, but optional)
          if (_imageFile != null) 'roboflow_predictions': predictionJson, 
        };
        await SupabaseService.updateReport(reportId, updateData);
      } else {
        // CREATE logic
        final reportData = {
          'user_id': user.id,
          'title': _titleController.text,
          'description': _descriptionController.text.trim(),
          'contact_number': _contactNumberController.text.trim(),
          'waste_category': _selectedCategories.join(','),
          'latitude': _selectedLocation!.latitude,
          'longitude': _selectedLocation!.longitude,
          'location': _locationSearchController.text.trim(),
          'image_url': imageUrl,
          'status': 'pending',
          // Include prediction data for creation. It should be non-null here due to validation.
          'roboflow_predictions': predictionJson, 
        };
        await SupabaseService.createReport(reportData);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isEditMode ? 'Report updated successfully!' : 'Report submitted successfully!',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e, stackTrace) {
      Log.e("Report submission failed", e, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar( 
          SnackBar(content: Text('Failed to submit report. Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _contactNumberController.dispose();
    _locationSearchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Determine if we have any successful predictions to display
    final hasPredictions = _predictions.isNotEmpty;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditMode ? 'Edit Report' : 'Submit a New Report'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ... existing form fields (Title, Description) ...
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'Title / Landmark',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                ),
                validator: (value) =>
                    value!.isEmpty ? 'Please enter a title' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: 'Description (Optional)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _contactNumberController,
                decoration: InputDecoration(
                  labelText: 'Contact Number',
                  hintText: 'e.g., 09123456789',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  prefixIcon: const Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
                validator: (value) => value!.isEmpty ? 'Please enter a contact number' : null,
              ),
              const SizedBox(height: 16),

              // ... existing Categories selector ...
              const Text(
                'Waste Categories (Select all that apply)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8.0,
                runSpacing: 4.0,
                children: _wasteCategories.map((category) {
                  final isSelected = _selectedCategories.contains(category);
                  return FilterChip(
                    label: Text(category[0].toUpperCase() + category.substring(1)),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedCategories.add(category);
                        } else {
                          _selectedCategories.remove(category);
                        }
                      });
                    },
                    selectedColor: Colors.green.shade100,
                    checkmarkColor: Colors.green,
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              
              // NEW: Image Analysis Results Display
              if (_imageFile != null && hasPredictions)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AI Analysis: Detected Items',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                    const SizedBox(height: 8),

                    // Primary Class Highlight
                    if (_primaryWasteClass != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Text(
                          'Highest Confidence: ${_primaryWasteClass!.toUpperCase()}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ),

                    // Detailed List of Predictions in a Card
                    Card(
                      elevation: 1,
                      child: Column(
                        children: _predictions.map((p) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                p.objectClass[0].toUpperCase() + p.objectClass.substring(1),
                                style: const TextStyle(fontWeight: FontWeight.w500),
                              ),
                              Text(
                                '${(p.confidence * 100).toStringAsFixed(1)}%',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        )).toList(),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
                
              // LOADING INDICATOR FOR ANALYSIS
              if (_imageFile != null && _isSubmitting && _predictions.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 24.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(width: 16),
                      Text('Analyzing image...'),
                    ],
                  ),
                ),
                
              // ... existing Image selection buttons/preview ...
              _imageFile == null
                  ? Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('Camera'),
                            onPressed: () => _pickImage(ImageSource.camera),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.photo_library),
                            label: const Text('Gallery'),
                            onPressed: () => _pickImage(ImageSource.gallery),
                          ),
                        ),
                      ],
                    )
                  : GestureDetector(
                      onTap: () => _showImageSourceDialog(),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8.0),
                        child: Image.file(
                          _imageFile!,
                          fit: BoxFit.cover,
                          height: 200,
                          width: double.infinity,
                        ),
                      ),
                    ),
              
              const SizedBox(height: 24),

              // ... existing Location fields and map ...
              const Text(
                'Add Location',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _locationSearchController,
                      decoration: InputDecoration(
                        labelText: 'Search for a location',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                      ),
                      onFieldSubmitted: (_) => _searchLocation(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: _isSearching
                        ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                        : const Icon(Icons.search),
                    onPressed: _isSearching ? null : _searchLocation,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey.shade200,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: _isLocating
                        ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                        : const Icon(Icons.my_location),
                    onPressed: _isLocating ? null : _getCurrentLocation,
                    tooltip: 'Pinpoint My Location',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey.shade200,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 250, // Reduced map height
                child: FlutterMap(
                  key: UniqueKey(), // Add this key to force a rebuild when location changes
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _selectedLocation ?? const LatLng(10.8702, 122.9566),
                    initialZoom: _selectedLocation != null ? 18.0 : 5.0,
                    onTap: _onMapTapped,
                  ),
                  children: [
                    if (_isLocating)
                      const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 8),
                            Text('Fetching your location...'),
                          ],
                        ),
                      ),
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.wastewatch',
                    ),
                    if (_selectedLocation != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _selectedLocation!,
                            child: const Icon(
                              Icons.location_on,
                              color: Colors.red,
                              size: 40.0,
                            ), // The 'builder' property is now 'child'.
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              if (_selectedLocation != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    'Lat: ${_selectedLocation!.latitude.toStringAsFixed(4)}, Lon: ${_selectedLocation!.longitude.toStringAsFixed(4)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              const SizedBox(height: 24),

              // ... existing Submission button (with updated condition) ...
              ElevatedButton(
                // Disable if submitting OR if image is picked but analysis is still loading
                onPressed: _isSubmitting ? null : _submitReport,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(widget.isEditMode ? 'Update Report' : 'Submit Report'),
              ),
              // Add padding at the bottom to avoid being obscured by system UI
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  void _showImageSourceDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Image Source'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () {
                Navigator.of(context).pop();
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.of(context).pop();
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }
}