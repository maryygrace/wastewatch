import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import '../../services/logging_service.dart';
import '../../theme_provider.dart';
import 'report_submission_screen.dart';
import 'user_report_detail_screen.dart';

class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen> {
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  String? _errorMessage;
  int _selectedIndex = 0;

  // Statistics data
  int _totalReports = 0;
  int _resolvedReports = 0;
  Map<String, int> _wasteBreakdown = {
    'biodegradable': 0,
    'recyclable': 0,
    'residual': 0,
  };
  // Separate state for location breakdown to resolve type mismatch
  Map<String, int> _locationBreakdown = {};

  // For notifications
  final List<Map<String, dynamic>> _notifications = [];
  int _newNotificationCount = 0;

  // Define colors for waste categories
  final Map<String, Color> _categoryColors = {
    'biodegradable': Colors.green,
    'recyclable': Colors.blue,
    'residual': Colors.orange,
  };

  // Titles for AppBar
  static const List<String> _appBarTitles = <String>[
    'Dashboard',
    'My Reports',
    'Notifications',
    'Profile',
  ];

  @override
  void initState() {
    super.initState();
    // Initial data load
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    // This method will now be the single source of truth for refreshing all user-related data.
    setState(() {
      // Only show full-screen loader on first load, not on pull-to-refresh
      _isLoading = _userData == null;
      _errorMessage = null;
    });

    try {
      final user = SupabaseService.currentUser;
      if (user == null) {
        throw Exception("User not found. Please log in again.");
      }

      // Fetch data in parallel for better performance
      final results = await Future.wait([
        SupabaseService.getUserData(user.id),
        SupabaseService.calculateUserStats(user.id), // Now calculates stats directly
        SupabaseService.getHistoricalNotifications(user.id),
        _getNewNotifications(user.id),
      ]);

      if (!mounted) return;

      final userData = results[0] as Map<String, dynamic>?;
      final userStats = results[1] as Map<String, dynamic>; // This is now non-nullable
      final historicalNotifications = results[2] as List<Map<String, dynamic>>;
      final newNotifications = results[3] as List<Map<String, dynamic>>?;

      // User data is critical. If it's null, we can't proceed.
      if (userData == null) {
        throw Exception("Could not retrieve essential user profile data.");
      }

      setState(() {
        _notifications.clear(); // Clear before adding to prevent duplicates on refresh
        _userData = userData;
        // Stats are now calculated directly, ensuring they are always available.
        _totalReports = userStats['totalReports'] ?? 0;
        _resolvedReports = userStats['resolvedReports'] ?? 0;
        _wasteBreakdown = {
          'biodegradable': userStats['biodegradable'] ?? 0,
          'recyclable': userStats['recyclable'] ?? 0,
          'residual': userStats['residual'] ?? 0,
        };

        // Add all historical notifications first
        _notifications.addAll(historicalNotifications);

        // Prepend new notifications so they appear at the top of the list.
        _notifications.insertAll(0, newNotifications ?? []);

        _locationBreakdown = Map<String, int>.from(userStats['locationBreakdown'] ?? {});

        if (newNotifications != null && newNotifications.isNotEmpty) {
          // Set the badge count and show a snackbar for the newest notification.
          _newNotificationCount = newNotifications.length;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(newNotifications.first['message']),
              backgroundColor: Colors.green,
            ),
          );
        }
      });
    } catch (e, stackTrace) {
      if (!mounted) return; // Check mounted status before showing error.
      setState(() {
        _errorMessage = 'Failed to load user data. Please try again.';
      });
      Log.e('Error loading user data', e, stackTrace);
    } finally {
      if (mounted) {
        _isLoading = false;
      }
    }
  }

  Future<List<Map<String, dynamic>>> _getNewNotifications(String userId) async {
    try {
      final response = await Supabase.instance.client
          .from('reports')
          .select('id, title')
          .eq('userId', userId)
          .eq('status', 'resolved')
          .eq('resolutionNotified', false);

      if (response.isEmpty) return [];

      final List<Map<String, dynamic>> newNotifications = [];
      final List<String> reportIdsToUpdate = [];

      for (final report in response) {
        newNotifications.add({
          'type': 'report_resolved',
          'message': "Your report '${report['title']}' has been resolved!",
          'reportId': report['id'],
          'timestamp': DateTime.now().toIso8601String(),
        });
        reportIdsToUpdate.add(report['id'] as String);
      }

      // Mark all as notified in a single batch operation
      await Supabase.instance.client
          .from('reports')
          .update({'resolutionNotified': true}).inFilter('id', reportIdsToUpdate);

      return newNotifications;
    } catch (e, stackTrace) {
      Log.e('Error checking for resolved reports', e, stackTrace);
      // Return an empty list to prevent the entire refresh from failing.
      return [];
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      // If the user taps on the notifications tab (index 2), mark all as read.
      if (index == 2) {
        // This will make the badge disappear but keep the items in the list.
        _newNotificationCount = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Define the widgets for each tab to be used in IndexedStack
    final List<Widget> widgetOptions = <Widget>[
      _buildDashboard(),
      _buildReportsList(),
      _buildNotificationsList(),
      _buildProfileScreen(),
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
        elevation: 1,
      ),
      body: _buildBody(widgetOptions),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed, // Ensures all labels are visible
        items: <BottomNavigationBarItem>[
          const BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), activeIcon: Icon(Icons.dashboard), label: 'Dashboard'),
          const BottomNavigationBarItem(icon: Icon(Icons.list_alt_outlined), activeIcon: Icon(Icons.list_alt), label: 'Reports'),
          BottomNavigationBarItem(
            icon: Badge(label: Text(_newNotificationCount.toString()), isLabelVisible: _newNotificationCount > 0, child: const Icon(Icons.notifications_outlined)),
            activeIcon: Badge(label: Text(_newNotificationCount.toString()), isLabelVisible: _newNotificationCount > 0, child: const Icon(Icons.notifications)),
            label: 'Notifications',
          ),
          const BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Profile'),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ReportSubmissionScreen(),
                  ),
                );
                // Refresh data after returning from submission screen
                _loadUserData();
              },
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              tooltip: 'Submit Report',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildDashboard() {
    return RefreshIndicator(
      onRefresh: _loadUserData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome message
            Text(
              'Welcome, ${_userData?['full_name'] ?? 'User'}!',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'Here\'s your waste reporting dashboard',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),

            // Statistics cards
            const Text(
              'Dashboard Overview',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Pending',
                    (_totalReports - _resolvedReports).toString(),
                    Colors.orange,
                    Icons.pending,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildStatCard(
                    'Resolved',
                    _resolvedReports.toString(),
                    Colors.green,
                    Icons.check_circle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Total Reports',
                    _totalReports.toString(),
                    Colors.blue,
                    Icons.description,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Waste breakdown
            const Text(
              'Waste Breakdown',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            _buildWasteBreakdownChart(),
            const SizedBox(height: 20),

            // Reports by Location
            const Text(
              'Reports by Location',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            _buildLocationBreakdownCard(),
            const SizedBox(height: 20),

          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Color color, IconData icon) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWasteBreakdownChart() {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: _wasteBreakdown.entries.map((entry) {
            String category = entry.key;
            int count = entry.value;
            Color color = _categoryColors[category] ?? Colors.grey;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5.0),
              child: _buildWasteCategoryRow(
                category.replaceFirst(category[0], category[0].toUpperCase()),
                count,
                color,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildWasteCategoryRow(String category, int count, Color color) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            category,
            style: const TextStyle(fontSize: 16),
          ),
        ),
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildLocationBreakdownCard() {
    // Sort locations by report count, descending, and take the top 5
    final sortedLocations = _locationBreakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topLocations = sortedLocations.take(5).toList();

    if (topLocations.isEmpty) {
      return const Card(
        elevation: 3,
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Center(child: Text('No location data available yet.', style: TextStyle(color: Colors.grey))),
        ),
      );
    }

    // The highest count will represent 100% of the progress bar width
    final maxCount = topLocations.first.value;

    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: List.generate(topLocations.length, (index) {
            final entry = topLocations[index];
            final locationName = _getShortLocationName(entry.key);
            final count = entry.value;
            final percentage = maxCount > 0 ? count / maxCount : 0.0;

            return _buildLocationBar(context, locationName, count, percentage);
          }),
        ),
      ),
    );
  }

  Widget _buildLocationBar(BuildContext context, String name, int count, double percentage) {
    final colorScheme = Theme.of(context).colorScheme;
    final primaryColor = colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  name,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                count.toString(),
                style: TextStyle(fontWeight: FontWeight.bold, color: primaryColor, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: percentage.clamp(0.0, 1.0), // Ensure value is within valid range
              minHeight: 8,
              backgroundColor: primaryColor.withAlpha((255 * 0.2).round()),
              valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
            ),
          ),
        ],
      ),
    );
  }

  String _getShortLocationName(String fullLocation) {
    // This function provides a cleaner, more readable name for the chart axis.
    // The full name is still available in the bar's tooltip on tap.
    final locationParts = fullLocation.split(',').map((e) => e.trim()).toList();
    String shortName = fullLocation; // Default to the full string

    if (locationParts.length > 2) {
      // e.g., "Street, Bacolod, Negros Occidental" -> "Street"
      shortName = locationParts.first;
    } else if (locationParts.length == 2) {
      // e.g., "Bacolod, Negros Occidental" -> "Bacolod"
      shortName = locationParts.first;
    }
    return shortName;
  }

  Widget _buildReportsList() {
    final user = SupabaseService.currentUser;
    if (user == null) {
      return const Center(child: Text('No user logged in'));
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: SupabaseService.getUserReports(user.id),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.description, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'No reports yet',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
                SizedBox(height: 8),
                Text(
                  'Submit your first report to get started',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16.0),
          itemCount: snapshot.data!.length,
          itemBuilder: (context, index) {
            final report = snapshot.data![index];
            return GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => UserReportDetailScreen(reportId: report['id'])),
              ),
              child: _buildReportCard(report['id'], report),
            );
          },
        );
      },
    );
  }

  Widget _buildBody(List<Widget> widgetOptions) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadUserData,
                child: const Text('Retry'),
              )
            ],
          ),
        ),
      );
    }

    return IndexedStack(
      index: _selectedIndex,
      children: widgetOptions,
    );
  }

  Widget _buildNotificationsList() {
    if (_notifications.isEmpty) {
      return const Center(
        child: Text('You have no new notifications.'),
      );
    }
    return ListView.builder(
      itemCount: _notifications.length,
      itemBuilder: (context, index) {
        final notification = _notifications[index];
        return ListTile(
          leading: Icon(
            notification['type'] == 'report_resolved' ? Icons.check_circle : Icons.notification_important,
            color: Colors.green,
          ),
          title: Text(notification['message']),
          subtitle: Text(DateTime.parse(notification['timestamp']).toLocal().toString().split('.')[0]),
          onTap: () {
            final reportId = notification['reportId'];
            if (reportId != null) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => UserReportDetailScreen(reportId: reportId)),
              );
            }
          },
        );
      },
    );
  }

  Widget _buildReportCard(String reportId, Map<String, dynamic> data) {
    Color statusColor = Colors.orange; // Pending
    if (data['status'] == 'in-progress') {
      statusColor = Colors.blue;
    } else if (data['status'] == 'resolved') {
      statusColor = Colors.green;
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
                Text(
                  data['title'] ?? 'Untitled Report',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha((255 * 0.2).round()),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    data['status']?.toString().toUpperCase() ?? 'UNKNOWN',
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
            if (data['description'] != null && data['description'].isNotEmpty) Text(data['description']),
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

  Widget _buildProfileScreen() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final userEmail = _userData?['email'] ?? 'No email found';
    final userName = _userData?['full_name'] ?? 'User';

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        // User info card
        Center(
          child: Column(
            children: [
              const CircleAvatar(
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

        // Re-using settings screen content
        _buildSectionHeader('Preferences'),
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
        _buildSectionHeader('Account'),
        ListTile(
          leading: const Icon(Icons.logout, color: Colors.red),
          title: const Text('Log Out', style: TextStyle(color: Colors.red)),
          onTap: () => _showLogoutConfirmationDialog(),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: Theme.of(context).primaryColor,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
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
