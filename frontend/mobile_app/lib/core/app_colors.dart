import 'package:flutter/material.dart';

/// Uygulama genelinde uyumlu renk paleti.
/// Tüm ekranlar bu tonları kullanarak görsel bütünlük sağlar.
class AppColors {
  AppColors._();

  /// Arka plan üst (açık mavi-gri)
  static const Color backgroundTop = Color(0xFFE8F4F8);
  /// Arka plan alt (krem)
  static const Color backgroundBottom = Color(0xFFF5F5F0);
  /// Ana vurgu (mavi)
  static const Color primary = Color(0xFF5B9BD5);
  /// Ana vurgu açık (ikon arka planı vb.)
  static const Color primaryLight = Color(0xFFE3F2FD);
  /// Başlık / koyu metin
  static const Color textPrimary = Color(0xFF2C3E50);
  /// İkincil metin
  static const Color textSecondary = Color(0xFF6B7B8C);
  /// Kart / yüzey
  static const Color surface = Color(0xFFFFFFFF);
  /// Uyarı (stok az vb.)
  static const Color warning = Color(0xFFE65100);
  static const Color warningLight = Color(0xFFFFF3E0);
  /// Maviyle uyumlu ikincil vurgu (turuncu/amber)
  static const Color accent = Color(0xFFF5A623);
  static const Color accentLight = Color(0xFFFFF4E5);
}
