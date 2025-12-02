import 'package:flutter/material.dart';

class AllLocationsScreen extends StatefulWidget {
  final Map<String, int> allLocations;

  const AllLocationsScreen({
    super.key,
    required this.allLocations,
  });

  @override
  State<AllLocationsScreen> createState() => _AllLocationsScreenState();
}

class _AllLocationsScreenState extends State<AllLocationsScreen> {
  late List<MapEntry<String, int>> _sortedLocations;
  List<MapEntry<String, int>> _filteredLocations = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Sort locations by count in descending order initially
    _sortedLocations = widget.allLocations.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    _filteredLocations = _sortedLocations;

    _searchController.addListener(_filterLocations);
  }

  void _filterLocations() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredLocations = _sortedLocations.where((entry) {
        return entry.key.toLowerCase().contains(query);
      }).toList();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('All Report Locations'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search locations',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
              ),
            ),
          ),
          Expanded(
            child: _filteredLocations.isEmpty
                ? Center(
                    child: Text(
                      'No locations match your search.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  )
                : ListView.builder(
                    itemCount: _filteredLocations.length,
                    itemBuilder: (context, index) {
                      final entry = _filteredLocations[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                          child: Text(
                            entry.value.toString(),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(entry.key),
                        subtitle: Text(
                          '${entry.value} ${entry.value == 1 ? "report" : "reports"}',
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}