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


def _noise(n, seed):
    rnd = random.Random(seed)
    return [rnd.uniform(-1, 1) for _ in range(n)]


def _lowpass(samples, k):
    """Lọc thông thấp một cực: k nhỏ thì tiếng trầm, đục."""
    out, y = [], 0.0
    for s in samples:
        y += k * (s - y)
        out.append(y)
    return out


def _normalize(samples, peak=0.85):
    m = max(abs(s) for s in samples) or 1
    return [s / m * peak for s in samples]


def synth_tire_hiss(path, seconds=1.3):
    """Lốp xì hơi: tiếng 'bụp' nhỏ rồi xì kéo dài, nhỏ dần."""
    n = int(RATE * seconds)
    noise = _noise(n, 3)
    hiss = [noise[i] - 0.85 * (noise[i - 1] if i else 0) for i in range(n)]
    out = []
    for i, s in enumerate(hiss):
        t = i / RATE
        env = min(1, t / 0.03) * (1 - t / seconds) ** 1.4
        pop = math.exp(-t * 60) * math.sin(2 * math.pi * 90 * t) * 1.6
        out.append(s * env * 0.7 + pop)
    write_wav(path, _normalize(out, 0.8))


def synth_whistle(path):
    """Còi CSGT 'toét toét': tiếng huýt cao có rung (hạt bi trong còi), một
    tiếng ngắn rồi một tiếng dài."""
    blasts = [(0.0, 0.22), (0.32, 0.62)]
    seconds = 1.0
    n = int(RATE * seconds)
    out = [0.0] * n
    phase = 0.0
    for i in range(n):
        t = i / RATE
        amp = 0.0
        for start, length in blasts:
            if start <= t < start + length:
                local = t - start
                amp = min(1, local / 0.015) * min(1, (start + length - t) / 0.04)
        if amp == 0:
            continue
        trill = math.sin(2 * math.pi * 28 * t)
        freq = 2950 + 260 * trill
        phase += 2 * math.pi * freq / RATE
        tone = math.sin(phase) + 0.18 * math.sin(2 * phase)
        out[i] = tone * amp * (0.75 + 0.25 * trill)
    write_wav(path, _normalize(out, 0.6))


def synth_sputter(path, seconds=0.9):
    """Máy khục khặc thiếu xăng: vài tiếng nổ khục trầm, ngắt quãng."""
    n = int(RATE * seconds)
    out = [0.0] * n
    rnd = random.Random(5)
    noise = _lowpass(_noise(n, 9), 0.08)
    for start in (0.0, 0.16, 0.27, 0.52, 0.7):
        f = rnd.uniform(55, 85)
        for i in range(int(start * RATE), min(n, int((start + 0.14) * RATE))):
            t = i / RATE - start
            env = math.exp(-t * 28)
            out[i] += (math.sin(2 * math.pi * f * t) * 0.8 + noise[i] * 3) * env
    write_wav(path, _normalize(out, 0.75))


def synth_fuel_pump(path, seconds=1.5):
    """Cột bơm xăng chạy: tiếng mô-tơ rì rì, kết thúc bằng tiếng 'tách' ngắt cò."""
    n = int(RATE * seconds)
    noise = _lowpass(_noise(n, 11), 0.2)
    out = []
    for i in range(n):
        t = i / RATE
        env = min(1, t / 0.08) * (1 if t < seconds - 0.25 else max(0, (seconds - t) / 0.25))
        hum = math.sin(2 * math.pi * 118 * t) + 0.5 * math.sin(2 * math.pi * 236 * t) + 0.25 * math.sin(2 * math.pi * 354 * t)
        s = (hum * 0.35 + noise[i] * 1.2) * env
        click_t = t - (seconds - 0.12)
        if 0 <= click_t < 0.05:
            s += math.exp(-click_t * 120) * math.sin(2 * math.pi * 1800 * click_t) * 1.2
        out.append(s)
    write_wav(path, _normalize(out, 0.7))


def synth_rain(path, seconds=4.0):
    """Tiếng mưa rơi lặp liền mạch: rào rào (nhiễu lọc) + lộp độp hạt to."""
    n = int(RATE * seconds)
    base = _lowpass(_noise(n, 21), 0.35)
    hiss = [a - b for a, b in zip(base, _lowpass(base, 0.05))]
    out = [h * 0.8 for h in hiss]
    rnd = random.Random(4)
    for _ in range(int(seconds * 60)):
        start = rnd.randrange(n)
        f = rnd.uniform(1800, 4200)
        amp = rnd.uniform(0.15, 0.5)
        for j in range(int(0.012 * RATE)):
            i = (start + j) % n
            t = j / RATE
            out[i] += math.sin(2 * math.pi * f * t) * math.exp(-t * 400) * amp
    # Nối đuôi vào đầu cho lặp không giật.
    fade = int(0.3 * RATE)
    for j in range(fade):
        k = j / fade
        out[j] = out[j] * k + out[n - fade + j] * (1 - k)
    write_wav(path, _normalize(out[: n - fade], 0.6))


def synth_new():
    """Các tiếng tự tổng hợp cho tình huống dọc đường (không cần nguồn ngoài)."""
    synth_tire_hiss(f'{OUT}/sfx_tire_hiss.wav')
    synth_whistle(f'{OUT}/sfx_whistle.wav')
    synth_sputter(f'{OUT}/sfx_sputter.wav')
    synth_fuel_pump(f'{OUT}/sfx_fuel_pump.wav')
    synth_rain(f'{OUT}/sfx_rain.wav')


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
    synth_new()
    # Nhạc (Spring Spring, CC0) và jingle kết thúc (MintoDog, CC0) — M4A cho nhẹ.
    to_m4a(f'{SRC}/audio_oga_chipnese/chipnese_2.ogg', 'music_main')
    to_m4a(f'{SRC}/audio_oga_chayna/CH-AY-NA_0.ogg', 'music_chase')
    to_m4a(f'{FINISH}/Race Finish Best/Race Finish Best (Jingle).ogg', 'jingle_win', loudness=-16)
    to_m4a(f'{FINISH}/Race Finish Bad/Race Finish Bad (Jingle).ogg', 'jingle_lose', loudness=-16)
    for f in sorted(os.listdir(OUT)):
        print(f'{f:28s} {os.path.getsize(os.path.join(OUT, f)) // 1024:6d} KB')


if __name__ == '__main__':
    import sys
    if '--synth-only' in sys.argv:
        os.makedirs(OUT, exist_ok=True)
        synth_new()
    else:
        main()
