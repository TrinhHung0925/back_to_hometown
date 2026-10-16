import 'dart:async';

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';

import '../resource/app_resource.dart';
import 'ambient_audio.dart';
import 'local_service.dart';

/// Âm thanh toàn app: nhạc nền, tiếng máy lặp (cao độ theo tốc độ), còi hú
/// công an, tiếng hiệu ứng ngắn. Tắt âm thanh thì mọi lệnh phát bị bỏ qua.
class AudioService {
  static final AudioService shared = AudioService._internal();

  factory AudioService() => shared;

  AudioService._internal();

  bool _ready = false;
  String? _music;

  AudioPlayer? _engine;
  double _engineRate = 1;
  AudioPlayer? _siren;
  AudioPlayer? _rain;
  double _rainVolume = 0;
  AudioPool? _lixiPool;

  /// Tiếng nền hai bên đường (chim, dế, sóng, phố…), trộn dần khi đổi cảnh.
  final AmbientLayer _ambient = AmbientLayer();

  /// Nhạc radio: các bài phát lần lượt (rỗng khi đang phát một bài lặp).
  List<String> _playlist = const [];
  int _track = 0;
  StreamSubscription<void>? _trackEnd;
  double _musicVolume = 0.35;
  Timer? _duckTimer;

  bool get enabled => LocalService.shared.getSoundOn();

  Future<void> init() async {
    if (_ready) return;
    FlameAudio.bgm.initialize();
    await FlameAudio.audioCache.loadAll(AppAudio.preload);
    _lixiPool = await FlameAudio.createPool(AppAudio.sfxLixi, maxPlayers: 4);
    _ready = true;
  }

  void setEnabled(bool on) {
    LocalService.shared.saveSoundOn(on);
    if (on) {
      final music = _music;
      _music = null;
      if (_playlist.isNotEmpty) {
        _playTrack();
      } else if (music != null) {
        playMusic(music);
      }
    } else {
      final music = _music;
      stopAll();
      // Nhớ bài đang phát để bật lại đúng bài.
      _music = music;
    }
  }

  // ------------------------------------------------------- Tiếng ngắn
  void play(String file, {double volume = 1}) {
    if (!enabled || !_ready) return;
    FlameAudio.play(file, volume: volume);
  }

  void click() => play(AppAudio.sfxClick, volume: 0.6);

  void lixi() {
    if (!enabled || !_ready) return;
    _lixiPool?.start(volume: 0.7);
  }

  // ---------------------------------------------------------- Nhạc
  Future<void> playMusic(String file, {double volume = 0.35}) async {
    _playlist = const [];
    _musicVolume = volume;
    if (!enabled) {
      _music = file;
      return;
    }
    if (_music == file && FlameAudio.bgm.isPlaying) return;
    _music = file;
    await FlameAudio.bgm.play(file, volume: volume);
  }

  /// Nhạc radio: phát lần lượt các bài [tracks] (hết bài này sang bài kia,
  /// bắt đầu từ bài thứ [start]); đang phát đúng danh sách này thì để yên.
  Future<void> playPlaylist(List<String> tracks, {double volume = 0.3, int start = 0}) async {
    if (tracks.isEmpty) return;
    if (listEquals(tracks, _playlist) && (!enabled || FlameAudio.bgm.isPlaying)) return;
    _playlist = List.unmodifiable(tracks);
    _track = start % tracks.length;
    _musicVolume = volume;
    await _playTrack();
  }

  Future<void> _playTrack() async {
    final file = _playlist[_track % _playlist.length];
    _music = file;
    if (!enabled) return;
    await FlameAudio.bgm.play(file, volume: _musicVolume);
    // Hết bài thì dừng (không lặp) để chuyển sang bài kế.
    await FlameAudio.bgm.audioPlayer.setReleaseMode(ReleaseMode.stop);
    _trackEnd ??= FlameAudio.bgm.audioPlayer.onPlayerComplete.listen((_) {
      if (_playlist.isEmpty || !enabled) return;
      _track++;
      _playTrack();
    });
  }

  /// Hạ nhỏ nhạc một lúc (đài đọc bản tin) rồi trả lại như cũ.
  void duckMusic(Duration hold, {double factor = 0.4}) {
    if (!enabled || !_ready || _music == null || !FlameAudio.bgm.isPlaying) return;
    FlameAudio.bgm.audioPlayer.setVolume(_musicVolume * factor);
    _duckTimer?.cancel();
    _duckTimer = Timer(hold, () {
      if (FlameAudio.bgm.isPlaying) FlameAudio.bgm.audioPlayer.setVolume(_musicVolume);
    });
  }

  void stopMusic() {
    _music = null;
    _playlist = const [];
    _duckTimer?.cancel();
    // Chưa nạp xong âm thanh (hay đang chạy thử không có plugin) thì chưa có
    // nhạc nào để dừng.
    if (_ready) FlameAudio.bgm.stop();
  }

  // ------------------------------------------------------- Tiếng nền
  /// Tiếng nền theo cảnh đường [file] ở độ to [volume]; đổi cảnh thì trộn dần.
  void setAmbient(String file, double volume) {
    if (!enabled || !_ready) return;
    _ambient.play(file, volume);
  }

  /// Nhỏ dần rồi tắt tiếng nền ([fade] = false thì tắt ngay).
  void stopAmbient({bool fade = true}) => fade ? _ambient.fadeOut() : _ambient.stop();

  // ------------------------------------------------------- Tiếng máy
  Future<void> startEngine(String file) async {
    await stopEngine();
    if (!enabled || !_ready) return;
    _engineRate = 1;
    _engine = await FlameAudio.loop(file, volume: 0.35);
  }

  /// [fraction] 0..1 theo tốc độ: máy gầm cao và to hơn khi chạy nhanh.
  void setEngineLevel(double fraction) {
    final engine = _engine;
    if (engine == null) return;
    final rate = 0.75 + 0.75 * fraction.clamp(0.0, 1.0);
    // Đổi tốc độ phát liên tục khá tốn; chỉ đổi khi lệch đủ nghe thấy.
    if ((rate - _engineRate).abs() < 0.04) return;
    _engineRate = rate;
    engine.setPlaybackRate(rate);
    engine.setVolume(0.25 + 0.2 * fraction.clamp(0.0, 1.0));
  }

  Future<void> stopEngine() async {
    final engine = _engine;
    _engine = null;
    await engine?.stop();
    await engine?.dispose();
  }

  // --------------------------------------------------------- Còi hú
  Future<void> startSiren() async {
    if (_siren != null || !enabled || !_ready) return;
    _siren = await FlameAudio.loop(AppAudio.sfxSiren, volume: 0.22);
  }

  Future<void> stopSiren() async {
    final siren = _siren;
    _siren = null;
    await siren?.stop();
    await siren?.dispose();
  }

  // ----------------------------------------------------------- Mưa
  /// Tiếng mưa rơi lặp, to nhỏ theo độ nặng hạt [level] (0 = tắt).
  Future<void> setRain(double level) async {
    final volume = (level * 0.5).clamp(0.0, 0.5);
    if (volume <= 0.01) {
      final rain = _rain;
      _rain = null;
      _rainVolume = 0;
      await rain?.stop();
      await rain?.dispose();
      return;
    }
    if (!enabled || !_ready) return;
    if (_rain == null) {
      _rainVolume = volume;
      _rain = await FlameAudio.loop(AppAudio.sfxRain, volume: volume);
      return;
    }
    if ((volume - _rainVolume).abs() < 0.04) return;
    _rainVolume = volume;
    await _rain?.setVolume(volume);
  }

  // ------------------------------------------------- Tạm dừng / tắt
  void pauseLoops() {
    _engine?.pause();
    _siren?.pause();
    _rain?.pause();
    _ambient.pause();
    if (_ready) FlameAudio.bgm.pause();
  }

  void resumeLoops() {
    if (!enabled) return;
    _engine?.resume();
    _siren?.resume();
    _rain?.resume();
    _ambient.resume();
    if (_music != null && _ready) FlameAudio.bgm.resume();
  }

  void stopAll() {
    stopEngine();
    stopSiren();
    setRain(0);
    _ambient.stop();
    final playlist = _playlist;
    stopMusic();
    // Nhớ danh sách nhạc radio để bật lại âm thanh thì phát tiếp.
    _playlist = playlist;
  }
}
