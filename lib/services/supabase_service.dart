import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import '../models/user_role.dart';
import 'logging_service.dart';

class SupabaseService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static User? get currentUser => _supabase.auth.currentUser;

  /// Check if a user document exists in the 'users' table.
  static Future<bool> userExistsInDb(String uid) async {
    try {
      final response = await _supabase
          .from('users')
          .select()
          .eq('uid', uid)
          .maybeSingle();
      return response != null;
    } catch (e) {
      Log.e('Error checking if user exists in database', e);
      return false;
    }
  }

  /// Create a new user entry in the 'users' table.
  static Future<void> createUserInDb({
    required String uid,
    required String email,
    required UserRole role,
    required String fullName,
  }) async {
    try {
      await _supabase.from('users').insert({
        'uid': uid,
        'email': email,
        'role': role.value,
        'full_name': fullName,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      Log.e('Error creating user in database', e);
      rethrow;
    }
  }

  /// Get a user's data from the 'users' table.
  static Future<Map<String, dynamic>?> getUserData(String uid) async {
    try {
      final response = await _supabase
          .from('users')
          .select()
          .eq('uid', uid)
          .single();

      return response;
    } catch (e) {
      Log.e('Error getting user data for uid: $uid', e);
      return null;
    }
  }

  /// Get a user's role from the 'users' table.
  static Future<UserRole?> getUserRole(String uid) async {
    try {
      final userData = await getUserData(uid);
      if (userData != null && userData['role'] != null) {
        return UserRole.fromString(userData['role']);
      }
      return null;
    } catch (e) {
      Log.e('Error getting user role for uid: $uid', e);
      return null;
    }
  }

  /// Record a login activity in the 'user_logins' table.
  static Future<void> recordLoginActivity({
    String? userId,
    required String email,
    required String status,
    String? failureReason,
  }) async {
    try {
      await _supabase.from('user_logins').insert({
        'user_id': userId,
        'email': email,
        'login_time': DateTime.now().toIso8601String(),
        'status': status,
        'failure_reason': failureReason,
      });
    } catch (e) {
      Log.e('Error recording login activity', e);
    }
  }

  /// Get a stream of a user's reports.
  static Stream<List<Map<String, dynamic>>> getUserReports(String userId, {int limit = 10}) {
    return _supabase
        .from('reports')
        .stream(primaryKey: ['id'])
        .eq('userId', userId)
        .order('createdAt', ascending: false)
        .limit(limit);
  }

  /// Get a stream of all assigned (pending or in-progress) reports for collectors.
  static Stream<List<Map<String, dynamic>>> getAssignedReportsStream(String collectorId) {
    return _supabase
        .from('reports')
        .stream(primaryKey: ['id']).order('assigned_at', ascending: true).map((reports) {
      // Post-filter the stream on the client-side for multiple conditions.
      return reports
          .where((report) =>
              report['collector_id'] == collectorId &&
              report['status'] == 'in-progress')
          .toList();
    });
  }

  /// Get a stream of all reports for an admin, filterable by status.
  static Stream<List<Map<String, dynamic>>> getAllReportsStream({String? status}) {
    final query = _supabase.from('reports').stream(primaryKey: ['id']);
    if (status != null) {
      return query.eq('status', status).order('createdAt', ascending: true);
    }
    return query
        .order('createdAt', ascending: true);
  }

  /// Get a stream of resolved reports for a specific collector.
  static Stream<List<Map<String, dynamic>>> getResolvedReportsByCollectorStream(String collectorId) {
    return _supabase
        .from('reports')
        .stream(primaryKey: ['id']).eq('status', 'resolved').order('resolved_at', ascending: false).map(
            (reports) => reports.where((report) => report['resolved_by'] == collectorId).toList());
  }

  /// Get a single report by ID.
  static Future<Map<String, dynamic>?> getReport(String reportId) async {
    try {
      final response = await _supabase
          .from('reports')
          .select()
          .eq('id', reportId)
          .single();
      return response;
    } catch (e) {
      Log.e('Error getting report: $reportId', e);
      return null;
    }
  }

  /// Get a user's statistics from the 'user_stats' table.
  static Future<Map<String, dynamic>?> getUserStats(String userId) async {
    try {
      final response = await _supabase
          .from('user_stats')
          .select()
          .eq('user_id', userId)
          .single();

      return response;
    } catch (e) {
      Log.e('Error getting user stats for uid: $userId', e);
      return null;
    }
  }

  /// Gets statistics for a collector's dashboard.
  static Future<Map<String, dynamic>> getCollectorStats(String collectorId) async {
    try {
      // Get reports resolved today
      final today = DateTime.now();
      final startOfToday = DateTime(today.year, today.month, today.day).toIso8601String();

      final resolvedTodayResponse = await _supabase
          .from('reports')
          .select('id')
          .eq('resolved_by', collectorId)
          .gte('resolved_at', startOfToday);
      final resolvedTodayCount = resolvedTodayResponse.length;

      // Get total reports assigned to this collector that are 'in-progress'
      final assignedResponse = await _supabase
          .from('reports')
          .select('id')
          .eq('collector_id', collectorId)
          .eq('status', 'in-progress');
      final assignedCount = assignedResponse.length;

      return {
        'resolvedToday': resolvedTodayCount,
        'totalAssigned': assignedCount,
      };
    } catch (e, stackTrace) {
      Log.e('Error getting collector stats', e, stackTrace);
      return {
        'resolvedToday': 0,
        'totalAssigned': 0,
      };
    }
  }

  /// Calculates user statistics on the fly by querying the reports table.
  /// This is more resource-intensive but ensures data is always accurate.
  static Future<Map<String, dynamic>> calculateUserStats(String userId) async {
    try {
      final reports = await _supabase
          .from('reports')
          .select('status, wasteCategory, location')
          .eq('userId', userId);

      int totalReports = reports.length;
      int resolvedReports =
          reports.where((r) => r['status'] == 'resolved').length;

      final Map<String, int> locationBreakdown = {};
      for (final report in reports) {
        final location = report['location'] as String?;
        if (location != null && location.isNotEmpty) {
          locationBreakdown.update(location, (value) => value + 1, ifAbsent: () => 1);
        }
      }

      Map<String, int> wasteBreakdown = {
        'biodegradable': 0,
        'recyclable': 0,
        'residual': 0,
      };

      for (var report in reports) {
        final categories = (report['wasteCategory'] as String?)?.split(',') ?? [];
        for (var category in categories) {
          if (wasteBreakdown.containsKey(category)) {
            wasteBreakdown[category] = wasteBreakdown[category]! + 1;
          }
        }
      }

      return {
        'totalReports': totalReports,
        'resolvedReports': resolvedReports,
        'locationBreakdown': locationBreakdown,
        ...wasteBreakdown,
      };
    } catch (e, stackTrace) {
      Log.e('Error calculating user stats for uid: $userId', e, stackTrace);
      // Return zeroed stats on error to prevent crashing the UI.
      return {'totalReports': 0, 'resolvedReports': 0, 'biodegradable': 0, 'recyclable': 0, 'residual': 0, 'locationBreakdown': <String, int>{}};
    }
  }

  /// Create a new report in the 'reports' table.
  static Future<void> createReport(Map<String, dynamic> reportData) async {
    try {
      await _supabase.from('reports').insert(reportData);
    } catch (e) {
      Log.e('Error creating report', e);
      rethrow;
    }
  }

  /// Update an existing report.
  static Future<void> updateReport(String reportId, Map<String, dynamic> updates) async {
    try {
      await _supabase.from('reports').update({
        ...updates,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', reportId);
    } catch (e) {
      Log.e('Error updating report: $reportId', e);
      rethrow; }
  }

  /// Delete a report.
  static Future<void> deleteReport(String reportId) async {
    try {
      await _supabase.from('reports').delete().eq('id', reportId);
    } catch (e) {
      Log.e('Error deleting report: $reportId', e);
      rethrow;
    }
  }

  /// Update user statistics.
  static Future<void> updateUserStats(String userId, Map<String, dynamic> stats) async {
    try {
      await _supabase.from('user_stats').update({
        ...stats,
        'last_updated': DateTime.now().toIso8601String(),
      }).eq('user_id', userId);
    } catch (e) {
      Log.e('Error updating user stats for uid: $userId', e);
      rethrow;
    }
  }

  /// Update user profile.
  static Future<void> updateUserProfile(String userId, Map<String, dynamic> updates) async {
    try {
      await _supabase.from('users').update({
        ...updates,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('uid', userId);

    } catch (e) { rethrow; }
  }

  /// Sign out the current user.
  static Future<void> signOut() async {
    try {
      Log.i('User signing out.');
      await _supabase.auth.signOut();
    } catch (e) {
      Log.e('Error signing out', e);
      rethrow;
    }
  }

  /// Upload an image to Supabase Storage.
  static Future<String> uploadImageToStorage(String bucket, String path, File file) async {
    try {
      await _supabase.storage.from(bucket).upload(path, file);
      Log.i('Image uploaded to path: $path');
      // Return the path, not the URL. We will generate signed URLs on the fly.
      return path;
    } catch (e) {
      Log.e('Error uploading image to storage', e);
      rethrow;
    }
  }

  /// Intelligently creates a fresh, valid signed URL for a report image.
  /// This handles cases where the stored value is an old, expired signed URL,
  /// a public URL, or just the raw path. This works for both public and private buckets.
  static Future<String> getValidImageUrl(String imageUrl) async {
    String imagePath;
    const String bucketMarker = 'report_images/';
    final pathIndex = imageUrl.lastIndexOf(bucketMarker);

    if (pathIndex != -1) {
      // Extract the path from a full URL (signed or public)
      imagePath = imageUrl.substring(pathIndex + bucketMarker.length);
    } else {
      // Assume the stored string is already just the path
      imagePath = imageUrl;
    }

    // Remove query parameters if they exist (from old signed URLs)
    final queryIndex = imagePath.indexOf('?');
    if (queryIndex != -1) {
      imagePath = imagePath.substring(0, queryIndex);
    }

    // Create a new signed URL with a 1-hour validity.
    return await _supabase.storage
        .from('report_images')
        .createSignedUrl(imagePath, 3600);
  }

  /// Gets all historical "resolved" notifications for a user.
  static Future<List<Map<String, dynamic>>> getHistoricalNotifications(String userId) async {
    try {
      final response = await _supabase
          .from('reports')
          .select('id, title, resolved_at')
          .eq('userId', userId)
          .eq('status', 'resolved')
          .order('resolved_at', ascending: false);

      return response.map((report) {
        return {
          'reportId': report['id'], // Add the reportId here
          'message': "Your report '${report['title']}' has been resolved!",
          'timestamp': report['resolved_at'] ?? DateTime.now().toIso8601String(),
        };
      }).toList();
    } catch (e, stackTrace) {
      Log.e('Error getting historical notifications', e, stackTrace);
      return [];
    }
  }
}
