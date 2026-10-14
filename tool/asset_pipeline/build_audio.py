"""Dựng thư mục assets/audio từ các nguồn CC0 trong asset_source/.

- iOS không phát được .ogg → chuyển hết sang WAV (tiếng lặp ngắn: không có
  độ trễ mã hoá nên lặp liền mạch) hoặc M4A/AAC (nhạc dài, cho nhẹ).
- Còi hú công an và tràng pháo Tết tự tổng hợp bằng code (không vướng bản
  quyền).
- Âm lượng được chuẩn hoá về cùng mức (loudnorm) để không tiếng nào lấn át.

Cần ffmpeg. Chạy từ thư mục gốc project:
    python3 -E tool/asset_pipeline/build_audio.py
"""
import math
import os
import random
import struct
import subprocess
import tempfile
import wave

SRC = 'asset_source'
OUT = 'assets/audio'
RATE = 22050

KR = f'{SRC}/audio_kenney_starter_racing'
CAR = f'{SRC}/audio_oga_car_pack/extracted'
IFACE = f'{SRC}/audio_kenney_interface/extracted/Audio'
IMPACT = f'{SRC}/audio_kenney_impact/extracted/Audio'
FINISH = f'{SRC}/audio_oga_finish_jingle/extracted/ogg_Racing Game Finish & Jingle'
BANGS = f'{SRC}/audio_oga_bangs/extracted'


def ffmpeg(*args):
    subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', *args], check=True)


def to_wav(src, name, filters='', loudness=-16.0, mono=True):
    """Chuẩn hoá âm lượng rồi xuất WAV 16-bit."""
    chain = ','.join(f for f in [filters, f'loudnorm=I={loudness}:TP=-1.5:LRA=11'] if f)
    ffmpeg('-i', src, '-af', chain, '-ac', '1' if mono else '2', '-ar', str(RATE), '-sample_fmt', 's16',
           f'{OUT}/{name}.wav')


def mean_volume_db(src):
    """Đo âm lượng trung bình (dB) bằng volumedetect của ffmpeg."""
    r = subprocess.run(['ffmpeg', '-hide_banner', '-i', src, '-af', 'volumedetect', '-f', 'null', '-'],
                       capture_output=True, text=True, check=True)
    for line in r.stderr.splitlines():
        if 'mean_volume:' in line:
            return float(line.split('mean_volume:')[1].split('dB')[0])
    raise RuntimeError(f'không đo được âm lượng: {src}')


def to_wav_loop(src, name, target_db=-22.0):
    """Tiếng lặp (máy xe): chỉnh âm lượng CỐ ĐỊNH — loudnorm một lượt chỉnh động
    nên đầu và cuối file lệch nhau, lặp lại sẽ nghe "giật" ở chỗ nối."""
    gain = target_db - mean_volume_db(src)
    ffmpeg('-i', src, '-af', f'volume={gain:.2f}dB', '-ac', '1', '-ar', str(RATE), '-sample_fmt', 's16',
           f'{OUT}/{name}.wav')


def to_m4a(src, name, loudness=-18.0, bitrate='96k'):
    ffmpeg('-i', src, '-af', f'loudnorm=I={loudness}:TP=-1.5:LRA=11', '-ac', '2', '-ar', '44100',
           '-c:a', 'aac', '-b:a', bitrate, f'{OUT}/{name}.m4a')


def write_wav(path, samples):
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b''.join(struct.pack('<h', max(-32767, min(32767, int(s * 32767)))) for s in samples))


def synth_siren(path, seconds=2.0):
    """Còi hú kiểu 'wail': tần số lên xuống 650↔1350 Hz, đúng 2 chu kỳ để lặp
    liền mạch; thêm hoạ âm cho đỡ giống tiếng bíp điện tử."""
    n = int(RATE * seconds)
    phase = 0.0
    out = []
    for i in range(n):
        t = i / RATE
        sweep = 0.5 - 0.5 * math.cos(2 * math.pi * t / (seconds / 2))
        freq = 650 + 700 * sweep
        phase += 2 * math.pi * freq / RATE
        s = 0.6 * math.sin(phase) + 0.25 * math.sin(2 * phase) + 0.12 * math.sin(3 * phase)
        out.append(0.55 * s)
    write_wav(path, out)


def read_mono(path):
    """Giải mã một file bất kỳ ra mảng mẫu float mono ở RATE (qua ffmpeg)."""
    with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as tmp:
        tmp_path = tmp.name
    ffmpeg('-i', path, '-ac', '1', '-ar', str(RATE), '-sample_fmt', 's16', tmp_path)
    with wave.open(tmp_path, 'rb') as w:
        raw = w.readframes(w.getnframes())
    os.remove(tmp_path)
    return [v / 32768 for v in struct.unpack(f'<{len(raw) // 2}h', raw)]


def synth_firecrackers(path, seconds=2.6, seed=7):
    """Tràng pháo Tết: ghép nhiều tiếng nổ ngắn (CC0) với nhịp dồn dập ngẫu nhiên."""
    random.seed(seed)
    bangs = [read_mono(f'{BANGS}/bang_{i:02d}.ogg') for i in range(1, 11)]
    bangs = [b[: int(RATE * 0.35)] for b in bangs]
    n = int(RATE * seconds)
    mix = [0.0] * n
    t = 0.0
    while t < seconds - 0.4:
        b = random.choice(bangs)
        gain = 0.35 + random.random() * 0.45
        start = int(t * RATE)
        for j, v in enumerate(b):
            if start + j < n:
                mix[start + j] += v * gain
        t += 0.03 + random.random() * 0.09
    peak = max(abs(v) for v in mix) or 1
    write_wav(path, [v / peak * 0.9 for v in mix])


def main():
    os.makedirs(OUT, exist_ok=True)
    # Tiếng máy (Kenney Starter Kit Racing, CC0) — WAV để lặp liền mạch.
    to_wav_loop(f'{KR}/engine-motorcycle.ogg', 'sfx_engine_moto')
    to_wav_loop(f'{KR}/engine.ogg', 'sfx_engine_car')
    to_wav(f'{KR}/skid.ogg', 'sfx_skid', loudness=-18)
    # Còi (GGBotNet, CC0): ô tô giữ nguyên, xe máy nâng cao độ cho tiếng "bíp" nhỏ.
    to_wav(f'{CAR}/Car_Horn.ogg', 'sfx_horn_car', loudness=-14)
    to_wav(f'{CAR}/Car_Horn.ogg', 'sfx_horn_moto', filters=f'asetrate={RATE}*1.45,aresample={RATE}', loudness=-14)
    # Va chạm: quẹt nhẹ (qubodup, CC0); tai nạn = quẹt + tiếng kim loại nặng (Kenney, CC0).
    to_wav(f'{SRC}/audio_oga_crash/qubodup-crash.ogg', 'sfx_crash_light', loudness=-14)
    with tempfile.TemporaryDirectory() as tmp:
        ffmpeg('-i', f'{SRC}/audio_oga_crash/qubodup-crash.ogg', '-i', f'{IMPACT}/impactMetal_heavy_000.ogg',
               '-i', f'{KR}/impact.ogg', '-filter_complex', 'amix=inputs=3:duration=longest:normalize=0',
               f'{tmp}/heavy.wav')
        to_wav(f'{tmp}/heavy.wav', 'sfx_crash_heavy', loudness=-12)
    to_wav(f'{IMPACT}/impactPunch_heavy_000.ogg', 'sfx_pothole', loudness=-16)
    # Nhặt lì xì (Luke.RUSTLTD, CC0).
    to_wav(f'{SRC}/audio_oga_coins/extracted/coin1.wav', 'sfx_lixi', loudness=-17)
    # Giao diện (Kenney Interface Sounds, CC0).
    to_wav(f'{IFACE}/click_001.ogg', 'sfx_click', loudness=-18)
    to_wav(f'{IFACE}/confirmation_001.ogg', 'sfx_confirm', loudness=-18)
    # Tự tổng hợp.
    synth_siren(f'{OUT}/sfx_siren.wav')
    synth_firecrackers(f'{OUT}/sfx_firecrackers.wav')
    # Nhạc (Spring Spring, CC0) và jingle kết thúc (MintoDog, CC0) — M4A cho nhẹ.
    to_m4a(f'{SRC}/audio_oga_chipnese/chipnese_2.ogg', 'music_main')
    to_m4a(f'{SRC}/audio_oga_chayna/CH-AY-NA_0.ogg', 'music_chase')
    to_m4a(f'{FINISH}/Race Finish Best/Race Finish Best (Jingle).ogg', 'jingle_win', loudness=-16)
    to_m4a(f'{FINISH}/Race Finish Bad/Race Finish Bad (Jingle).ogg', 'jingle_lose', loudness=-16)
    for f in sorted(os.listdir(OUT)):
        print(f'{f:28s} {os.path.getsize(os.path.join(OUT, f)) // 1024:6d} KB')


if __name__ == '__main__':
    main()
