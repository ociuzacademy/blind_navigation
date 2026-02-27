import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/tts_service.dart';
import 'services/vision_service.dart';
import 'services/emergency_service.dart';
import 'services/ocr_service.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    cameras = await availableCameras();
  } catch (e) {
    print('Error getting cameras: $e');
  }
  
  runApp(const BlindNavApp());
}

class BlindNavApp extends StatelessWidget {
  const BlindNavApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Guide Vision',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const BlindSafeHomeScreen(),
    );
  }
}

class BlindSafeHomeScreen extends StatefulWidget {
  const BlindSafeHomeScreen({super.key});

  @override
  State<BlindSafeHomeScreen> createState() => _BlindSafeHomeScreenState();
}

class _BlindSafeHomeScreenState extends State<BlindSafeHomeScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  final TtsService _ttsService = TtsService();
  late final VisionService _visionService; // Initialized in initState
  late final EmergencyService _emergencyService; 
  late final OcrService _ocrService;
  
  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _autoMode = false;
  Timer? _autoTimer;
  String _lastAnnouncement = "";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Initialize services
    _visionService = VisionService();
    _emergencyService = EmergencyService(_ttsService);
    _ocrService = OcrService(_ttsService);
    
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    // 1. Camera Permissions
    final cameraStatus = await Permission.camera.request();
    if (!cameraStatus.isGranted) {
      _ttsService.speak("Camera permission denied. The app cannot see.");
      return;
    }

    // 2. Initialize TTS
    await _ttsService.initialize();
    _ttsService.speak("ready", isKey: true);

    // 3. Initialize Vision
    await _visionService.loadModel();
    if (!_visionService.isModelLoaded) {
      _ttsService.speak("model_fail", isKey: true);
    }
    
    // 4. Initialize Emergency Service
    await _emergencyService.initialize();
    _emergencyService.onSmsSent = () {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("🆘 EMERGENCY ALERT SENT SUCCESSFULLY"),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 4),
          ),
        );
      }
    };
    
    // Set up fall detection callback
    // Set up fall detection callback
    _emergencyService.setCountdownUpdateCallback(_handleEmergencyUpdate);

    if (_emergencyService.isConfigured && _emergencyService.isMonitoring == false) {
      _emergencyService.startMonitoring();
    }

    // 5. Setup Camera
    if (cameras.isNotEmpty) {
      await _initializeCamera(cameras.first);
    }
  }

  Future<void> _initializeCamera(CameraDescription camera) async {
    _cameraController = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await _cameraController!.initialize();
      if (mounted) setState(() => _isInitialized = true);
    } catch (e) {
      _ttsService.speak("cam_error", isKey: true);
    }
  }

  /// ----------------------------------------------------------
  /// CORE LOGIC: IMAGE PROCESSING
  /// ----------------------------------------------------------

  Future<void> _performDetection() async {
    if (_isProcessing || _cameraController == null || !_cameraController!.value.isInitialized) return;
    
    // Don't perform detection if fall alert is active
    if (_emergencyService.isAlertActive) return;
    
    _isProcessing = true;
    HapticFeedback.lightImpact(); // Tactile feedback that scan started

    try {
      await _cameraController!.setFlashMode(FlashMode.off);
      final XFile photo = await _cameraController!.takePicture();
      
      final detections = await _visionService.processImageFile(photo.path);
      
      // Cleanup image logic - removing explicit delete here, handled at end
      // try { await File(photo.path).delete(); } catch (_) {}

      // Analyze results
      String announcement = "";
      bool shouldReadText = false;
      
      if (detections.isEmpty) {
        announcement = _ttsService.translate("clear");
      } else {
        // Prioritize stairs
        final staircase = detections.firstWhere(
          (d) => d.isStaircase, 
          orElse: () => DetectedObject(label: "", confidence: 0, left:0, top:0, width:0, height:0, distanceMeters: 0)
        );
        
        final door = detections.firstWhere(
          (d) => d.isDoor, 
          orElse: () => DetectedObject(label: "", confidence: 0, left:0, top:0, width:0, height:0, distanceMeters: 0)
        );
        
        final sign = detections.firstWhere(
            (d) => d.label.toLowerCase().contains('sign') || d.label.toLowerCase().contains('text'),
            orElse: () => DetectedObject(label: "", confidence: 0, left:0, top:0, width:0, height:0, distanceMeters: 0)
        );

        if (staircase.label.isNotEmpty) {
           HapticFeedback.heavyImpact();
           final distance = staircase.distanceMeters.toStringAsFixed(1);
           final lang = _ttsService.currentLanguage;
           if (lang == 'ml-IN') {
             String stepInfo = staircase.stepCount > 0 ? " ${_ttsService.translate('with')} ${staircase.stepCount} ${_ttsService.translate('steps')}" : "";
             announcement = "${_ttsService.translate('caution_stairs')} ${_ttsService.translate(staircase.locationLabel)} $distance ${_ttsService.translate('meters')} $stepInfo.";
           } else {
             String stepInfo = staircase.stepCount > 0 ? " with approximately ${staircase.stepCount} steps" : "";
             announcement = "Caution! Staircase detected ${_ttsService.translate(staircase.locationLabel)} at $distance meters$stepInfo.";
           }
        } else if (door.label.isNotEmpty) {
           String doorStatus = door.isDoorOpen ? _ttsService.translate("open") : _ttsService.translate("closed");
           final distance = door.distanceMeters.toStringAsFixed(1);
           final lang = _ttsService.currentLanguage;
           if (lang == 'ml-IN') {
             announcement = "${_ttsService.translate(door.label)} ${_ttsService.translate(door.locationLabel)} $distance ${_ttsService.translate('meters')} ${_ttsService.translate('away')}. ${_ttsService.translate('door_status')} $doorStatus.";
           } else {
             announcement = "${door.label} detected ${_ttsService.translate(door.locationLabel)} at $distance meters. The door appears to be $doorStatus.";
           }
        } else if (sign.label.isNotEmpty) {
           announcement = _ttsService.translate("sign_detected");
           shouldReadText = true;
        } else {
            final itemsToShow = detections.take(3).toList(); // Reduced to 3 for brevity in voice
            final isMalayalam = _ttsService.currentLanguage == 'ml-IN';
            
            final details = itemsToShow.map((d) {
              String extra = "";
              if (d.isStaircase && d.stepCount > 0) {
                extra = isMalayalam ? " (${d.stepCount} പടികൾ)" : " (${d.stepCount} steps)";
              } else if (d.isDoor) {
                extra = d.isDoorOpen ? " (${_ttsService.translate('open')})" : " (${_ttsService.translate('closed')})";
              }
              
              final translatedLabel = _ttsService.translate(d.label);
              final translatedLocation = _ttsService.translate(d.locationLabel);
              
              if (isMalayalam) {
                return "$translatedLabel$extra $translatedLocation ${d.distanceMeters.toStringAsFixed(1)} മീറ്റർ അകലെയാണ്";
              }
              return "$translatedLabel$extra is $translatedLocation, ${d.distanceMeters.toStringAsFixed(1)} meters away";
            }).toList();
            
            final separator = isMalayalam ? ". ${_ttsService.translate('next')} " : ". Next, ";
            announcement = isMalayalam ? details.join(separator) : "There is a ${details.join(separator)}.";
        }
      }

      if (announcement.isNotEmpty) {
        if (shouldReadText) {
           await _ttsService.speak(announcement);
        } else {
           _ttsService.speak(announcement); 
           _lastAnnouncement = announcement;
        }
      }

      // Cleanup image immediately if not needed for OCR
      if (!shouldReadText) {
         try { await File(photo.path).delete(); } catch (_) {}
      } else {
         // Perform OCR
         await _ocrService.processImageForText(photo.path);
         // Then clean up
         try { await File(photo.path).delete(); } catch (_) {}
      }

    } catch (e) {
      print("Detection Error: $e");
    } finally {
      _isProcessing = false;
    }
  }

  /// ----------------------------------------------------------
  /// USER INTERACTION HANDLERS (GESTURES)
  /// ----------------------------------------------------------
  
  // Single Tap: Manual Detection
  void _onTap() {
    HapticFeedback.lightImpact(); // Haptic for tap
    if (_autoMode) {
      _ttsService.speak("pause_auto", isKey: true);
      _toggleAutoMode(); // Turn it off
    } else {
      _performDetection();
    }
  }

  // Long Press: Toggle Auto-Nav Mode
  void _onLongPress() {
    HapticFeedback.heavyImpact(); // Haptic for long press
    _toggleAutoMode();
  }

  void _toggleAutoMode() {
    setState(() => _autoMode = !_autoMode);
    
    if (_autoMode) {
      _ttsService.speak("start_auto", isKey: true);
      _autoTimer = Timer.periodic(const Duration(seconds: 4), (_) => _performDetection());
    } else {
      _ttsService.speak("stop_nav", isKey: true);
      _autoTimer?.cancel();
    }
  }

  // Double Tap: Cancel fall alert OR repeat last announcement
  void _onDoubleTap() {
    // If fall alert is active, cancel it
    if (_emergencyService.isAlertActive) {
      _emergencyService.cancelFallAlert();
      _dismissFallAlertDialog();
      return;
    }
    
    // Otherwise, repeat last announcement
    if (_lastAnnouncement.isNotEmpty) {
      _ttsService.speak(_lastAnnouncement, force: true);
    } else {
      _ttsService.speak("no_prev", isKey: true, force: true);
    }
  }
  
  // Dismiss the fall alert dialog if shown
  void _dismissFallAlertDialog() {
    if (_fallAlertDialogContext != null && Navigator.canPop(_fallAlertDialogContext!)) {
      _isDialogMounted = false;
      Navigator.of(_fallAlertDialogContext!).pop();
      _fallAlertDialogContext = null;
    }
  }
  
  // Context for fall alert dialog
  BuildContext? _fallAlertDialogContext;
  bool _isDialogMounted = false;
  
  /// Show the fall alert dialog with countdown - Minimal & Premium Design
  void _showFallAlertDialog() {
    if (!mounted || _fallAlertDialogContext != null) return;
    
    _isDialogMounted = true;
    _ttsService.speak("fall_detected", isKey: true, force: true);

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: "Fall Alert",
      barrierColor: Colors.black.withOpacity(0.5), // Semi-transparent top
      pageBuilder: (dialogContext, anim1, anim2) {
        _fallAlertDialogContext = dialogContext;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            _emergencyService.setCountdownUpdateCallback(() {
              if (mounted && _isDialogMounted) {
                setDialogState(() {});
                setState(() {});
                if (!_emergencyService.isAlertActive && _fallAlertDialogContext != null) {
                  _isDialogMounted = false;
                  Navigator.of(_fallAlertDialogContext!).pop();
                  _fallAlertDialogContext = null;
                }
              }
            });
            
            return PopScope(
              canPop: false, // Prevent back button dismiss
              child: Scaffold(
                backgroundColor: Colors.transparent, // Transparent scaffold
                body: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: () {
                    _isDialogMounted = false;
                    _emergencyService.cancelFallAlert();
                    Navigator.of(dialogContext).pop();
                    _fallAlertDialogContext = null;
                  },
                  child: Column(
                    children: [
                      const Spacer(), // Top half is empty (but tappable by GestureDetector)
                      Container(
                        height: MediaQuery.of(context).size.height * 0.55, // Bottom ~55%
                        width: double.infinity,
                        decoration: const BoxDecoration(
                          color: Color(0xFF1A0000), // Very dark red
                          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                          boxShadow: [BoxShadow(color: Colors.redAccent, blurRadius: 20, spreadRadius: 2)],
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.warning_rounded, color: Colors.redAccent, size: 60),
                            const SizedBox(height: 10),
                            Text(
                              _ttsService.translate("FALL DETECTED"),
                              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 20),
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                SizedBox(
                                  width: 120,
                                  height: 120,
                                  child: CircularProgressIndicator(
                                    value: _emergencyService.remainingSeconds / 10,
                                    strokeWidth: 8,
                                    color: Colors.redAccent,
                                    backgroundColor: Colors.white10,
                                  ),
                                ),
                                Text(
                                  "${_emergencyService.remainingSeconds}",
                                  style: const TextStyle(color: Colors.white, fontSize: 50, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const Spacer(),
                            const Text(
                              "Sending Alert In...",
                              style: TextStyle(color: Colors.white70, fontSize: 16),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _ttsService.translate("DOUBLE TAP ANYWHERE\nTO CANCEL"),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1),
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      _isDialogMounted = false;
      _fallAlertDialogContext = null;
      // RESTORE MAIN CALLBACK so next alert can trigger opening the dialog
      _emergencyService.setCountdownUpdateCallback(_handleEmergencyUpdate);
    });
  }

  void _handleEmergencyUpdate() {
    if (mounted) {
      if (_fallAlertDialogContext == null) setState(() {}); 
      
      // Show fall alert dialog if not already shown
      if (_emergencyService.isAlertActive && _fallAlertDialogContext == null) {
        _showFallAlertDialog();
      }
    }
  }

  Widget _buildAlertButton(String label, Color color, VoidCallback onTap) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  // Triple Tap: Emergency Settings (Accessibility-friendly "Hidden" menu)
  void _onTripleTap() {
    HapticFeedback.heavyImpact();
    _showEmergencyDialog();
  }

  /// ----------------------------------------------------------
  /// EMERGENCY CONFIGURATION UI
  /// ----------------------------------------------------------
  
  void _showEmergencyDialog() {
    final TextEditingController numberController = TextEditingController();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Container(
            decoration: const BoxDecoration(
              color: Color(0xFF121212),
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 30,
              top: 30,
              left: 25,
              right: 25,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _ttsService.translate("Emergency Settings"),
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54),
                      onPressed: () => Navigator.pop(context),
                    )
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _ttsService.translate("Contacts added here will receive SOS messages with your location if a fall or shake is detected."),
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 20),
                
                // Language Switcher
                const Text("APP LANGUAGE", style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.5)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildLanguageOption(
                        "English", 
                        "en-US", 
                        _ttsService.currentLanguage == "en-US",
                        () async {
                          await _ttsService.setLanguage("en-US");
                          setDialogState((){});
                          _ttsService.speak("Language set to English.");
                        }
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildLanguageOption(
                        "മലയാളം", 
                        "ml-IN", 
                        _ttsService.currentLanguage == "ml-IN",
                        () async {
                          await _ttsService.setLanguage("ml-IN");
                          setDialogState((){});
                          _ttsService.speak("ഭാഷ മലയാളമായി ക്രമീകരിച്ചു.");
                        }
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 25),
                
                // Contacts List
                if (_emergencyService.emergencyNumbers.isNotEmpty) ...[
                   const Text("SAVED CONTACTS", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.5)),
                   const SizedBox(height: 10),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 180),
                     decoration: BoxDecoration(
                       color: Colors.white.withOpacity(0.05),
                       borderRadius: BorderRadius.circular(15)
                     ),
                     child: ListView.separated(
                       shrinkWrap: true,
                       padding: EdgeInsets.zero,
                       itemCount: _emergencyService.emergencyNumbers.length,
                       separatorBuilder: (_, __) => Divider(color: Colors.white.withOpacity(0.05), height: 1),
                       itemBuilder: (c, i) {
                         final num = _emergencyService.emergencyNumbers[i];
                         return ListTile(
                           title: Text(num, style: const TextStyle(color: Colors.white, fontSize: 18)),
                           trailing: IconButton(
                             icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                             onPressed: () async {
                               await _emergencyService.removeEmergencyNumber(num);
                               setDialogState((){});
                               setState((){});
                               _ttsService.speak("Contact removed.");
                             }
                           ),
                         );
                       }
                     ),
                   ),
                   const SizedBox(height: 25),
                ],

                // Add new number UI
                const Text("ADD NEW CONTACT", style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.5)),
                const SizedBox(height: 10),
                TextField(
                  controller: numberController,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                  decoration: InputDecoration(
                    hintText: "+91 00000 00000",
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                    prefixIcon: const Icon(Icons.phone, color: Colors.white54),
                  ),
                ),
                const SizedBox(height: 15),
                ElevatedButton(
                  onPressed: () async {
                    final newNum = numberController.text.trim();
                    if (newNum.isNotEmpty) {
                      await _emergencyService.addEmergencyNumber(newNum);
                      numberController.clear();
                      setDialogState((){});
                      setState((){});
                      _ttsService.speak("Number added successfully.");
                    } else {
                      _ttsService.speak("Please enter a phone number first.");
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  child: const Text("CONFIRM & ADD NUMBER", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                
                const SizedBox(height: 30),
                
                // Monitoring Toggle
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _emergencyService.isMonitoring ? Colors.redAccent.withOpacity(0.1) : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: _emergencyService.isMonitoring ? Colors.redAccent.withOpacity(0.3) : Colors.transparent),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_ttsService.translate("System Monitoring"), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                          Text(
                            _emergencyService.isMonitoring ? _ttsService.translate("Active & Detecting") : _ttsService.translate("Currently Disabled"),
                            style: TextStyle(color: _emergencyService.isMonitoring ? Colors.redAccent : Colors.white54, fontSize: 14),
                          ),
                        ],
                      ),
                      Switch(
                        value: _emergencyService.isMonitoring, 
                        activeColor: Colors.redAccent,
                        onChanged: (val) {
                           if (val) {
                             if (_emergencyService.emergencyNumbers.isEmpty) {
                               _ttsService.speak("add_contact_first", isKey: true);
                               return;
                             }
                             _emergencyService.startMonitoring();
                           } else {
                             _emergencyService.stopMonitoring();
                           }
                           setDialogState((){});
                           setState((){});
                        }
                      )
                    ],
                  ),
                )
              ],
            ),
          );
        }
      ),
    );
  }

  Widget _buildLanguageOption(String label, String code, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blueAccent.withOpacity(0.2) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? Colors.blueAccent : Colors.white10),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white54,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }


  /// ----------------------------------------------------------
  /// APP LIFECYCLE
  /// ----------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (cameras.isNotEmpty) _initializeCamera(cameras.first);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _ttsService.dispose();
    _visionService.dispose();
    _emergencyService.stopMonitoring();
    _autoTimer?.cancel();
    super.dispose();
  }

  /// ----------------------------------------------------------
  /// MAIN UI BUILD (Full Screen Gestures)
  /// ----------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque, // Catch touches everywhere
          onTap: _onTap,
          onDoubleTap: _onDoubleTap,
          onLongPress: _onLongPress,
          onDoubleTapDown: (_) {}, // Consumes double tap logic
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Camera Preview (Dimmed for low vision / battery)
              if (_isInitialized && _cameraController != null)
                Opacity(
                  opacity: 0.6, // Dimmed
                  child: CameraPreview(_cameraController!),
                )
              else 
                const Center(child: CircularProgressIndicator()),

              // 2. High Contrast Overlay (Centered)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.touch_app, color: Colors.white, size: 80),
                    const SizedBox(height: 20),
                    Text(
                      _autoMode 
                        ? (_ttsService.currentLanguage == "ml-IN" ? "ഓട്ടോ മോഡ് സജീവം\nപരിശോധിക്കുന്നു..." : "AUTO MODE ACTIVE\nScanning...") 
                        : (_ttsService.currentLanguage == "ml-IN" ? "സ്ക്രീനിൽ അമർത്തുക\nതിരിച്ചറിയാൻ" : "TAP SCREEN\nto detect"),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 40),
                    if (_emergencyService.isMonitoring)
                      Chip(
                        label: Text(_ttsService.translate("Fall Monitor ON")),
                        backgroundColor: Colors.redAccent,
                        avatar: const Icon(Icons.shield, color: Colors.white),
                      )
                  ],
                ),
              ),

              // 3. Settings Button (Top Right)
              Positioned(
                top: 10,
                right: 10,
                child: IconButton(
                  icon: const Icon(Icons.settings, color: Colors.white, size: 30),
                  onPressed: _showEmergencyDialog,
                  tooltip: "Emergency Settings",
                ),
              ),

            ],
          ),
        ),
      ),

    );
  }
}



