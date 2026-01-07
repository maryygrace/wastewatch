import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wastewatch/services/supabase_service.dart';
import 'collector_report_detail_screen.dart';
import '../../theme_provider.dart';

import '../../services/logging_service.dart';

class CollectorHomeScreen extends StatefulWidget {
  const CollectorHomeScreen({super.key});

  @override
  State<CollectorHomeScreen> createState() => _CollectorHomeScreenState();
}

class _CollectorHomeScreenState extends State<CollectorHomeScreen> {
  int _selectedIndex = 0;
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  String? _errorMessage;

  // For availability and location tracking
  bool _isAvailable = false;
  Timer? _locationUpdateTimer;
  final Location _location = Location();

  // Stats
  String _selectedFilter = 'in-progress';
  int _resolvedToday = 0;
  int _totalAssigned = 0;
  int _totalResolved = 0;

  // New state for leaderboard and map
  List<Map<String, dynamic>> _leaderboard = [];
  List<Map<String, dynamic>> _assignedReportsForMap = [];
  String? _avatarUrl;

  // For notifications
  final List<Map<String, dynamic>> _notifications = [];
  int _newNotificationCount = 0;
  final MapController _mapController = MapController();

  static const List<String> _appBarTitles = <String>[
    'Dashboard',
    'Reports',
    'Notifications',
    'Profile',
  ];

  @override
  void initState() {
    super.initState();
    _loadCollectorData();
  }

  @override
  void dispose() {
    _stopLocationUpdates();
    super.dispose();
  }

  Future<void> _loadCollectorData() async {
    if (!mounted) {
      return;
    }
    setState(() => _isLoading = true);

    try {
      final user = SupabaseService.currentUser;
      if (user == null) throw Exception("User not found.");

      // Fetch all data in parallel, including the complete historical notification list.
      final results = await Future.wait([
        SupabaseService.getUserData(user.id),
        SupabaseService.getCollectorStats(user.id),
        SupabaseService.getCollectorLeaderboard(),
        SupabaseService.getAssignedReportsForMap(user.id),
        SupabaseService.getHistoricalAssignedNotifications(user.id),
        SupabaseService.getNewAssignedNotifications(user.id), // This will now only be used for the badge count and to update the DB.
      ]);

      final userData = results[0] as Map<String, dynamic>?;
      final collectorStats = results[1] as Map<String, dynamic>;
      final leaderboardData = results[2] as List<Map<String, dynamic>>;
      final mapData = results[3] as List<Map<String, dynamic>>;
      final historicalNotifications = results[4] as List<Map<String, dynamic>>;
      final newNotifications = results[5] as List<Map<String, dynamic>>;

      if (mounted) { // Ensure the widget is still mounted before updating state
        setState(() {
          _userData = userData;
          _avatarUrl = userData?['avatar_url'];
          _isAvailable = userData?['is_available'] ?? false;
          _resolvedToday = collectorStats['resolvedToday'] ?? 0;
          _totalAssigned = collectorStats['totalAssigned'] ?? 0;
          _totalResolved = collectorStats['totalResolved'] ?? 0;
          _leaderboard = leaderboardData;
          _assignedReportsForMap = mapData;
          
          // Clear the existing list and populate it with the definitive historical data.
          _notifications.clear();
          _notifications.addAll(historicalNotifications);

          if (newNotifications.isNotEmpty) {
            _newNotificationCount = newNotifications.length; // Set badge count
            _notifications.insertAll(0, newNotifications); // Prepend new notifications to ensure they are visible immediately
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("You have ${newNotifications.length} new report(s) assigned."),
                backgroundColor: Colors.blue,
              ),
            );
          }
        });

        if (_isAvailable) {
          _startLocationUpdates();
        }
      }
    } catch (e, stackTrace) {
      Log.e('Error loading collector data', e, stackTrace);
      if (mounted) {
        setState(() => _errorMessage = "Failed to load data: ${e.toString()}");
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _startLocationUpdates() async {
    if (!mounted) {
      return;
    }

    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) {
        Log.w('Location service is disabled.');
        return;
      }
    }

    PermissionStatus permissionGranted = await _location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await _location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) {
        Log.w('Location permission denied.');
        return;
      }
    }

    _locationUpdateTimer?.cancel(); // Cancel any existing timer
    _locationUpdateTimer = Timer.periodic(const Duration(minutes: 1), (timer) async {
      try {
        final user = SupabaseService.currentUser;
        if (user == null || !mounted || !_isAvailable) {
          timer.cancel(); // Stop if user logs out, widget is disposed, or goes offline
          return;
        }
        final locationData = await _location.getLocation();
        if (locationData.latitude != null && locationData.longitude != null) {
          await SupabaseService.updateUserLocation(user.id, locationData.latitude!, locationData.longitude!);
          Log.i('Updated collector location.');
        }
      } catch (e) {
        Log.e('Failed to get or update location', e);
      }
    });
  }

  void _stopLocationUpdates() {
    _locationUpdateTimer?.cancel();
    _locationUpdateTimer = null;
    Log.i('Stopped location updates.');
  }

  Future<void> _toggleAvailability(bool value) async {
    final user = SupabaseService.currentUser;
    if (user == null) {
      return;
    }

    setState(() => _isAvailable = value); // Optimistic UI update

    try {
      await SupabaseService.updateCollectorAvailability(user.id, value);
      if (value) {
        _startLocationUpdates();
      } else {
        _stopLocationUpdates();
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value ? 'You are now online.' : 'You have gone offline.'), backgroundColor: value ? Colors.green : Colors.orange));
      }
    } catch (e) {
      setState(() => _isAvailable = !value); // Revert on failure
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update status: ${e.toString()}'), backgroundColor: Colors.red));
      }
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      // If the user taps on the notifications tab (index 2), mark all as read.
      if (index == 2) {
        _newNotificationCount = 0;
      }
    });
  }

  void _navigateToReportsTab(String filter) {
    setState(() {
      _selectedIndex = 1; // Index of the 'Reports' tab
      _selectedFilter = filter;
    });
  }

  Future<void> _onUploadAvatar(String filePath) async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) {
        throw Exception("User not found. Please log in again.");
      }
      final fileExt = filePath.split('.').last;
      // Use timestamp to ensure unique filename and avoid caching issues
      final fileName = '${user.id}/avatar_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      await SupabaseService.uploadImageToStorage('avatars', fileName, File(filePath));
      final publicAvatarUrl = SupabaseService.getPublicImageUrl(fileName);
      await SupabaseService.updateUserProfile(user.id, {'avatar_url': publicAvatarUrl});
      setState(() {
        _avatarUrl = publicAvatarUrl;
      });
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Updated profile picture!')),
      );
    } on StorageException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Storage Error: ${e.message}')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
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
      _buildReportsTab(),
      _buildNotificationsTab(),
      _buildProfileTab(),
    ];

    
    return Scaffold(
      appBar: AppBar(        
        title: _selectedIndex == 0 ? Text(
          'WasteWatch',
          style: GoogleFonts.poppins(
            color: Colors.green,
            fontWeight: FontWeight.w700,
            fontSize: 22,
          ),
        ) : Text(_appBarTitles[_selectedIndex]),
        centerTitle: false,
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: widgetOptions,
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
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
    );
  }

  Widget _buildDashboardTab() {
    final collectorName = _userData?['full_name'] ?? 'Collector';
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
                    onTap: () => _navigateToReportsTab('in-progress'),
                    child: _buildStatCard(
                      'Currently Assigned',
                      _totalAssigned.toString(),
                      Colors.orange,
                      Icons.assignment_late,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded( // Wrap with GestureDetector to handle tap
                  child: GestureDetector(
                    onTap: () => _navigateToReportsTab('resolved'),
                    child: _buildStatCard(
                      'Resolved Today',
                      _resolvedToday.toString(),
                      Colors.green,
                      Icons.check_circle,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: _buildStatCard(
                'Total Resolved',
                _totalResolved.toString(),
                Colors.purple,
                Icons.history,
              ),
            ),
            const SizedBox(height: 20),

            // NEW: Assigned Reports Map
            _buildAssignedReportsMapCard(),
            const SizedBox(height: 20),

            // NEW: Leaderboard
            _buildLeaderboardCard(),
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

  Widget _buildLeaderboardCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Collector Leaderboard',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Card(
          elevation: 2,
          child: _leaderboard.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: Text('No leaderboard data available.')),
                )
              : Column(
                  children: _leaderboard.asMap().entries.map((entry) {
                    int idx = entry.key;
                    Map<String, dynamic> collector = entry.value;
                    IconData medalIcon;
                    Color medalColor;
                    switch (idx) {
                      case 0:
                        medalIcon = Icons.emoji_events;
                        medalColor = Colors.amber;
                        break;
                      case 1:
                        medalIcon = Icons.emoji_events;
                        medalColor = Colors.grey.shade400;
                        break;
                      case 2:
                        medalIcon = Icons.emoji_events;
                        medalColor = Colors.brown.shade400;
                        break;
                      default:
                        medalIcon = Icons.military_tech;
                        medalColor = Colors.transparent;
                    }
                    return ListTile(
                      leading: Icon(medalIcon, color: medalColor),
                      title: Text(
                        collector['full_name'] ?? 'Unknown Collector',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      trailing: Text(
                        '${collector['resolved_count']} reports',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  Widget _buildAssignedReportsMapCard() {
    final markers = _assignedReportsForMap.map((report) {
      return Marker(
        width: 80.0,
        height: 80.0,
        point: LatLng(report['latitude'], report['longitude']),
        child: Tooltip(
          message: report['title'] ?? 'Report',
          child: const Icon(Icons.location_pin, color: Colors.red, size: 30),
        ),
      );
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Assigned Report Locations',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 250,
          child: Card(
            clipBehavior: Clip.antiAlias,
            elevation: 2,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: markers.isNotEmpty ? markers.first.point : const LatLng(10.8702, 122.9566),
                initialZoom: 10.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.wastewatch',
                ),
                MarkerLayer(markers: markers),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReportsTab() {
    final collectorId = SupabaseService.currentUser?.id;
    if (collectorId == null) {
      return const Center(child: Text('User not found.'));
    }

    Stream<List<Map<String, dynamic>>> stream;
    if (_selectedFilter == 'in-progress') {
      stream = SupabaseService.getAssignedReportsStream(collectorId);
    } else {
      stream = SupabaseService.getResolvedReportsByCollectorStream(collectorId);
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        return Column(
          children: [
            _buildFilterButtons(),
            Expanded(child: _buildReportsList(snapshot)),
          ],
        );
      },
    );
  }

  Widget _buildFilterButtons() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'in-progress', label: Text('Assigned'), icon: Icon(Icons.assignment_late_outlined)),
          ButtonSegment(value: 'resolved', label: Text('Resolved'), icon: Icon(Icons.assignment_turned_in_outlined)),
        ],
        selected: {_selectedFilter},
        onSelectionChanged: (Set<String> newSelection) {
          setState(() {
            _selectedFilter = newSelection.first;
          });
        },
      ),
    );
  }

  Widget _buildReportsList(AsyncSnapshot<List<Map<String, dynamic>>> snapshot) {
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
            Icon(_selectedFilter == 'in-progress' ? Icons.task_alt : Icons.history, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              _selectedFilter == 'in-progress' ? 'No assigned reports.' : 'No resolved reports yet.',
              style: const TextStyle(fontSize: 18, color: Colors.grey),
            ),
            if (_selectedFilter == 'in-progress')
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
              MaterialPageRoute(builder: (context) => CollectorReportDetailScreen(reportId: report['id'])),
            );
          },
          child: _buildReportCard(report),
        );
      },
    );
  }
  Widget _buildNotificationsTab() {
    if (_notifications.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_off_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('You have no notifications.', style: TextStyle(fontSize: 18, color: Colors.grey)),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: _notifications.length,
      itemBuilder: (context, index) {
        final notification = _notifications[index];
        return ListTile(
          leading: const Icon(Icons.assignment_ind_outlined, color: Colors.blue),
          title: Text(notification['message']),
          subtitle: Text(DateTime.parse(notification['timestamp']).toLocal().toString().split('.')[0]),
          onTap: () {
            final reportId = notification['reportId'];
            if (reportId != null) {
              Navigator.push(context, MaterialPageRoute(builder: (context) => CollectorReportDetailScreen(reportId: reportId)));
            }
          },
        );
      },
    );
  }

  Widget _buildProfileTab() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final userEmail = _userData?['email'] ?? 'No email found';
    final userName = _userData?['full_name'] ?? 'User';
    final accountCreatedAt = _userData?['created_at'] != null ? DateTime.parse(_userData!['created_at']).toLocal().toString().split(' ')[0] : 'Unknown';

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        // User info card
        Center(
          child: Column(
            children: [
              GestureDetector(
                onTap: () async {
                  final imagePicker = ImagePicker();
                  final pickedFile = await imagePicker.pickImage(
                    source: ImageSource.gallery,
                    imageQuality: 50,
                    maxWidth: 400,
                  );
                  if (pickedFile != null) {
                    await _onUploadAvatar(pickedFile.path);
                  }
                },
                child: Stack(
                  children: [
                    _avatarUrl == null || _avatarUrl!.isEmpty
                        ? const CircleAvatar(
                            radius: 50,
                            backgroundColor: Colors.grey,
                            child: Icon(Icons.person, size: 50, color: Colors.white),
                          )
                        : CircleAvatar(
                            radius: 50,
                            backgroundImage: NetworkImage(_avatarUrl!),
                          ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.edit,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(userName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(userEmail, style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
              if (_userData?['location'] != null && _userData!['location'].isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.location_on_outlined, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(_userData!['location'], style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                  ],
                ),
              ],
              if (_userData?['bio'] != null && _userData!['bio'].isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(_userData!['bio'], style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic), textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          icon: const Icon(Icons.edit),
          label: const Text('Edit Profile'),
          onPressed: () {
            // Navigate to the edit profile screen
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => EditProfileScreen(
                  userData: _userData,
                  onProfileUpdated: (updatedData) {
                    setState(() {
                      _userData = updatedData;
                    });
                  },
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        const Divider(),

        _buildSectionHeader('Status'),
        SwitchListTile(
          title: const Text('Available for Collections'),
          subtitle: Text(_isAvailable ? 'You are online and will be assigned new reports.' : 'You are offline and will not receive new jobs.'),
          value: _isAvailable,
          onChanged: _toggleAvailability,
          secondary: Icon(
            _isAvailable ? Icons.location_on : Icons.location_off,
            color: _isAvailable ? Colors.green : Colors.grey,
          ),
        ),
        const Divider(height: 32),


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
        ListTile(
          leading: const Icon(Icons.account_circle),
          title: const Text('Account Created'),
          subtitle: Text(accountCreatedAt),
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

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic>? userData;
  final Function(Map<String, dynamic>) onProfileUpdated;

  const EditProfileScreen({super.key, this.userData, required this.onProfileUpdated});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _bioController = TextEditingController();
  final _locationController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fullNameController.text = widget.userData?['full_name'] ?? '';
    _bioController.text = widget.userData?['bio'] ?? '';
    _locationController.text = widget.userData?['location'] ?? '';
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _bioController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _updateProfile() async {
    if (_formKey.currentState!.validate()) {
      final fullName = _fullNameController.text.trim();
      final userId = SupabaseService.currentUser?.id;
      final bio = _bioController.text.trim();
      final location = _locationController.text.trim();

      if (userId != null) {
        try {
          final updates = {
            'full_name': fullName,
            'bio': bio,
            'location': location,
          };

          await SupabaseService.updateUserProfile(userId, updates);

          // Optimistically update the local state
          final updatedUserData = Map<String, dynamic>.from(widget.userData ?? {});
          updatedUserData['full_name'] = fullName;
          updatedUserData['bio'] = bio;
          updatedUserData['location'] = location;
          widget.onProfileUpdated(updatedUserData);

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile updated successfully!')),
          );
          Navigator.pop(context); // Close the edit screen
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update profile. Error: ${e.toString()}')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _fullNameController,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your full name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _bioController,
                decoration: const InputDecoration(labelText: 'Bio', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _locationController,
                decoration: const InputDecoration(labelText: 'Location', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: _updateProfile, child: const Text('Update Profile')),
            ],
          ),
        ),
      ),
    );
  }
}