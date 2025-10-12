class UserModel {
  final String fcmToken;
  final int threshold;

  UserModel({
    required this.fcmToken,
    required this.threshold,
  });

  factory UserModel.fromFirestore(Map<String, dynamic> data) {
    return UserModel(
      fcmToken: data['fcmToken'] ?? '',
      threshold: (data['aiRecommendationThreshold'] ?? 20).toInt(),
    );
  }
} 