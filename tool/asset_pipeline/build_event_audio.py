"""Tổng hợp bằng code các tiếng cho chuyện dọc đường (không vướng bản quyền):

- sfx_phone_ring.wav: chuông điện thoại di động — giai điệu ngắn kiểu
  marimba, hai lượt.
- sfx_wind_gust.wav: gió biển giật — tiếng ồn lọc dải, to dần rồi nhỏ dần.
- sfx_truck_horn.wav: còi hơi xe tải — hai giọng trầm lệch nhau, rè.
- sfx_fireworks.wav: pháo hoa giao thừa — tiếng "bùm" trầm rồi lách tách.

Chạy từ thư mục gốc project (cần numpy):
    python tool/asset_pipeline/build_event_audio.py
"""
import wave

import numpy as np

OUT = 'assets/audio'
RATE = 22050


def write(name, x):
    """Chuẩn hoá đỉnh -1 dB rồi xuất WAV 16-bit mono."""
    x = np.asarray(x, dtype=np.float64)
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.89
    data = (x * 32767).astype('<i2').tobytes()
    with wave.open(f'{OUT}/{name}.wav', 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)


def t_of(seconds):
    return np.arange(int(seconds * RATE)) / RATE


def lowpass(x, alpha):
    """Lọc thông thấp một cực (alpha nhỏ = tối hơn)."""
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += alpha * (v - acc)
        y[i] = acc
    return y


def marimba(freq, seconds=0.32):
    t = t_of(seconds)
    env = np.exp(-t * 11)
    tone = np.sin(2 * np.pi * freq * t) + 0.35 * np.sin(2 * np.pi * freq * 4 * t) * np.exp(-t * 30)
    attack = np.minimum(1, t / 0.004)
    return tone * env * attack


def phone_ring():
    # Giai điệu vui tai, lặp hai lượt, nghỉ một nhịp.
    notes = [(784, 0.16), (988, 0.16), (1175, 0.16), (988, 0.16), (1319, 0.32), (1175, 0.32)]
    phrase = np.zeros(int(1.4 * RATE))
    at = 0.0
    for freq, step in notes:
        n = marimba(freq)
        i = int(at * RATE)
        end = min(len(phrase), i + len(n))
        phrase[i:end] += n[: end - i]
        at += step
    return np.concatenate([phrase, phrase * 0.92, np.zeros(int(0.15 * RATE))])


def wind_gust():
    rng = np.random.default_rng(7)
    seconds = 1.8
    t = t_of(seconds)
    noise = rng.normal(0, 1, len(t))
    # Hai dải: ù trầm và rít cao, cao độ trôi theo cơn giật.
    low = lowpass(noise, 0.02)
    high = noise - lowpass(noise, 0.25)
    high = lowpass(high, 0.35)
    env = np.sin(np.pi * np.clip(t / seconds, 0, 1)) ** 1.6
    wobble = 1 + 0.25 * np.sin(2 * np.pi * 2.3 * t)
    return (low * 3.2 + high * 0.45 * wobble) * env


def truck_horn():
    seconds = 1.0
    t = t_of(seconds)
    out = np.zeros_like(t)
    for freq in (155.0, 196.0):
        phase = 2 * np.pi * freq * t + 0.4 * np.sin(2 * np.pi * 5.5 * t)
        # Sóng răng cưa bớt gắt: còi hơi rè, đầy.
        saw = sum(np.sin(k * phase) / k for k in range(1, 14))
        out += saw
    env = np.minimum(1, t / 0.03) * np.minimum(1, (seconds - t) / 0.12)
    return lowpass(out, 0.3) * env


def fireworks():
    rng = np.random.default_rng(11)
    seconds = 2.6
    t = t_of(seconds)
    out = np.zeros_like(t)
    # Bùm: tiếng nổ trầm.
    boom = rng.normal(0, 1, len(t))
    boom = lowpass(boom, 0.03) * np.exp(-t * 7) * 9
    out += boom
    # Lách tách: hàng trăm tiếng nổ nhỏ rải sau 0,25 giây.
    for _ in range(160):
        at = 0.25 + rng.random() ** 1.6 * 2.1
        i = int(at * RATE)
        n = int(0.012 * RATE)
        if i + n >= len(out):
            continue
        crack = rng.normal(0, 1, n) * np.exp(-np.arange(n) / (0.002 * RATE))
        out[i:i + n] += crack * (0.35 + rng.random() * 0.5) * np.exp(-(at - 0.25) * 0.9)
    return out


if __name__ == '__main__':
    write('sfx_phone_ring', phone_ring())
    write('sfx_wind_gust', wind_gust())
    write('sfx_truck_horn', truck_horn())
    write('sfx_fireworks', fireworks())
    print('xong')
