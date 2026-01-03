// lib/models/onboarding_model.dart
import 'package:flutter/material.dart'; // Import for the IconData type

class OnboardingModel {
  final IconData icon; // Changed from String image to IconData icon
  final String title;
  final String description;

  OnboardingModel({
    required this.icon, // Now requires an IconData object
    required this.title,
    required this.description,
  });
}

// List of our onboarding pages with icons
List<OnboardingModel> onboardingData = [
  OnboardingModel(
    icon: Icons.camera_alt_rounded, // Perfect for "reporting"
    title: 'Report for a Better Environment',
    description: 'Snap a photo to help restore the beauty of our community.',
  ),
  OnboardingModel(
    icon: Icons.notifications_active_rounded, // Perfect for "tracking progress"
    title: 'Track Cleanup Progress',
    description: 'Get notified when your reported site has been cleaned up.',
  ),
  OnboardingModel(
    icon: Icons.emoji_nature_rounded, // Perfect for "making a difference"
    title: 'Make a Difference',
    description: 'Help keep your community clean and hold polluters accountable.',
  ),
];
