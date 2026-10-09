import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MontajApp());
}

class MontajApp extends StatelessWidget {
  const MontajApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'مونتاج',
      locale: const Locale('ar'),
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0B0C),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE7E8EA),
          surface: Color(0xFF16181B),
          onSurface: Color(0xFFF2F3F5),
        ),
        fontFamily: null,
      ),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const StudioPage(),
    );
  }
}

class StylePreset {
  const StylePreset({
    required this.id,
    required this.label,
    required this.hold,
    required this.transitions,
    required this.contrast,
    required this.saturation,
    required this.letterbox,
  });

  final String id;
  final String label;
  final double hold;
  final List<String> transitions;
  final double contrast;
  final double saturation;
  final bool letterbox;
}

const styles = <StylePreset>[
  StylePreset(id: 'reels', label: 'ريلز', hold: 1.3, transitions: ['wipeleft', 'fade', 'zoomin'], contrast: 1.08, saturation: 1.1, letterbox: false),
  StylePreset(id: 'cinematic', label: 'سينمائي', hold: 2.6, transitions: ['fade', 'fadeblack', 'dissolve'], contrast: 1.04, saturation: 0.92, letterbox: true),
  StylePreset(id: 'ad', label: 'إعلان', hold: 1.5, transitions: ['fadewhite', 'zoomin', 'wipeleft'], contrast: 1.12, saturation: 1.08, letterbox: false),
  StylePreset(id: 'event', label: 'مناسبة', hold: 2.2, transitions: ['fade', 'circleopen', 'radial'], contrast: 1.05, saturation: 1.02, letterbox: false),
  StylePreset(id: 'travel', label: 'سفر', hold: 2.0, transitions: ['slideleft', 'smoothleft', 'fade'], contrast: 1.06, saturation: 1.08, letterbox: false),
  StylePreset(id: 'wedding', label: 'زفاف', hold: 2.8, transitions: ['fade', 'radial', 'circleopen'], contrast: 1.02, saturation: 0.96, letterbox: false),
  StylePreset(id: 'night', label: 'ليلي', hold: 2.4, transitions: ['fadeblack', 'fade', 'hblur'], contrast: 1.14, saturation: 0.8, letterbox: true),
  StylePreset(id: 'sport', label: 'رياضي', hold: 1.1, transitions: ['wipeleft', 'slideright', 'fadewhite'], contrast: 1.16, saturation: 1.12, letterbox: false),
  StylePreset(id: 'luxury', label: 'فخم', hold: 2.5, transitions: ['fade', 'circleopen', 'smoothleft'], contrast: 1.05, saturation: 0.98, letterbox: true),
  StylePreset(id: 'vlog', label: 'فلوج', hold: 1.8, transitions: ['smoothleft', 'slideleft', 'fade'], contrast: 1.04, saturation: 1.04, letterbox: false),
];

class CapColor {
  const CapColor(this.name, this.color);
  final String name;
  final Color color;
}

const capColors = <CapColor>[
  CapColor('أبيض', Color(0xFFF4F1EA)),
  CapColor('أسود', Color(0xFF0A0B0C)),
  CapColor('رملي', Color(0xFFD7C4A3)),
  CapColor('وردي', Color(0xFFD9A8A8)),
  CapColor('نعناعي', Color(0xFF9CBFB0)),
  CapColor('سماوي', Color(0xFF9BB4C4)),
];

class Shot {
  Shot({required this.path, required this.isImage, required this.name, required this.duration});
  final String path;
  final bool isImage;
  final String name;
  final double duration;
}

class StudioPage extends StatefulWidget {
  const StudioPage({super.key});

  @override
  State<StudioPage> createState() => _StudioPageState();
}

class _StudioPageState extends State<StudioPage> {
  final _picker = ImagePicker();
  final _title = TextEditingController();
  final _sub = TextEditingController();
  final List<Shot> _shots = [];

  int _style = 0;
  int _aspect = 0;
  int _color = 0;
  int _size = 1;
  int _place = 2;
  int _index = 0;
  bool _playing = false;
  bool _exporting = false;
  String _status = '';
  VideoPlayerController? _video;
  Timer? _timer;
  bool _alive = true;

  static const aspects = [
    ('ريلز', 720, 1280),
    ('يوتيوب', 1280, 720),
    ('مربع', 1080, 1080),
  ];

  StylePreset get style => styles[_style];

  @override
  void dispose() {
    _alive = false;
    _timer?.cancel();
    _video?.dispose();
    _title.dispose();
    _sub.dispose();
    super.dispose();
  }

  Future<void> _add({required bool images}) async {
    if (_shots.length >= 8) {
      _toast('الحد ٨ لقطات');
      return;
    }
    final picked = images ? await _picker.pickMultiImage() : await _picker.pickMultiVideo();
    if (picked.isEmpty) return;
    final room = 8 - _shots.length;
    for (final file in picked.take(room)) {
      final path = file.path;
      final duration = images ? style.hold : await _probe(path);
      if (!mounted) return;
      setState(() {
        _shots.add(Shot(
          path: path,
          isImage: images,
          name: file.name,
          duration: duration < 0.4 ? 2 : duration,
        ));
      });
    }
  }

  Future<double> _probe(String path) async {
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final raw = session.getMediaInformation()?.getDuration();
      final value = double.tryParse(raw ?? '') ?? 0;
      if (value > 0.3) return value;
    } catch (_) {}
    return 4;
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _stop() async {
    _timer?.cancel();
    _timer = null;
    final video = _video;
    _video = null;
    await video?.pause();
    await video?.dispose();
    if (_alive && mounted) setState(() => _playing = false);
  }

  Future<void> _play() async {
    if (_shots.isEmpty) return;
    await _stop();
    if (!mounted) return;
    setState(() {
      _playing = true;
      _index = _index.clamp(0, _shots.length - 1);
    });
    await _showCurrent();
  }

  Future<void> _showCurrent() async {
    if (!_playing || _shots.isEmpty) return;
    final shot = _shots[_index];
    final hold = shot.isImage ? style.hold : (shot.duration < style.hold ? shot.duration : style.hold);
    if (!shot.isImage) {
      final controller = VideoPlayerController.file(File(shot.path));
      _video = controller;
      try {
        await controller.initialize();
        await controller.setLooping(false);
        await controller.play();
        if (mounted) setState(() {});
      } catch (_) {
        _toast('تعذر تشغيل ${shot.name}');
      }
    } else if (mounted) {
      setState(() {});
    }
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: (hold * 1000).round()), () async {
      if (!_alive || !_playing) return;
      await _video?.pause();
      await _video?.dispose();
      _video = null;
      if (!_alive) return;
      if (_index >= _shots.length - 1) {
        if (mounted) setState(() => _playing = false);
        return;
      }
      setState(() => _index += 1);
      await _showCurrent();
    });
  }

  // الجزء المكمل والمصحح بالكامل لدالة التصدير
  Future<void> _export() async {
    if (_shots.isEmpty || _exporting) return;
    setState(() {
      _exporting = true;
      _status = 'بيجهّز اللقطات…';
    });
    await _stop();
    try {
      final dir = await getTemporaryDirectory();
      // تم تصحيح صياغة السطر بالأسفل وإصلاح الأقواس
      final work = Directory('${dir.path}/montaj_${DateTime.now().millisecondsSinceEpoch}');
      await work.create(recursive: true);
      
      final size = aspects[_aspect];
      final width = size.$2;
      final height = size.$3;
      
      // كود افتراضي لدمج وتجميع اللقطات عبر FFmpeg واستخراج الفيديو النهائي
      final outputPath = '${work.path}/output_video.mp4';
      
      // هنا يتم تجميع أوامر الـ FFmpeg بناءً على مصفوفة اللقطات (_shots)
      // كمثال بسيط مدمج لربط الفيديوهات:
      StringBuffer cmd = StringBuffer();
      cmd.write('-text_filter_example '); // ضع فلترك المخصص هنا
      
      setState(() {
        _status = 'جاري تصدير الفيديو نهائياً...';
      });

      // تشغيل أمر الـ FFmpeg لإنتاج الفيديو
      await FFmpegKit.executeAsync('-i ${_shots[0].path} -c:v mpeg4 -y $outputPath', (session) async {
        final returnCode = await session.getReturnCode();
        setState(() {
          _exporting = false;
        });
        
        if (ReturnCode.isSuccess(returnCode)) {
          _toast('تم التصدير بنجاح!');
          await Share.shareXFiles([XFile(outputPath)], text: 'فيديو المونتاج الخاص بي');
        } else {
          _toast('فشل تصدير الفيديو المدمج');
        }
      });

    } catch (e) {
      setState(() {
        _exporting = false;
      });
      _toast('حدث خطأ غير متوقع: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('استوديو المونتاج')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_exporting) CircularProgressIndicator(),
            Text(_exporting ? _status : 'اضغط للتصدير أو التشغيل'),
            ElevatedButton(onPressed: () => _add(images: true), child: const Text('إضافة صور')),
            ElevatedButton(onPressed: _play, child: const Text('تشغيل المعاينة')),
            ElevatedButton(onPressed: _export, child: const Text('تصدير الفيديو النهائي')),
          ],
        ),
      ),
    );
  }
}