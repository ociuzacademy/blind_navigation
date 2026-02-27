import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for handling Text-to-Speech announcements
class TtsService {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;
  bool _isSpeaking = false;
  String _currentLanguage = 'en-US';
  
  static const String _keyLang = "app_language";

  final Map<String, Map<String, String>> _translations = {
    'en-US': {
      'ready': "Vision Nav ready. Tap screen to detect. Long press for auto mode.",
      'pause_auto': "Pausing auto mode.",
      'start_auto': "Continuous navigation started.",
      'stop_nav': "Navigation stopped.",
      'no_prev': "No previous detection.",
      'cam_denied': "Camera permission denied. The app cannot see.",
      'model_fail': "Warning. Visual model failed to load.",
      'cam_error': "Camera error.",
      'clear': "Pathway clear.",
      'reading': "Reading text...",
      'no_text': "No legible text found.",
      'ocr_error': "Could not read the text clearly.",
      'fall_detected': "Fall detected! Alert will be sent in 10 seconds. Double tap anywhere to cancel.",
      'sending_sos': "Sending emergency alerts now.",
      'sos_sent': "Emergency messages sent successfully.",
      'sos_fail': "Failed to send emergency messages.",
      'loc_disabled': "Location services are disabled. Please turn on your GPS.",
      'detected_text': "Detected text: ",
      'detected': " detected ",
      'caution_stairs': "Caution! Staircase detected ",
      'meters': " meters ",
      'steps': " steps",
      'with': " with ",
      'door_status': "The door appears to be ",
      'open': "open",
      'closed': "closed",
      'at': " at ",
      'is': " is ",
      'away': " away",
      'sign_detected': "Sign board detected. Reading text...",
      'contact_removed': "Contact removed.",
      'number_added': "Number added successfully.",
      'enter_number': "Please enter a phone number first.",
      'add_contact_first': "Add a contact first before enabling monitoring.",
      'monitoring_active': "Emergency fall and shake detection enabled.",
      'monitoring_disabled': "Emergency detection disabled.",
      'shake_detected': "Shake detected.",
    },
    'ml-IN': {
      'ready': "വിഷൻ നാവ് തയ്യാറാണ്. തിരിച്ചറിയാൻ സ്ക്രീനിൽ അമർത്തുക. ഓട്ടോ മോഡിനായി ദീർഘനേരം അമർത്തുക.",
      'pause_auto': "ഓട്ടോ മോഡ് താൽക്കാലികമായി നിർത്തുന്നു.",
      'start_auto': "തുടർച്ചയായ നാവിഗേഷൻ ആരംഭിച്ചു.",
      'stop_nav': "നാവിഗേഷൻ നിർത്തി.",
      'no_prev': "മുൻപത്തെ വിവരങ്ങൾ ഒന്നുമില്ല.",
      'cam_denied': "ക്യാമറ അനുമതി നിഷേധിച്ചു. ആപ്പിന് കാണാൻ കഴിയില്ല.",
      'model_fail': "മുന്നറിയിപ്പ്. വിഷ്വൽ മോഡൽ ലോഡ് ചെയ്യുന്നതിൽ പരാജയപ്പെട്ടു.",
      'cam_error': "ക്യാമറ പിശക്.",
      'clear': "വഴി തടസ്സമില്ലാത്തതാണ്.",
      'reading': "അക്ഷരങ്ങൾ വായിക്കുന്നു...",
      'no_text': "വ്യക്തമായ അക്ഷരങ്ങൾ ഒന്നും കണ്ടെത്തിയില്ല.",
      'ocr_error': "അക്ഷരങ്ങൾ വ്യക്തമായി വായിക്കാൻ കഴിഞ്ഞില്ല.",
      'fall_detected': "വീഴ്ച കണ്ടെത്തി! 10 സെക്കൻഡിനുള്ളിൽ സന്ദേശം അയക്കും. റദ്ദാക്കാൻ സ്ക്രീനിൽ രണ്ടുതവണ അമർത്തുക.",
      'sending_sos': "അത്യാഹിത സന്ദേശങ്ങൾ ഇപ്പോൾ അയക്കുന്നു.",
      'sos_sent': "അത്യാഹിത സന്ദേശങ്ങൾ വിജയകരമായി അയച്ചു.",
      'sos_fail': "സന്ദേശങ്ങൾ അയക്കുന്നതിൽ പരാജയപ്പെട്ടു.",
      'loc_disabled': "ലൊക്കേഷൻ സേവനങ്ങൾ ഓഫ് ആണ്. ദയവായി ജിപിഎസ് ഓൺ ചെയ്യുക.",
      'detected_text': "കണ്ടെത്തിയ അക്ഷരങ്ങൾ: ",
      'detected': " കണ്ടെത്തി ",
      'caution_stairs': "ശ്രദ്ധിക്കുക! ഗോവണി കണ്ടെത്തി ",
      'meters': " മീറ്റർ ",
      'steps': " പടികൾ",
      'with': " ഏകദേശം ",
      'door_status': "വാതിൽ ",
      'open': "തുറന്നിരിക്കുന്നു",
      'closed': "അടഞ്ഞിരിക്കുന്നു",
      'at': " ഭാഗത്ത് ",
      'is': " ആകുന്നു ",
      'away': " അകലെ",
      'sign_detected': "സൈൻ ബോർഡ് കണ്ടെത്തി. അക്ഷരങ്ങൾ വായിക്കുന്നു...",
      'contact_removed': "കോൺടാക്റ്റ് നീക്കം ചെയ്തു.",
      'number_added': "നമ്പർ വിജയകരമായി ചേർത്തു.",
      'enter_number': "ദയവായി ഒരു ഫോൺ നമ്പർ നൽകുക.",
      'add_contact_first': "മോണിറ്ററിംഗ് ഓണാക്കുന്നതിന് മുൻപ് ഒരു കോൺടാക്റ്റ് ചേർക്കുക.",
      'monitoring_active': "വീഴ്ചയും കുലുക്കവും തിരിച്ചറിയാനുള്ള സംവിധാനം ഓൺ ചെയ്തു.",
      'monitoring_disabled': "അത്യാഹിത നിരീക്ഷണ സംവിധാനം ഓഫ് ചെയ്തു.",
      'shake_detected': "കുലുക്കം കണ്ടെത്തി.",
      'on the left': "ഇടത് വശത്ത്",
      'on the right': "വലത് വശത്ത്",
      'at center': "മധ്യഭാഗത്ത്",
      'next': "അടുത്തതായി",
      'front': "മുന്നിൽ",
      'behind': "പിന്നിൽ",
    }
  };

  final Map<String, String> _labelTranslationsMl = {
    // Objects
    'person': 'ഒരാൾ',
    'chair': 'കസേര',
    'table': 'മേശ',
    'door': 'വാതിൽ',
    'staircase': 'ഗോവണി',
    'stairs': 'പടികൾ',
    'bottle': 'കുപ്പി',
    'cup': 'കപ്പ്',
    'bowl': 'പാത്രം',
    'car': 'കാർ',
    'motorcycle': 'മോട്ടോർ സൈക്കിൾ',
    'bicycle': 'സൈക്കിൾ',
    'bus': 'ബസ്',
    'truck': 'ലോറി',
    'traffic light': 'ട്രാഫിക് സിഗ്നൽ',
    'bench': 'ബെഞ്ച്',
    'dog': 'നായ',
    'cat': 'പൂച്ച',
    'backpack': 'ബാഗ്',
    'handbag': 'ഹാൻഡ്ബാഗ്',
    'laptop': 'ലാപ്ടോപ്പ്',
    'cell phone': 'മൊബൈൽ ഫോൺ',
    'tv': 'ടിവി',
    'bed': 'കട്ടിൽ',
    'toilet': 'ടോയ്‌ലറ്റ്',
    'sink': 'സിങ്ക്',
    'refrigerator': 'ഫ്രിഡ്ജ്',
    'book': 'പുസ്തകം',
    'clock': 'ക്ലോക്ക്',
    'potted plant': 'ചെടി',
    'wall': 'ചുമര്',
    'floor': 'തറ',
    'ceiling': 'സീലിംഗ്',
    'window': 'ജനൽ',
    'glass': 'ഗ്ലാസ്',
    'remote': 'റിമോട്ട്',
    'keyboard': 'കീബോർഡ്',
    'mouse': 'മൗസ്',
    'phone': 'ഫോൺ',
    'sign': 'ബോർഡ്',
    'board': 'ബോർഡ്',
    
    // Colors (used as adjectives)
    'red': 'ചുവന്ന',
    'orange': 'ഓറഞ്ച്',
    'yellow': 'മഞ്ഞ',
    'green': 'പച്ച',
    'blue': 'നീല',
    'purple': 'വയലറ്റ്',
    'pink': 'പിങ്ക്',
    'white': 'വെള്ള',
    'gray': 'ചാരനിറത്തിലുള്ള',
    'black': 'കറുത്ത',
    'brown': 'തവിട്ടുനിറത്തിലുള്ള',
    'silver': 'വെള്ളി നിറത്തിലുള്ള',
    'gold': 'സ്വർണ്ണ നിറത്തിലുള്ള',
    'violet': 'വയലറ്റ്',
    'indigo': 'ഇൻഡിഗോ',
    'sky': 'ആകാശ',
    'light': 'ഇളം',
    'dark': 'കടും',
    'bright': 'തിളക്കമുള്ള',
    'maroon': 'കടും ചുവപ്പ്',
    'navy': 'കടും നീല',
    'teal': 'ടീൽ',
    'lime': 'ഇളം പച്ച',
    'cream': 'ക്രീം',
    'beige': 'ബീജ്',
    'cyan': 'സയൻ',
    'magenta': 'മജന്ത',
    'turquoise': 'ടർക്കോയ്‌സ്',
    'lavender': 'ലാവെൻഡർ',
    'ivory': 'ഐവറി',
    'peach': 'പീച്ച്',
    'tan': 'ടാൻ',
    'khaki': 'കാക്കി',
    
    // Noun forms for standalone detection
    'red_noun': 'ചുവപ്പ്',
    'black_noun': 'കറുപ്പ്',
    'blue_noun': 'നീല',
    'green_noun': 'പച്ച',
    'yellow_noun': 'മഞ്ഞ',
    'white_noun': 'വെള്ള',
  };

  String get currentLanguage => _currentLanguage;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    final prefs = await SharedPreferences.getInstance();
    _currentLanguage = prefs.getString(_keyLang) ?? 'en-US';
    
    await _flutterTts.setLanguage(_currentLanguage);
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

  Future<void> setLanguage(String langCode) async {
    _currentLanguage = langCode;
    await _flutterTts.setLanguage(langCode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLang, langCode);
  }

  String translate(String key) {
    if (_currentLanguage != 'ml-IN') {
      return _translations['en-US']?[key] ?? key;
    }

    // 1. Check direct translations (sentences or specific UI keys)
    String? translation = _translations['ml-IN']?[key];
    if (translation != null) return translation;

    // 2. Handle object labels (potentially with colors/status)
    String lowerKey = key.toLowerCase();
    
    // Remove extra info from ML Kit labels like "Sign board (Poster)" -> "sign board"
    if (lowerKey.contains('(')) {
      lowerKey = lowerKey.split('(')[0].trim();
    }

    // Split words to handle cases like "Red Car" or "Open Door"
    List<String> words = lowerKey.split(' ');
    List<String> translatedWords = [];
    bool foundAny = false;

    for (var word in words) {
      if (_labelTranslationsMl.containsKey(word)) {
        translatedWords.add(_labelTranslationsMl[word]!);
        foundAny = true;
      } else if (word == 'open') {
        translatedWords.add('തുറന്ന');
        foundAny = true;
      } else if (word == 'closed') {
        translatedWords.add('അടഞ്ഞ');
        foundAny = true;
      } else {
        translatedWords.add(word);
      }
    }

    if (foundAny) {
      return translatedWords.join(' ');
    }

    return key;
  }

  /// Speak a message. If already speaking, will not interrupt unless [force] is true.
  Future<void> speak(String message, {bool force = false, bool isKey = false}) async {
    if (!_isInitialized) await initialize();
    
    String textToSpeak = isKey ? translate(message) : message;
    
    if (_isSpeaking && !force) return;
    
    if (force && _isSpeaking) {
      await _flutterTts.stop();
    }
    
    await _flutterTts.speak(textToSpeak);
  }

  /// Stop current speech
  Future<void> stop() async {
    await _flutterTts.stop();
    _isSpeaking = false;
  }

  /// Announce staircase detection with distance and step count
  Future<void> announceStaircase(double distanceMeters, int stepCount, String location) async {
    final distance = distanceMeters.toStringAsFixed(1);
    String message;
    
    if (_currentLanguage == 'ml-IN') {
      String stepInfo = stepCount > 0 ? " ${translate('with')} $stepCount ${translate('steps')}" : "";
      message = "${translate('caution_stairs')} $location $distance ${translate('meters')} $stepInfo.";
    } else {
      String stepInfo = stepCount > 0 ? "${translate('with')} approximately $stepCount ${translate('steps')}" : "";
      message = "${translate('caution_stairs')} $location ${translate('at')} $distance ${translate('meters')} $stepInfo.";
    }
    
    await speak(message, force: true);
  }
  
  /// Announce door detection with open/close status
  Future<void> announceDoor(String doorLabel, double distanceMeters, bool isOpen, String location) async {
    final distance = distanceMeters.toStringAsFixed(1);
    final status = isOpen ? translate('open') : translate('closed');
    
    String message;
    if (_currentLanguage == 'ml-IN') {
      message = "$doorLabel $location $distance ${translate('meters')} ${translate('away')}. ${translate('door_status')} $status.";
    } else {
      message = "$doorLabel detected $location at $distance meters. ${translate('door_status')} $status.";
    }
    await speak(message, force: true);
  }

  void dispose() {
    _flutterTts.stop();
  }
}

