import 'package:flutter/material.dart';
import 'package:wastewatch/services/supabase_service.dart';
import 'package:wastewatch/services/logging_service.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

class CollectorReportDetailScreen extends StatefulWidget {
  final String reportId;

  const CollectorReportDetailScreen({super.key, required this.reportId});

  @override
  State<CollectorReportDetailScreen> createState() => _CollectorReportDetailScreenState();
}

class _CollectorReportDetailScreenState extends State<CollectorReportDetailScreen> {
  Map<String, dynamic>? _report;
  bool _isLoading = true;
  String? _errorMessage;
  String? _currentStatus;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _fetchReportDetails();
  }

  Future<void> _fetchReportDetails() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final reportData = await SupabaseService.getReport(widget.reportId);
      if (reportData == null) {
        throw Exception('Report not found.');
      }
      if (mounted) {
        setState(() {
          _report = reportData;
          _currentStatus = reportData['status'];
          _isLoading = false;
        });
      }
    } catch (e, s) {
      Log.e('Failed to fetch report details', e, s);
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load report details.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    setState(() {
      _isUpdating = true;
    });
    try {
      final updates = <String, dynamic>{'status': newStatus};
      if (newStatus == 'resolved') {
        updates['resolved_by'] = SupabaseService.currentUser?.id;
        updates['resolved_at'] = DateTime.now().toIso8601String();
      }

      await SupabaseService.updateReport(widget.reportId, updates);
      if (mounted) {
        setState(() {
          _currentStatus = newStatus;
          _report?['status'] = newStatus; // Also update the local report map
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Report status updated to "$newStatus"'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e, s) {
      Log.e('Failed to update report status', e, s);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update status. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  Future<void> _launchMaps(double lat, double lon) async {
    final uri = Uri.tryParse('https://www.google.com/maps/search/?api=1&query=$lat,$lon');
    if (uri != null) {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        Log.e('Could not launch maps', 'URL launch failed for: $uri', null);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open map application.')),
          );
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid location data.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_report?['title'] ?? 'Report Details'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_errorMessage!),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchReportDetails,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final report = _report!;
    final location = (report['latitude'] != null && report['longitude'] != null)
        ? LatLng(report['latitude'], report['longitude'])
        : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (report['imageUrl'] != null)
            FutureBuilder<String>(
              future: SupabaseService.getValidImageUrl(report['imageUrl'] as String),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
                }
                if (snapshot.hasError || !snapshot.hasData) {
                  return const SizedBox(height: 200, child: Center(child: Icon(Icons.error, color: Colors.red, size: 40)));
                }
                return ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    snapshot.data!,
                    height: 250,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                );
              },
            ),
          const SizedBox(height: 16),
          Text(
            report['title'] ?? 'Untitled Report',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (report['description'] != null && report['description'].isNotEmpty)
            Text(
              report['description'],
              style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
            ),
          if (report['location'] != null && report['location'].isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.location_pin, color: Colors.grey.shade600, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(report['location'], style: TextStyle(fontSize: 16, color: Colors.grey.shade700))),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.calendar_today, color: Colors.grey.shade600, size: 20),
              const SizedBox(width: 8),
              Text(
                'Reported on: ${DateTime.parse(report['createdAt']).toLocal().toString().split('.')[0]}',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
              ),
            ],
          ),
          const Divider(height: 32),
          if (location != null) ...[
            const Text('Location', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: location,
                    initialZoom: 16.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.yourcompany.wastewatch',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: location,
                          child: const Icon(Icons.location_on, color: Colors.red, size: 40.0),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _launchMaps(location.latitude, location.longitude),
                icon: const Icon(Icons.directions),
                label: const Text('Get Directions'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  textStyle: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
          const Text('Update Status', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _buildStatusChanger(),
          // Add padding at the bottom to avoid being obscured by system UI
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildStatusChanger() {
    if (_isUpdating) {
      return const Center(child: CircularProgressIndicator());
    }

    final statuses = ['pending', 'in-progress', 'resolved'];
    final bool isResolved = _currentStatus == 'resolved';
    
    return DropdownButtonFormField<String>(
      initialValue: _currentStatus,
      decoration: InputDecoration(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      disabledHint: Text(_currentStatus?.toUpperCase() ?? 'RESOLVED'),
      items: statuses.map((String status) {
        return DropdownMenuItem<String>(
          value: status,
          child: Text(status.toUpperCase()),
        );
      }).toList(),
      onChanged: isResolved ? null : (String? newStatus) {
        if (newStatus != null && newStatus != _currentStatus) _showConfirmationDialog(newStatus);
      }
    );
  }

  void _showConfirmationDialog(String newStatus) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Status Change'),
          content: Text('Are you sure you want to change the status to "$newStatus"?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
                // Revert the dropdown to the original status if the user cancels
                setState(() {
                  // No need to change _currentStatus, just rebuild to show it
                });
              },
            ),
            TextButton(
              child: const Text('Confirm'),
              onPressed: () {
                Navigator.of(context).pop();
                _updateStatus(newStatus);
              },
            ),
          ],
        );
      },
    ).then((_) {
      // This `then` block ensures that if the dialog is dismissed by tapping outside,
      // the UI dropdown resets to its original state.
      setState(() {
        // This rebuilds the widget, and since _currentStatus hasn't changed yet,
        // the DropdownButtonFormField will show the correct value.
      });
    });
  }
}