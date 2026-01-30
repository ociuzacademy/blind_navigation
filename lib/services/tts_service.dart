import 'package:flutter_tts/flutter_tts.dart';

/// Service for handling Text-to-Speech announcements
class TtsService {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;
  bool _isSpeaking = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
    
    _flutterTts.setStartHandler(() {
      _isSpeaking = true;
    });
    
    _flutterTts.setCompletionHandler(() {
      _isSpeaking = false;
    });
    
    _flutterTts.setErrorHandler((msg) {
      _isSpeaking = false;
    });
    
    _isInitialized = true;
  }

  /// Speak a message. If already speaking, will not interrupt unless [force] is true.
  Future<void> speak(String message, {bool force = false}) async {
    if (!_isInitialized) await initialize();
    
    if (_isSpeaking && !force) return;
    
    if (force && _isSpeaking) {
      await _flutterTts.stop();
    }
    
    await _flutterTts.speak(message);
  }

  /// Stop current speech
  Future<void> stop() async {
    await _flutterTts.stop();
    _isSpeaking = false;
  }

  /// Announce staircase detection with distance and step count
  Future<void> announceStaircase(double distanceMeters, int stepCount) async {
    final distance = distanceMeters.toStringAsFixed(1);
    String message;
    
    if (stepCount > 0) {
      message = "Caution! Staircase detected at $distance meters with approximately $stepCount steps. Please proceed with care.";
    } else {
      message = "Caution! Staircase detected at $distance meters. Please proceed with care.";
    }
    
    await speak(message, force: true);
  }
  
  /// Announce door detection with open/close status
  Future<void> announceDoor(String doorLabel, double distanceMeters, bool isOpen) async {
    final distance = distanceMeters.toStringAsFixed(1);
    final status = isOpen ? "open" : "closed";
    final message = "$doorLabel detected at $distance meters. The door appears to be $status.";
    await speak(message, force: true);
  }

  /// Announce general obstacle
  Future<void> announceObstacle(String objectName, double distanceMeters) async {
    final distance = distanceMeters.toStringAsFixed(1);
    await speak("$objectName detected at $distance meters", force: false);
  }

  void dispose() {
    _flutterTts.stop();
  }
}
