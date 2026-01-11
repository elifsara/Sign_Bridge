import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'secrets.dart'

late final List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _cameras = await availableCameras();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF7C4DFF),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF0B0F14),
      cardColor: const Color(0xFF0F1620),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: dark,
      home: const CameraTranslatePage(),
    );
  }
}

class CameraTranslatePage extends StatefulWidget {
  const CameraTranslatePage({super.key});

  @override
  State<CameraTranslatePage> createState() => _CameraTranslatePageState();
}

class _CameraTranslatePageState extends State<CameraTranslatePage> {
  CameraController? _controller;
  Future<void>? _initFuture;

  // Otomatik mod için zamanlayıcı
  Timer? _timer;
  bool _isStreaming = false;

  int _cameraIndex = 0;
  String _resultText = "Hazır";

  // IP ADRESİNİ BURAYA YAZ
  final String _serverIp = AppConstants.serverIp; // <-- GÜNCELLE (kendi IP'nizi yazın.
  // final String _serverIp = "192.168.1.XXX";

  @override
  void initState() {
    super.initState();
    if (_cameras.isEmpty) return;
    final frontCameraIndex =
    _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
    if (frontCameraIndex != -1) {
      _cameraIndex = frontCameraIndex;
    }
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    await _controller?.dispose();
    final controller = CameraController(
      _cameras[_cameraIndex],
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    setState(() {
      _controller = controller;
      _initFuture = controller.initialize();
    });

    try {
      await _initFuture;
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _resultText = "Kamera Hatası");
    }
  }

  @override
  void dispose() {
    _timer?.cancel(); // Çıkarken zamanlayıcıyı durdur
    _controller?.dispose();
    super.dispose();
  }

  // Akışı Başlat/Durdur Butonu
  void _toggleStreaming() {
    if (_isStreaming) {
      // Durdur
      _timer?.cancel();
      setState(() {
        _isStreaming = false;
        _resultText = "Durduruldu";
      });
    } else {
      // Başlat
      setState(() {
        _isStreaming = true;
        _resultText = "Başlatılıyor...";
      });
      // Her 800 milisaniyede bir istek at (Hız ayarı burada)
      _timer = Timer.periodic(const Duration(milliseconds: 800), (timer) {
        _captureAndSend();
      });
    }
  }

  Future<void> _captureAndSend() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    // Kamera meşgulse atla
    if (controller.value.isTakingPicture) return;

    try {
      final XFile file = await controller.takePicture();
      final Uint8List bytes = await file.readAsBytes();

      // IP ADRESİNİ KONTROL ET (Mac IP'si olmalı)
      final uri = Uri.parse("http://$_serverIp:8000/predict");

      // DÜZELTME: JSON yerine Multipart (Dosya) gönderimi
      final request = http.MultipartRequest("POST", uri);

      // Dosyayı 'file' ismiyle ekle (Python bu ismi bekliyor)
      request.files.add(
        http.MultipartFile.fromBytes(
          "file",
          bytes,
          filename: "frame.jpg",
        ),
      );

      final streamedResponse = await request.send();
      final resp = await http.Response.fromStream(streamedResponse);

      if (resp.statusCode == 200) {
        // Gelen JSON cevabını oku
        final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
        String prediction = decoded["prediction"]?.toString() ?? "";

        if (mounted) {
          setState(() {
            _resultText = prediction;
          });
        }
      } else {
        print("Sunucu Hatası: ${resp.statusCode}");
      }
    } catch (e) {
      print("Bağlantı Hatası: $e");
    }
  }
  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      appBar: AppBar(title: const Text("SignBridge Live")),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  color: Colors.black,
                  child: controller == null || _initFuture == null
                      ? const Center(child: CircularProgressIndicator())
                      : FutureBuilder<void>(
                    future: _initFuture,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return CameraPreview(controller);
                    },
                  ),
                ),
              ),
            ),
          ),

          // Sonuç Alanı
          Container(
            padding: const EdgeInsets.all(20),
            child: Text(
              _resultText,
              style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: Colors.white
              ),
              textAlign: TextAlign.center,
            ),
          ),

          // Başlat/Durdur Butonu
          Padding(
            padding: const EdgeInsets.only(bottom: 30, left: 20, right: 20),
            child: SizedBox(
              width: double.infinity,
              height: 60,
              child: FilledButton.icon(
                onPressed: _toggleStreaming,
                style: FilledButton.styleFrom(
                  backgroundColor: _isStreaming ? Colors.red : const Color(0xFF7C4DFF),
                ),
                icon: Icon(_isStreaming ? Icons.stop : Icons.play_arrow),
                label: Text(
                  _isStreaming ? "DURDUR" : "OTOMATİK ÇEVİRİYİ BAŞLAT",
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}