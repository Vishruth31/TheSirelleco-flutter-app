import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../widgets/ai_help_popup.dart';

// --------------------------------------------------
// 🔮 Predictive Feature Usage Engine
// --------------------------------------------------
// This engine watches navigation patterns and predicts
// which screen the user may open next.
// --------------------------------------------------

class PredictiveEngine {
  static final Map<String, List<String>> _navigationHistory = {};
  // 🔮 Stores learned navigation transitions (session learning)
  static final Map<String, Map<String, Map<String, int>>> _transitionCounts = {};
  // 🧠 Recent home navigation memory (used for smarter prediction)
  static final Map<String, List<String>> _recentHomeTargets = {};

  static BuildContext? appContext;
  // ⏱️ Smart anti‑spam system for AI popup
  static final Map<String, DateTime> _lastSuggestionTime = {};
  static final Map<String, String> _lastSuggestedPage = {};
  static final Map<String, String> _lastPrediction = {};
  static const Duration _cooldown = Duration(seconds: 20);

  static void setContext(BuildContext context) {
    appContext = context;
  }

  // --------------------------------------------------
  // Record Navigation Events
  // --------------------------------------------------
  static void recordNavigation({
    required String userId,
    required String screen,
    required String action,
  }) {
    // We only care about navigation-type actions
    if (action != "navigation" && action != "open") return;

    _navigationHistory.putIfAbsent(userId, () => []);
    _navigationHistory[userId]!.add(screen);
    if (_navigationHistory[userId]!.length > 6) {
      _navigationHistory[userId]!.removeAt(0);
    }

    _runPrediction(userId);
  }

  // --------------------------------------------------
  // 🔮 Smart Recent-Behaviour Prediction Logic
  // --------------------------------------------------
  static void _runPrediction(String userId) {
    _navigationHistory.putIfAbsent(userId, () => []);
    _recentHomeTargets.putIfAbsent(userId, () => []);
    _transitionCounts.putIfAbsent(userId, () => {});

    if (_navigationHistory[userId]!.length < 2) return;

    final last = _navigationHistory[userId]![_navigationHistory[userId]!.length - 1];
    final prev = _navigationHistory[userId]![_navigationHistory[userId]!.length - 2];

    // --------------------------------------------------
    // 🧠 Learn transition globally (kept for backend analytics)
    // --------------------------------------------------
    _transitionCounts[userId]!.putIfAbsent(prev, () => {});
    _transitionCounts[userId]![prev]![last] =
        (_transitionCounts[userId]![prev]![last] ?? 0) + 1;

    // --------------------------------------------------
    // 🔥 Learn only Home → OtherPage transitions
    // --------------------------------------------------
    if (prev == "home_page" && last != "home_page") {
      _recentHomeTargets[userId]!.add(last);

      // Keep only last 6 transitions
      if (_recentHomeTargets[userId]!.length > 6) {
        _recentHomeTargets[userId]!.removeAt(0);
      }
    }

    // --------------------------------------------------
    // 🔮 Predict ONLY when landing on HOME
    // --------------------------------------------------
    if (last != "home_page") return;

    if (_recentHomeTargets[userId]!.length < 2) return;

    // 🔥 STREAK-BASED detection (most recent repeated behaviour wins)
    String? predicted;

    final latest = _recentHomeTargets[userId]!.last;
    int streak = 0;

    for (int i = _recentHomeTargets[userId]!.length - 1; i >= 0; i--) {
      if (_recentHomeTargets[userId]![i] == latest) {
        streak++;
      } else {
        break;
      }
    }

    // Require at least 2 consecutive visits from home
    if (streak >= 2) {
      predicted = latest;
    }

    if (predicted != null) {
      _lastPrediction[userId] = predicted; // store for UI display
      _showSuggestion(userId, predicted, "home_page");
    }
  }

  // --------------------------------------------------
  // Show AI Suggestion Popup
  // --------------------------------------------------
  static void _showSuggestion(
    String userId,
    String predictedScreen,
    String basedOn,
  ) {
    // 🧠 Show popup ONLY for search-based help (avoid showing on other pages)
    // ❗ Prevent suggesting the screen the user is already on
    final currentScreen = _navigationHistory[userId]?.isNotEmpty == true
        ? _navigationHistory[userId]!.last
        : null;

    if (currentScreen == predictedScreen) {
      return; // Don't show useless prediction
    }

    // ⏱️ Prevent spammy suggestions
    final now = DateTime.now();

    // ❌ Don't repeat same suggestion again immediately
    if (_lastSuggestedPage[userId] == predictedScreen) {
      return;
    }

    // ⏱️ Cooldown check
    final lastTime = _lastSuggestionTime[userId];
    if (lastTime != null && now.difference(lastTime) < _cooldown) {
      return;
    }

    _lastSuggestionTime[userId] = now;
    _lastSuggestedPage[userId] = predictedScreen;

    if (appContext != null) {
      AIHelpPopup.show(
        appContext!,
        "💡 You often visit $predictedScreen. Want to go there?",
      );
    }

    _savePredictionBackend(userId, predictedScreen, basedOn);
  }

  // --------------------------------------------------
  // Save prediction to backend (ai_predictions table)
  // --------------------------------------------------
  static Future<void> _savePredictionBackend(
    String userId,
    String predicted,
    String basedOn,
  ) async {
    try {
      await http.post(
        Uri.parse("${ApiConfig.baseUrl}/ai/predict"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "user_id": userId,
          "predicted_screen": predicted,
          "based_on_screen": basedOn,
        }),
      );
    } catch (e) {
      print("Prediction save failed: $e");
    }
  }
  // --------------------------------------------------
  // Public getter for UI
  // --------------------------------------------------
  static String? getPrediction(String userId) {
    return _lastPrediction[userId];
  }
}