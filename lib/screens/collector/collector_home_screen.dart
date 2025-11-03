import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:wastewatch/services/supabase_service.dart';
import 'collector_report_detail_screen.dart';
import '../../theme_provider.dart';

class CollectorHomeScreen extends StatefulWidget {
  const CollectorHomeScreen({super.key});

  @override
  State<CollectorHomeScreen> createState() => _CollectorHomeScreenState();
}

class _CollectorHomeScreenState extends State<CollectorHomeScreen> {
  int _selectedIndex = 0;
  Map<String, dynamic>? _collectorData;
  bool _isLoading = true;
  String? _errorMessage;

  static const List<String> _appBarTitles = <String>[
    'Dashboard',
    'Assigned Reports',
    'Resolved Reports',
    'Profile'
  ];

  @override
  void initState() {
    super.initState();
    _loadCollectorData();
  }

  Future<void> _loadCollectorData() async {
    setState(() {
      _isLoading = _collectorData == null;
      _errorMessage = null;
    });

    try {
      final user = SupabaseService.currentUser;
      if (user == null) throw Exception("User not found.");

      final data = await SupabaseService.getUserData(user.id);
      if (mounted) setState(() => _collectorData = data);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = "Failed to load data.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Error")),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_errorMessage!),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _loadCollectorData, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final List<Widget> widgetOptions = <Widget>[
      _buildDashboardTab(),
      _buildReportsListTab(isAssigned: true),
      _buildReportsListTab(isAssigned: false),
      _buildProfileTab(),
    ];

    
    return Scaffold(
      appBar: AppBar(        
        title: _selectedIndex == 0
            ? Text(
                'WasteWatch',
                style: GoogleFonts.poppins(
                  color: Colors.green,
                  fontWeight: FontWeight.w700,
                  fontSize: 22,
                ),
              )
            : Text(_appBarTitles[_selectedIndex]),
        centerTitle: _selectedIndex == 0,
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: widgetOptions,
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), activeIcon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.assignment_late_outlined), activeIcon: Icon(Icons.assignment_late), label: 'Assigned'),
          BottomNavigationBarItem(icon: Icon(Icons.assignment_turned_in_outlined), activeIcon: Icon(Icons.assignment_turned_in), label: 'Resolved'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Profile'),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }

  Widget _buildDashboardTab() {
    final collectorId = SupabaseService.currentUser?.id;
    if (collectorId == null) return const Center(child: Text('User not found.'));

    return FutureBuilder<Map<String, dynamic>>(
      future: SupabaseService.getCollectorStats(collectorId),
      builder: (context, snapshot) {
        final resolvedToday = snapshot.data?['resolvedToday'] ?? 0;
        final totalAssigned = snapshot.data?['totalAssigned'] ?? 0;
        final collectorName = _collectorData?['full_name'] ?? 'Collector';
        return RefreshIndicator(
          onRefresh: _loadCollectorData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome, $collectorName!',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  'Here are your current stats:',
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded( // Wrap with GestureDetector to handle tap
                      child: GestureDetector(
                        onTap: () => _onItemTapped(1), // Navigate to "Assigned" tab (index 1)
                        child: _buildStatCard(
                          'Currently Assigned',
                          totalAssigned.toString(),
                          Colors.orange,
                          Icons.assignment_late,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded( // Wrap with GestureDetector to handle tap
                      child: GestureDetector(
                        onTap: () => _onItemTapped(2), // Navigate to "Resolved" tab (index 2)
                        child: _buildStatCard(
                          'Resolved Today',
                          resolvedToday.toString(),
                          Colors.green,
                          Icons.check_circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatCard(String title, String value, Color color, IconData icon) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Icon(icon, color: color, size: 40),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportsListTab({required bool isAssigned}) {
    final collectorId = SupabaseService.currentUser?.id;
    if (collectorId == null) return const Center(child: Text('User not found.'));

    final stream = isAssigned
        ? SupabaseService.getAssignedReportsStream(collectorId)
        : SupabaseService.getResolvedReportsByCollectorStream(collectorId);

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error fetching reports: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(isAssigned ? Icons.task_alt : Icons.history, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  isAssigned ? 'No assigned reports.' : 'No resolved reports yet.',
                  style: const TextStyle(fontSize: 18, color: Colors.grey),
                ),
                if (isAssigned)
                  const Text(
                    'Great job!',
                    style: TextStyle(color: Colors.grey),
                  ),
              ],
            ),
          );
        }

        final reports = snapshot.data!;
        return ListView.builder(
          padding: const EdgeInsets.all(16.0),
          itemCount: reports.length,
          itemBuilder: (context, index) {
            final report = reports[index];
            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => CollectorReportDetailScreen(reportId: report['id'])),
                );
              },
              child: _buildReportCard(report),
            );
          },
        );
      },
    );
  }

  Widget _buildProfileTab() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final userEmail = _collectorData?['email'] ?? 'No email found';
    final userName = _collectorData?['full_name'] ?? 'Collector';

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        // User info card
        Center(
          child: Column(
            children: [
              CircleAvatar(
                radius: 50,
                backgroundColor: Colors.grey,
                child: Icon(Icons.person, size: 50, color: Colors.white),
              ),
              const SizedBox(height: 16),
              Text(userName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(userEmail, style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Divider(),

        SwitchListTile(
          title: const Text('Dark Mode'),
          subtitle: const Text('Reduce eye strain in low light'),
          value: themeProvider.themeMode == ThemeMode.dark,
          onChanged: (bool value) {
            themeProvider.toggleTheme(value);
          },
          secondary: const Icon(Icons.dark_mode_outlined),
        ),
        const Divider(height: 32),
        ListTile(
          leading: const Icon(Icons.logout, color: Colors.red),
          title: const Text('Log Out', style: TextStyle(color: Colors.red)),
          onTap: () => _showLogoutConfirmationDialog(),
        ),
      ],
    );
  }

  Widget _buildReportCard(Map<String, dynamic> data) {
    final status = data['status'] ?? 'unknown';
    Color statusColor;
    switch (status) {
      case 'in-progress':
        statusColor = Colors.blue;
        break;
      case 'resolved':
        statusColor = Colors.green;
        break;
      case 'pending':
      default:
        statusColor = Colors.orange;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    data['title'] ?? 'Untitled Report',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha((255 * 0.2).round()),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (data['description'] != null && data['description'].isNotEmpty)
              Text(data['description']),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.category, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  data['wasteCategory']?.toString().toUpperCase() ?? 'UNCATEGORIZED',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(width: 16),
                Icon(Icons.calendar_today, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  data['createdAt'] != null
                      ? DateTime.parse(data['createdAt']).toLocal().toString().split(' ')[0]
                      : 'Unknown date',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
            if (data['imageUrl'] != null) ...[
              const SizedBox(height: 12),
              FutureBuilder<String>(
                future: SupabaseService.getValidImageUrl(data['imageUrl'] as String),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox(
                      height: 150,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError || !snapshot.hasData) {
                    return const SizedBox(
                      height: 150,
                      child: Center(child: Icon(Icons.error, color: Colors.red, size: 40)),
                    );
                  }
                  return SizedBox(
                    width: double.infinity,
                    height: 150,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        image: DecorationImage(image: NetworkImage(snapshot.data!), fit: BoxFit.cover),
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showLogoutConfirmationDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Log Out'),
          content: const Text('Are you sure you want to log out?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(dialogContext).pop(); // Dismiss the dialog
              },
            ),
            TextButton(
              child: const Text('Log Out', style: TextStyle(color: Colors.red)),
              onPressed: () async {
                Navigator.of(dialogContext).pop(); // Dismiss the dialog
                final navigator = Navigator.of(context);
                await SupabaseService.signOut();
                navigator.pushNamedAndRemoveUntil('/auth', (route) => false);
              },
            ),
          ],
        );
      },
    );
  }
}