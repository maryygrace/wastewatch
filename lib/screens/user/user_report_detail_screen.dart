import 'package:flutter/material.dart';
import 'package:wastewatch/services/supabase_service.dart';
import 'package:wastewatch/services/logging_service.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'report_submission_screen.dart';

class UserReportDetailScreen extends StatefulWidget {
  final String reportId;

  const UserReportDetailScreen({super.key, required this.reportId});

  @override
  State<UserReportDetailScreen> createState() => _UserReportDetailScreenState();
}

class _UserReportDetailScreenState extends State<UserReportDetailScreen> {
  Map<String, dynamic>? _report;
  bool _isLoading = true;
  String? _errorMessage;

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

  Future<void> _deleteReport() async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Report'),
        content: const Text('Are you sure you want to permanently delete this report?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      try {
        await SupabaseService.deleteReport(widget.reportId);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report deleted successfully.'), backgroundColor: Colors.green),
        );
        Navigator.of(context).pop();
      } catch (e, s) {
        Log.e('Failed to delete report', e, s);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete report. Please try again.'), backgroundColor: Colors.red),
        );
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
            const SizedBox(height: 24),
          ],
          const Divider(height: 32),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: Icon(
                    Icons.edit,
                    color: report['status'] == 'resolved' ? Colors.grey : null,
                  ),
                  label: const Text('Edit Report'),
                  onPressed: report['status'] == 'resolved'
                      ? null // Disable button if resolved
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ReportSubmissionScreen(reportToEdit: _report),
                            ),
                          );
                        },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.delete_forever, color: Colors.white),
                  label: const Text('Delete Report', style: TextStyle(color: Colors.white)),
                  onPressed: report['status'] == 'resolved' ? null : _deleteReport,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                ),
              ),
            ],
          ),
          // Add padding at the bottom to avoid being obscured by system UI
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}