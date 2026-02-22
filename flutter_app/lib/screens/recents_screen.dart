import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:intl/intl.dart';
import '../models/recording.dart';
import '../services/recording_service.dart';

final recordingsProvider = FutureProvider<List<Recording>>((ref) async {
  return RecordingService().getRecordings();
});

class RecentsScreen extends ConsumerStatefulWidget {
  const RecentsScreen({super.key});

  @override
  ConsumerState<RecentsScreen> createState() => _RecentsScreenState();
}

class _RecentsScreenState extends ConsumerState<RecentsScreen> {
  final AudioPlayer _player = AudioPlayer();
  String? _playingId;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.durationStream.listen((d) {
      if (mounted) setState(() => _duration = d ?? Duration.zero);
    });
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        if (mounted) setState(() => _playingId = null);
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay(Recording rec) async {
    if (_playingId == rec.id) {
      await _player.pause();
      setState(() => _playingId = null);
    } else {
      final file = File(rec.filePath);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Recording file not found')),
          );
        }
        return;
      }
      await _player.stop();
      await _player.setFilePath(rec.filePath);
      await _player.play();
      setState(() => _playingId = rec.id);
    }
  }

  void _confirmDelete(Recording rec) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Recording'),
        content: Text('Delete the recording with ${rec.number}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              if (_playingId == rec.id) {
                await _player.stop();
                setState(() => _playingId = null);
              }
              await RecordingService().deleteRecording(rec);
              ref.invalidate(recordingsProvider);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recordingsAsync = ref.watch(recordingsProvider);

    return recordingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (recordings) {
        if (recordings.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.mic_none, size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(
                  'No recordings yet',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Enable auto-record in Settings to capture calls',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade400,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: recordings.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
          itemBuilder: (context, index) {
            final rec = recordings[index];
            final isPlaying = _playingId == rec.id;

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: rec.isIncoming
                    ? Colors.green.shade100
                    : Colors.blue.shade100,
                child: Icon(
                  rec.isIncoming ? Icons.call_received : Icons.call_made,
                  color: rec.isIncoming ? Colors.green : Colors.blue,
                  size: 20,
                ),
              ),
              title: Text(
                rec.number,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('MMM d, y  h:mm a').format(rec.timestamp),
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (isPlaying) ...[
                    const SizedBox(height: 4),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                        trackHeight: 2,
                      ),
                      child: Slider(
                        value: _duration.inMilliseconds > 0
                            ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
                            : 0.0,
                        onChanged: (v) {
                          _player.seek(Duration(milliseconds: (v * _duration.inMilliseconds).round()));
                        },
                      ),
                    ),
                    Text(
                      '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                      style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary),
                    ),
                  ] else
                    Text(
                      rec.formattedDuration,
                      style: const TextStyle(fontSize: 12),
                    ),
                ],
              ),
              isThreeLine: isPlaying,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(isPlaying ? Icons.pause_circle : Icons.play_circle),
                    color: Theme.of(context).colorScheme.primary,
                    iconSize: 36,
                    onPressed: () => _togglePlay(rec),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    color: Colors.grey,
                    onPressed: () => _confirmDelete(rec),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
