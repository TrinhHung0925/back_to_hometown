import 'dart:async';

import 'package:flame_audio/flame_audio.dart';

/// Lớp tiếng nền lặp (chim, dế, sóng, phố…): đổi cảnh thì trộn dần — bài cũ
/// nhỏ dần, bài mới to dần — không ngắt đột ngột; đổi độ to cũng trượt dần.
class AmbientLayer {
  /// Mỗi nhịp 100 ms âm lượng nhích chừng này (0 → 0,3 mất chừng 2,5 giây).
  static const double _step = 0.012;
  static const Duration _tick = Duration(milliseconds: 100);

  /// Tiếng đang phát; tiếng cuối danh sách là tiếng chính (các tiếng trước
  /// đang nhỏ dần để tắt).
  final List<_Voice> _voices = [];
  Timer? _timer;
  bool _paused = false;

  /// File đang phát chính (null khi im).
  String? get file {
    final last = _voices.isEmpty ? null : _voices.last;
    return last == null || last.target <= 0 ? null : last.file;
  }

  /// Chuyển sang tiếng nền [file] ở độ to [volume] (trộn dần nếu đổi file).
  void play(String file, double volume) {
    final current = _voices.isEmpty ? null : _voices.last;
    if (current != null && current.file == file) {
      if ((current.target - volume).abs() < 0.005) return;
      current.target = volume;
      _run();
      return;
    }
    for (final v in _voices) {
      v.target = 0;
    }
    // Vừa rời cảnh này chưa tắt hẳn thì to trở lại, khỏi nạp lại file.
    final i = _voices.indexWhere((v) => v.file == file);
    final voice = i >= 0 ? _voices.removeAt(i) : _Voice(file);
    voice.target = volume;
    _voices.add(voice);
    if (voice.player == null && !voice.loading) _load(voice);
    _run();
  }

  Future<void> _load(_Voice voice) async {
    voice.loading = true;
    try {
      final player = await FlameAudio.loop(voice.file, volume: 0);
      if (!_voices.contains(voice)) {
        await player.stop();
        await player.dispose();
        return;
      }
      voice.player = player;
      if (_paused) await player.pause();
    } catch (_) {
      _voices.remove(voice);
    } finally {
      voice.loading = false;
    }
  }

  /// Nhỏ dần rồi tắt hết (về đích, rời màn chơi).
  void fadeOut() {
    for (final v in _voices) {
      v.target = 0;
    }
    _run();
  }

  /// Tắt ngay (tắt âm thanh trong cài đặt).
  void stop() {
    _paused = false;
    _timer?.cancel();
    _timer = null;
    for (final v in _voices) {
      _release(v);
    }
    _voices.clear();
  }

  void pause() {
    _paused = true;
    _timer?.cancel();
    _timer = null;
    for (final v in _voices) {
      v.player?.pause();
    }
  }

  void resume() {
    if (!_paused) return;
    _paused = false;
    for (final v in _voices) {
      v.player?.resume();
    }
    _run();
  }

  void _run() {
    if (_paused || _timer != null || _voices.isEmpty) return;
    _timer = Timer.periodic(_tick, (_) => _advance());
  }

  void _advance() {
    var busy = false;
    for (final v in List.of(_voices)) {
      final player = v.player;
      if (player == null) {
        busy = busy || v.loading;
        continue;
      }
      if (v.volume != v.target) {
        final delta = (v.target - v.volume).clamp(-_step, _step);
        v.volume = (v.volume + delta).clamp(0.0, 1.0);
        if ((v.volume - v.target).abs() < 0.001) v.volume = v.target;
        player.setVolume(v.volume);
      }
      if (v.target <= 0 && v.volume <= 0) {
        _voices.remove(v);
        _release(v);
      } else if (v.volume != v.target) {
        busy = true;
      }
    }
    if (!busy) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _release(_Voice v) {
    final player = v.player;
    v.player = null;
    if (player == null) return;
    player.stop().then((_) => player.dispose(), onError: (_) {});
  }
}

class _Voice {
  _Voice(this.file);

  final String file;
  double target = 0;
  double volume = 0;
  AudioPlayer? player;
  bool loading = false;
}
