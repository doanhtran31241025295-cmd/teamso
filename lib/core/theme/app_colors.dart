import 'package:flutter/material.dart';

abstract final class AppColors {
  // Brand (khớp logo)
  static const green = Color(0xFF439751);
  static const purple = Color(0xFF867CB3);
  static const pink = Color(0xFFF472B6);
  static const yellow = Color(0xFFFACC15);
  static const darkPurple = Color(0xFF4D4379);

  // Neutral
  static const background = Color(0xFFFFFFFF);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFF8F7FA);
  static const border = Color(0xFFE8E6ED);
  static const textPrimary = Color(0xFF252331);
  static const textSecondary = Color(0xFF777482);
  static const inputBackground = Color(0xFFF8F7FA);

  // Semantic
  static const danger = Color(0xFFD94A4A);
  static const dangerSoft = Color(0xFFFCEEEE);
  static const successSoft = Color(0xFFEAF5EC);
  static const purpleSoft = Color(0xFFF0EEF7);
  static const pinkSoft = Color(0xFFFDEBF5);
  static const greenSoft = Color(0xFFEAF5EC);
  static const yellowSoft = Color(0xFFFFF6D6);
  static const workspaceDocument = (Color(0xFFE8F3F8), Color(0xFF477F9C));
  static const workspaceVote = (Color(0xFFFCEEF4), Color(0xFFA34076));
  static const workspaceMeeting = (Color(0xFFF0EAF8), Color(0xFF7860A3));

  static const pageHeader = Color(0xFF8371D0);
  static const pageTint = Colors.white;

  /// Gradient thương hiệu: tím -> hồng -> xanh lá.
  static const brandGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [purple, pink, green],
  );

  /// Gradient cho khối hero (tím đậm -> tím -> hồng).
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [darkPurple, purple, pink],
  );
}

/// Hằng màu thương hiệu dùng chung cho các màn hình (khai báo MỘT lần
/// duy nhất để tránh lỗi "ambiguous import" khi nhiều file cùng import).
const Color teamUpGreen = AppColors.green;
const Color teamUpPurple = AppColors.purple;
const Color teamUpPink = AppColors.pink;
const Color teamUpYellow = AppColors.yellow;
const Color teamUpDarkPurple = AppColors.darkPurple;
