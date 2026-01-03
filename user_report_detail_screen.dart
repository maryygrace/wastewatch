import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wastewatch/services/supabase_service.dart';

class UserReportDetailScreen extends StatefulWidget {
  final String reportId;

  const UserReportDetailScreen({super.key, required this.reportId});

  @override
  State<UserReportDetailScreen> createState() => _UserReportDetailScreenState();
}

class _UserReportDetailScreenState extends State<UserReportDetailScreen> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: SupabaseService.getReportStream(widget.reportId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text('Report Details')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('Report Details')),
            body: const Center(child: Text('Failed to load report details.')),
          );
        }

        final report = snapshot.data!;
    final status = report['status'] as String? ?? 'pending';
    final verificationCode = report['verification_code'] as String?;

    return Scaffold(
      appBar: AppBar(
        title: Text(report['title'] ?? 'Report Details'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Report Image
            if (report['imageUrl'] != null)
              FutureBuilder<String>(
                future: SupabaseService.getValidImageUrl(report['imageUrl']),
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(snapshot.data!, height: 200, width: double.infinity, fit: BoxFit.cover),
                    );
                  }
                  return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
                },
              ),
            const SizedBox(height: 16),
            
            // Title and Status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    report['title'] ?? 'Untitled',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
                _buildStatusChip(status),
              ],
            ),
            const SizedBox(height: 8),
            Text('Reported on: ${DateTime.parse(report['createdAt']).toLocal().toString().split('.')[0]}', style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 16),
            
            // Description
            if (report['description'] != null) ...[
              const Text('Description', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(report['description']),
              const SizedBox(height: 24),
            ],

            // QR Code Section (Only visible when In-Progress)
            if ((status == 'in-progress' || status == 'assigned') && verificationCode != null) ...[
              const Divider(),
              const SizedBox(height: 16),
              Center(
                child: Column(
                  children: [
                    const Text(
                      'Collection Verification',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Show this QR code to the collector to verify pickup.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withValues(alpha: 0.2),
                            spreadRadius: 2,
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: QrImageView(
                        data: verificationCode,
                        version: QrVersions.auto,
                        size: 200.0,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Code: $verificationCode',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: 2),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
      },
    );
  }

  Widget _buildStatusChip(String status) {
    Color color;
    switch (status) {
      case 'in-progress': color = Colors.blue; break;
      case 'resolved': color = Colors.green; break;
      default: color = Colors.orange;
    }
    return Chip(
      label: Text(status.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      backgroundColor: color,
    );
  }
}