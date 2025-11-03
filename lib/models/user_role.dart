// lib/models/user_role.dart
enum UserRole {
  user('user', 'User'),
  collector('collector', 'Data Collector'),
  admin('admin', 'Administrator');

  final String value;
  final String displayName;
  const UserRole(this.value, this.displayName);

  // Helper method to convert from string
  static UserRole fromString(String value) {
    return UserRole.values.firstWhere(
      (role) => role.value == value,
      orElse: () => UserRole.user, // Default to user if not found
    );
  }

  // Check if user has admin privileges
  bool get isAdmin => this == UserRole.admin;

  // Check if user has collector privileges
  bool get isCollector => this == UserRole.collector || this == UserRole.admin;

  // Check if user has basic user privileges
  bool get isUser => this == UserRole.user;

  // Get all roles as a list of strings (for dropdowns, etc.)
  static List<String> get allValues {
    return UserRole.values.map((role) => role.value).toList();
  }

  // Get all display names as a list of strings
  static List<String> get allDisplayNames {
    return UserRole.values.map((role) => role.displayName).toList();
  }

  // Get role from display name
  static UserRole fromDisplayName(String displayName) {
    return UserRole.values.firstWhere(
      (role) => role.displayName == displayName,
      orElse: () => UserRole.user,
    );
  }

  // Get permissions for this role
  Map<String, bool> get permissions {
    switch (this) {
      case UserRole.admin:
        return {
          'viewReports': true,
          'createReports': true,
          'editReports': true,
          'deleteReports': true,
          'viewAllData': true,
          'manageUsers': true,
          'viewAnalytics': true,
        };
      case UserRole.collector:
        return {
          'viewReports': true,
          'createReports': true,
          'editReports': true,
          'deleteReports': false,
          'viewAllData': false,
          'manageUsers': false,
          'viewAnalytics': true,
        };
      case UserRole.user:
        return {
          'viewReports': true,
          'createReports': true,
          'editReports': false,
          'deleteReports': false,
          'viewAllData': false,
          'manageUsers': false,
          'viewAnalytics': false,
        };
    }
  }

  // Check if this role has a specific permission
  bool hasPermission(String permission) {
    return permissions[permission] ?? false;
  }

  @override
  String toString() => value;
}