import 'dart:convert';
import 'dart:io';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/recording.dart';

class RecordingService {
  static final RecordingService _instance = RecordingService._internal();
  factory RecordingService() => _instance;
  RecordingService._internal();

  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _recorderOpen = false;
  String? _currentFilePath;
  DateTime? _recordingStartTime;

  Future<bool> hasPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<bool> get isRecording async =>
      _recorderOpen && _recorder.isRecording;

  Future<void> _ensureOpen() async {
    if (!_recorderOpen) {
      await _recorder.openRecorder();
      _recorderOpen = true;
    }
  }

  Future<void> startRecording(String callId) async {
    if (!await hasPermission()) return;
    if (_recorder.isRecording) return;

    await _ensureOpen();

    final dir = await getApplicationDocumentsDirectory();
    final recordingsDir = Directory('${dir.path}/recordings');
    await recordingsDir.create(recursive: true);

    _currentFilePath = '${recordingsDir.path}/$callId.aac';
    _recordingStartTime = DateTime.now();

    await _recorder.startRecorder(
      toFile: _currentFilePath!,
      codec: Codec.aacADTS,
      bitRate: 128000,
      sampleRate: 44100,
    );
  }

  Future<Recording?> stopRecording({
    required String number,
    required bool isIncoming,
  }) async {
    if (!_recorder.isRecording) return null;

    await _recorder.stopRecorder();

    if (_currentFilePath == null || _recordingStartTime == null) return null;

    final duration = DateTime.now().difference(_recordingStartTime!).inSeconds;
    final recording = Recording(
      id: const Uuid().v4(),
      filePath: _currentFilePath!,
      number: number,
      timestamp: _recordingStartTime!,
      durationSeconds: duration,
      isIncoming: isIncoming,
    );

    await _saveRecording(recording);
    _currentFilePath = null;
    _recordingStartTime = null;

    return recording;
  }

  Future<void> _saveRecording(Recording recording) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('recordings') ?? [];
    list.insert(0, jsonEncode(recording.toJson()));
    await prefs.setStringList('recordings', list);
  }

  Future<List<Recording>> getRecordings() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('recordings') ?? [];
    return list.map((s) => Recording.fromJson(jsonDecode(s))).toList();
  }

  Future<void> deleteRecording(Recording recording) async {
    final file = File(recording.filePath);
    if (await file.exists()) await file.delete();

    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('recordings') ?? [];
    list.removeWhere((s) => jsonDecode(s)['id'] == recording.id);
    await prefs.setStringList('recordings', list);
  }

  void dispose() {
    if (_recorderOpen) {
      _recorder.closeRecorder();
      _recorderOpen = false;
    }
  }
}
