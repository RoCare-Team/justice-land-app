import 'dart:async';
import 'dart:io';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:path_provider/path_provider.dart';

import '../../services/consultation_service.dart';

/// Records one call on this device and uploads it for the admin to review.
///
/// flutter_webrtc's native recorder captures a single audio *channel* per file
/// and has no way to mix two, so a call is recorded as two files at once: what
/// this device's mic picked up (`-app-in`) and what it played out loud, i.e.
/// the other person (`-app-out`). Together they are the whole conversation; the
/// admin panel labels and plays each. The web client, which can mix in the
/// browser, uploads one file with both voices instead.
///
/// Best-effort throughout: recording must never affect the call, so every
/// failure — an unsupported platform, a channel that will not start, a failed
/// upload — is swallowed here.
class CallRecorder {
  CallRecorder(this._service, this._consultationId);

  final ConsultationService _service;
  final String _consultationId;

  final List<_Take> _takes = [];

  bool get isRecording => _takes.isNotEmpty;

  /// Starts both channels. Call once the peer connection is actually connected.
  Future<void> start() async {
    if (_takes.isNotEmpty) return;
    final Directory dir;
    try {
      dir = await getTemporaryDirectory();
    } catch (_) {
      return;
    }
    final stamp = DateTime.now().millisecondsSinceEpoch;
    await _begin(dir, stamp, 'in', RecorderAudioChannel.INPUT);
    await _begin(dir, stamp, 'out', RecorderAudioChannel.OUTPUT);
  }

  Future<void> _begin(
    Directory dir,
    int stamp,
    String suffix,
    RecorderAudioChannel channel,
  ) async {
    try {
      final path = '${dir.path}/call_${stamp}_$suffix.m4a';
      final recorder = MediaRecorder();
      await recorder.start(path, audioChannel: channel);
      _takes.add(_Take(recorder, path, suffix));
    } catch (_) {
      // This channel is unavailable on this device; the other may still work.
    }
  }

  /// Stops recording and uploads each file under `<callId>-app-<in|out>`, then
  /// deletes the local copies.
  Future<void> finishAndUpload(String callId) async {
    final takes = List<_Take>.of(_takes);
    _takes.clear();
    for (final take in takes) {
      try {
        await take.recorder.stop();
        final file = File(take.path);
        if (callId.isNotEmpty && await file.exists() && await file.length() > 0) {
          await _service.uploadRecording(
            _consultationId,
            callId: '$callId-app-${take.suffix}',
            filePath: take.path,
          );
        }
        if (await file.exists()) await file.delete();
      } catch (_) {
        // A lost recording must never surface as a failed call.
      }
    }
  }

  /// Stops recording without uploading — for a screen closing mid-call.
  Future<void> discard() async {
    final takes = List<_Take>.of(_takes);
    _takes.clear();
    for (final take in takes) {
      try {
        await take.recorder.stop();
        final file = File(take.path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Nothing to salvage.
      }
    }
  }
}

class _Take {
  const _Take(this.recorder, this.path, this.suffix);

  final MediaRecorder recorder;
  final String path;
  final String suffix;
}
