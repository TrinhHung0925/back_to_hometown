"""Tổng hợp bằng code các tiếng cho đêm 30 Tết và trời rét (không vướng bản
quyền):

- sfx_starter_crank.wav: đề ô tô buổi sáng rét — củ đề rè rè ba nhịp nén
  máy rồi máy nổ "bùm", gầm lên rồi về ga ralanti.
- sfx_breath_beep.wav: tiếng "bíp" ngắn của máy đo nồng độ cồn.
- sfx_breath_blow.wav: hơi thổi đều vào ống (kèm tiếng máy kêu khe khẽ),
  nửa giây — giữ nút thổi thì phát nối nhau.

Chạy từ thư mục gốc project (cần numpy):
    python tool/asset_pipeline/build_tet_night_audio.py
"""
import wave

import numpy as np

OUT = 'assets/audio'
RATE = 22050


def write(name, x, peak=0.89):
    x = np.asarray(x, dtype=np.float64)
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    data = (x * 32767).astype('<i2').tobytes()
    with wave.open(f'{OUT}/{name}.wav', 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)


def t_of(seconds):
    return np.arange(int(seconds * RATE)) / RATE


def lowpass(x, alpha):
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += alpha * (v - acc)
        y[i] = acc
    return y


def starter_crank(seed=3):
    rng = np.random.default_rng(seed)
    # Củ đề: động cơ điện rít ~150 Hz, nhịp nén máy ~9 lần/giây làm tiếng
    # rè lên xuống, máy lạnh nên quay hơi ì.
    crank = t_of(0.95)
    rate = 8.5 + 1.5 * crank / 0.95
    phase = 2 * np.pi * np.cumsum(rate) / RATE
    stroke = 0.55 + 0.45 * np.maximum(0, np.sin(phase)) ** 1.6
    motor = np.sign(np.sin(2 * np.pi * 150 * crank)) * 0.25 + np.sin(2 * np.pi * 300 * crank) * 0.2
    grind = lowpass(rng.normal(0, 1, crank.size), 0.35) * 0.6
    c = (motor + grind) * stroke * np.minimum(1, crank / 0.03)
    # Máy nổ: tiếng nổ trầm 40–55 Hz dồn dập, gầm lên rồi dịu về ralanti.
    run = t_of(1.1)
    fire = 46 + 30 * np.exp(-run * 4) * np.sin(np.pi * np.minimum(run / 0.35, 1))
    ph = 2 * np.pi * np.cumsum(fire) / RATE
    pulses = np.maximum(0, np.sin(ph)) ** 6
    body = lowpass(pulses + 0.25 * np.sin(ph * 2) + 0.15 * rng.normal(0, 1, run.size) * pulses, 0.18)
    env = np.minimum(1, run / 0.02) * (0.55 + 0.45 * np.exp(-run * 3)) * np.minimum(1, (1.1 - run) / 0.25)
    e = body * env * 1.6
    out = np.concatenate([c * 0.8, e])
    return out


def breath_beep():
    t = t_of(0.14)
    tone = np.sin(2 * np.pi * 2750 * t) + 0.2 * np.sin(2 * np.pi * 5500 * t)
    env = np.minimum(1, t / 0.004) * np.minimum(1, (0.14 - t) / 0.02)
    return tone * env


def breath_blow(seed=5):
    rng = np.random.default_rng(seed)
    t = t_of(0.55)
    hiss = rng.normal(0, 1, t.size)
    band = lowpass(hiss, 0.45) - lowpass(hiss, 0.06)
    flutter = 0.8 + 0.2 * np.sin(2 * np.pi * 7 * t)
    tone = 0.12 * np.sin(2 * np.pi * 1850 * t)
    env = np.minimum(1, t / 0.05) * np.minimum(1, (0.55 - t) / 0.05)
    return (band * flutter + tone) * env


if __name__ == '__main__':
    write('sfx_starter_crank', starter_crank())
    write('sfx_breath_beep', breath_beep(), peak=0.6)
    write('sfx_breath_blow', breath_blow(), peak=0.55)
    print('done')
