import 'package:flame_audio/flame_audio.dart';

import '../resource/app_resource.dart';
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
      if (music != null) playMusic(music);
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
    if (!enabled) {
      _music = file;
      return;
    }
    if (_music == file && FlameAudio.bgm.isPlaying) return;
    _music = file;
    await FlameAudio.bgm.play(file, volume: volume);
  }

  void stopMusic() {
    _music = null;
    FlameAudio.bgm.stop();
  }

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
    FlameAudio.bgm.pause();
  }

  void resumeLoops() {
    if (!enabled) return;
    _engine?.resume();
    _siren?.resume();
    _rain?.resume();
    if (_music != null) FlameAudio.bgm.resume();
  }

  void stopAll() {
    stopEngine();
    stopSiren();
    setRain(0);
    stopMusic();
  }
}
