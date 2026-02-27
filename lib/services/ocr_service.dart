import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'tts_service.dart';

class OcrService {
  final TtsService _ttsService;
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  OcrService(this._ttsService);

  Future<void> processImageForText(String imagePath) async {
    try {
      final InputImage inputImage = InputImage.fromFilePath(imagePath);
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

      String text = recognizedText.text;

      // Filter out garbage text/artifacts
      if (text.trim().length <= 2 && !RegExp(r'^\d+$').hasMatch(text.trim())) {
          // If very short and not a number, likely noise
          text = "";
      }

      if (text.trim().isNotEmpty) {
        String cleanText = text.replaceAll(RegExp(r'\s+'), ' ').trim();
        _ttsService.speak("${_ttsService.translate('detected_text')} $cleanText", force: true);
      } else {
        _ttsService.speak("no_text", isKey: true, force: true);
      }
    } catch (e) {
      print("OCR Error: $e");
      _ttsService.speak("ocr_error", isKey: true, force: true);
    }
  }
  
  void dispose() {
    _textRecognizer.close();
  }
}
