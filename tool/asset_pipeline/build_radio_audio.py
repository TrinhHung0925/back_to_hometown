"""Tổng hợp bằng code nhạc xuân và nhạc hiệu cho "Radio Giao thông" trên xe —
giai điệu tự soạn (ngũ cung), không dựa trên bài hát có sẵn nào:

- radio_spring_1.m4a: "Xuân về trên phố" — Sol trưởng ngũ cung, 120 nhịp/phút,
  sáo trúc dẫn giai điệu, đàn tranh rải hợp âm và vuốt dây, trống nhỏ, mõ,
  lắc tay (~60 giây, lặp liền mạch).
- radio_spring_2.m4a: "Đường về quê" — Rê trưởng ngũ cung, 104 nhịp/phút,
  đàn tranh dẫn với ngón nhấn, vê; sáo trúc đối đáp; phách, trống (~60 giây).
- sfx_radio_jingle.wav: nhạc hiệu đài trước mỗi bản tin — tiếng dò sóng rồi
  đàn tranh vuốt và chuông ngân.

Nhạc dựng trên vòng thời gian khép kín (đuôi nốt và tiếng vang quấn về đầu
bài) nên phát lặp không có vết nối. Stereo 44,1 kHz, nén AAC bằng afconvert
(macOS) hoặc ffmpeg; không có thì để WAV.

Chạy từ thư mục gốc project (cần numpy, scipy):
    python tool/asset_pipeline/build_radio_audio.py
"""
import os
import shutil
import subprocess
import tempfile
import wave

import numpy as np
from scipy import signal

OUT = 'assets/audio'
SR = 44100

NOTE = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}


def midi(name):
    """'F#5' → số MIDI."""
    step = NOTE[name[0]]
    rest = name[1:]
    if rest.startswith('#'):
        step += 1
        rest = rest[1:]
    return 12 * (int(rest) + 1) + step


def hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def smooth(u):
    u = np.clip(u, 0, 1)
    return u * u * (3 - 2 * u)


def bandpass(x, lo, hi, order=2, rate=SR):
    sos = signal.butter(order, (lo / (rate / 2), min(hi, rate * 0.45) / (rate / 2)), btype='band', output='sos')
    return signal.sosfilt(sos, x)


def highpass(x, f, order=2, rate=SR):
    return signal.sosfilt(signal.butter(order, f / (rate / 2), btype='high', output='sos'), x)


def lowpass(x, f, order=2, rate=SR):
    return signal.sosfilt(signal.butter(order, min(f, rate * 0.45) / (rate / 2), btype='low', output='sos'), x)


# ================================================================ Nhạc cụ
def tranh(f0, seconds, rng, bright=1.0, bend=None, vib=0.0, decay=1.0, rate=SR):
    """Đàn tranh dây thép: gảy bằng móng gần ngựa đàn — tiếng sáng, ngân dài.

    [bend] = (bắt đầu, kết thúc, nửa cung, nhả lúc) — ngón nhấn làm nốt
    cao lên rồi nhả về; [vib] độ rung (nửa cung) cho ngón rung.
    """
    n = int(seconds * rate)
    t = np.arange(n) / rate
    cents = 15 * np.exp(-t / 0.02)  # dây thép vừa gảy hơi cao rồi về
    if bend:
        b0, b1, st, back = bend
        up = smooth((t - b0) / max(b1 - b0, 1e-3))
        if back is not None:
            up = up * (1 - smooth((t - back) / 0.12))
        cents = cents + 100 * st * up
    if vib:
        cents = cents + 100 * vib * np.sin(2 * np.pi * 5.6 * t) * smooth((t - 0.25) / 0.3)
    f = f0 * 2 ** (cents / 1200)
    phase = 2 * np.pi * np.cumsum(f) / rate
    tau1 = 2.0 * decay * (220 / f0) ** 0.3
    pos = 0.12
    out = np.zeros(n)
    for k in range(1, 26):
        fk = k * f0 * np.sqrt(1 + 0.00012 * k * k)
        if fk > rate * 0.42:
            break
        amp = abs(np.sin(np.pi * k * pos)) / k ** (1.15 - 0.35 * bright)
        tau = tau1 / (1 + 0.55 * (k - 1) ** 1.15)
        out += amp * np.exp(-t / tau) * np.sin(k * phase * np.sqrt(1 + 0.00012 * k * k) + rng.random() * 6.28)
    pick = highpass(rng.normal(size=n), 2500) * np.exp(-t / 0.0025) * 0.25 * bright
    out = (out + pick) * (1 - np.exp(-t / 0.0012))
    # Thân đàn gỗ ngô đồng: cộng hưởng ấm quanh 220 Hz và 520 Hz.
    out = out + 0.25 * bandpass(out, 180, 300, rate=rate) + 0.15 * bandpass(out, 440, 640, rate=rate)
    return out * fade_tail(n, 0.08, rate)


def fade_tail(n, seconds, rate=SR):
    e = np.ones(n)
    m = min(n, int(seconds * rate))
    e[n - m:] = np.cos(np.linspace(0, np.pi / 2, m)) ** 2
    return e


def bass(f0, seconds, rng):
    """Bè trầm gảy mềm (kiểu đàn đáy): ít bội âm, tắt nhanh vừa."""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    phase = 2 * np.pi * f0 * t
    for k in range(1, 9):
        out += np.exp(-t / (0.9 / k ** 0.8)) * np.sin(k * phase + rng.random()) / k ** 1.7
    out *= 1 - np.exp(-t / 0.004)
    return lowpass(out, 1100) * fade_tail(n, 0.06)


def flute(notes, rng, breath=1.0):
    """Sáo trúc: một câu liền hơi. [notes] = [(giây bắt đầu, độ dài, midi, láy)]
    tính từ đầu câu; láy: '' | 'grace' (vẩy nốt trên) | 'slide' (luyến từ dưới
    lên) | 'mord' (láy rền). Nốt dài tự rung hơi."""
    end = notes[-1][0] + notes[-1][1] + 0.25
    n = int(end * SR)
    t = np.arange(n) / SR
    cents = np.zeros(n)
    f_target = np.zeros(n)
    amp = np.zeros(n)
    first = notes[0][2]
    f_target[:] = first
    for i, (start, dur, m, orn) in enumerate(notes):
        a = int(start * SR)
        b = min(n, int((start + dur) * SR))
        f_target[a:] = m
        # Đường bao hơi: nốt liền hơi chỉ hơi chùng lưỡi, nốt tách thì vào hơi
        # nhẹ; nốt cuối câu (hay trước chỗ ngắt) nhả hơi.
        u = t[a:b] - start
        legato = i > 0 and abs(notes[i - 1][0] + notes[i - 1][1] - start) < 0.03
        tied = i + 1 < len(notes) and abs(start + dur - notes[i + 1][0]) < 0.03
        env = 1 - 0.22 * np.exp(-u / 0.02) if legato else smooth(u / 0.035)
        if not tied:
            env = env * (1 - smooth((u - (dur - 0.06)) / 0.06))
        env = env * (0.92 + 0.08 * smooth(u / max(dur, 0.1)))  # hơi đầy dần
        amp[a:b] = np.maximum(amp[a:b], env)
        if orn == 'grace':
            g = int(0.05 * SR)
            f_target[a:a + g] = m + 2
        elif orn == 'mord':
            g = int(0.035 * SR)
            f_target[a:a + g] = m
            f_target[a + g:a + 2 * g] = m + 2
        elif orn == 'slide':
            g = int(0.09 * SR)
            cents[a:a + g] += -200 * (1 - smooth(np.linspace(0, 1, g)))
        if dur > 0.45:
            cents[a:b] += 100 * 0.22 * np.sin(2 * np.pi * 5.3 * u) * smooth((u - 0.22) / 0.35)
    # Chuyển nốt có trượt rất nhanh (ngón tay rời lỗ bấm không tức thì).
    k = 1 - np.exp(-1 / (0.012 * SR))
    glide = signal.lfilter([k], [1, k - 1], f_target - f_target[0]) + f_target[0]
    pitch = glide + cents / 100
    f = hz(pitch)
    phase = 2 * np.pi * np.cumsum(f) / SR
    tail = int(0.08 * SR)
    amp = signal.lfilter([0.004], [1, -0.996], amp)  # mềm đường bao (~6 ms)
    amp = amp / (amp.max() + 1e-9)
    tone = np.zeros(n)
    for k, a in enumerate([1, 0.38, 0.13, 0.07, 0.035, 0.02], 1):
        tone += a * amp ** (1 + 0.35 * (k - 1)) * np.sin(k * phase)
    noise = rng.normal(size=n)
    air = bandpass(noise, 1200, 7000) * 0.05 + bandpass(noise, 300, 1500) * 0.03 * (1 + np.sin(phase))
    chiff = np.zeros(n)
    for start, dur, m, orn in notes:
        a = int(start * SR)
        m2 = min(n - a, int(0.03 * SR))
        chiff[a:a + m2] += np.exp(-np.arange(m2) / (0.008 * SR))
    out = tone + air * breath * amp + bandpass(noise, 2000, 8000) * chiff * 0.12 * breath
    out[-tail:] *= np.linspace(1, 0, tail)
    return out


def woodblock(rng, pitch=1.0):
    """Mõ: hai cộng hưởng gỗ tắt rất nhanh."""
    n = int(0.12 * SR)
    t = np.arange(n) / SR
    s = np.sin(2 * np.pi * 1020 * pitch * t) * np.exp(-t / 0.028) + 0.6 * np.sin(2 * np.pi * 1650 * pitch * t) * np.exp(-t / 0.016)
    return s + highpass(rng.normal(size=n), 3000) * np.exp(-t / 0.0015) * 0.4


def drum(rng, accent=1.0):
    """Trống nhỏ (kiểu trống cơm / trống đế): mặt da căng, cao độ rơi nhanh."""
    n = int(0.45 * SR)
    t = np.arange(n) / SR
    f = 150 + 70 * np.exp(-t / 0.025)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.16)
    skin = lowpass(rng.normal(size=n), 1800) * np.exp(-t / 0.02) * 0.45
    return (body + skin) * accent


def rim(rng):
    """Gõ tang trống / phách tre: "cắc" khô, sáng."""
    n = int(0.08 * SR)
    t = np.arange(n) / SR
    s = np.sin(2 * np.pi * 1850 * t) * np.exp(-t / 0.012) + bandpass(rng.normal(size=n), 1500, 5000) * np.exp(-t / 0.004)
    return s * 0.6


def shaker(rng, accent=1.0):
    """Lắc tay (sênh tiền / lục lạc nhỏ)."""
    n = int(0.09 * SR)
    t = np.arange(n) / SR
    s = highpass(rng.normal(size=n), 5500) * np.clip(t / 0.008, 0, 1) * np.exp(-t / 0.03)
    return s * accent


def cymbal(rng, seconds=1.2):
    """Chũm chọe nhỏ, đánh nhẹ."""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    s = np.zeros(n)
    for _ in range(36):
        f = rng.uniform(3000, 11000)
        s += np.sin(2 * np.pi * f * t + rng.random() * 6) * np.exp(-t / rng.uniform(0.25, 0.7))
    s = s / 6 + highpass(rng.normal(size=n), 6000) * np.exp(-t / 0.3) * 0.6
    return s * np.clip(t / 0.002, 0, 1)


# =========================================================== Bàn hoà âm
class Track:
    """Bài nhạc stereo trên một vòng khép kín: đặt nốt theo ô nhịp, phách."""

    def __init__(self, bpm, bars, seed):
        self.beat = 60 / bpm
        self.bars = bars
        self.n = int(round(bars * 4 * self.beat * SR))
        self.mix = np.zeros((2, self.n))
        self.send = np.zeros((2, self.n))
        self.rng = np.random.default_rng(seed)

    def at(self, bar, beat=0.0):
        """Giây của phách [beat] (0..4) trong ô nhịp [bar] (đánh số từ 1)."""
        return ((bar - 1) * 4 + beat) * self.beat

    def add(self, sig, seconds, pan=0.0, gain=1.0, send=0.2):
        i = int(round(seconds * SR)) % self.n
        left = np.cos((pan + 1) * np.pi / 4) * gain
        right = np.sin((pan + 1) * np.pi / 4) * gain
        for ch, g in ((0, left), (1, right)):
            wrap(self.mix[ch], sig * g, i)
            if send:
                wrap(self.send[ch], sig * g * send, i)

    def render(self, rt60=1.7, wet=0.5):
        out = self.mix.copy()
        for ch in range(2):
            ir = hall_ir(rt60, self.rng)
            spec = np.fft.rfft(self.send[ch]) * np.fft.rfft(ir, self.n)
            out[ch] += np.fft.irfft(spec, self.n) * wet
        return out


def wrap(buf, sig, i):
    n = len(buf)
    pos = 0
    while pos < len(sig):
        take = min(len(sig) - pos, n - i)
        buf[i:i + take] += sig[pos:pos + take]
        pos += take
        i = 0


def hall_ir(rt60, rng, seconds=2.6):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    ir = np.zeros(n)
    for lo, hi, k in [(60, 400, 1.1), (400, 2000, 1.0), (2000, 6000, 0.7), (6000, 16000, 0.4)]:
        b = bandpass(rng.normal(size=n), lo, hi)
        ir += b / (b.std() + 1e-12) * np.exp(-6.9 * t / (rt60 * k))
    ir *= np.clip((t - 0.018) / 0.04, 0, 1)
    return ir / np.sqrt(np.sum(ir ** 2))


def parse(line):
    """'D5 .5 E5 .5 G5 1 r 1' → [(midi | None, phách)]."""
    toks = line.split()
    out = []
    for name, beats in zip(toks[::2], toks[1::2]):
        out.append((None if name == 'r' else name, float(beats)))
    return out


CHORDS = {
    'G': ['G3', 'D4', 'G4', 'B4', 'D5', 'B4', 'G4', 'D4'],
    'D': ['D3', 'A3', 'D4', 'E4', 'A4', 'E4', 'D4', 'A3'],
    'Em': ['E3', 'B3', 'E4', 'G4', 'B4', 'G4', 'E4', 'B3'],
    'Am': ['A3', 'E4', 'G4', 'A4', 'E5', 'A4', 'G4', 'E4'],
    'Bm': ['B3', 'F#4', 'B4', 'D5', 'F#5', 'D5', 'B4', 'F#4'],
    'A': ['A3', 'E4', 'A4', 'B4', 'E5', 'B4', 'A4', 'E4'],
    'E': ['E3', 'B3', 'E4', 'F#4', 'B4', 'F#4', 'E4', 'B3'],
}
ROOTS = {'G': ('G2', 'D3'), 'D': ('D2', 'A2'), 'Em': ('E2', 'B2'), 'Am': ('A2', 'E3'), 'Bm': ('B2', 'F#3'), 'A': ('A2', 'E3'), 'E': ('E2', 'B2')}


def place_flute(track, bar, line, gain=1.0, pan=0.25, ornaments=None):
    """Đặt một câu sáo bắt đầu từ ô nhịp [bar]; nốt liền nhau thổi liền hơi."""
    ornaments = ornaments or {}
    phrase = []
    beat = 0.0
    idx = 0
    phrases = []
    for name, beats in parse(line):
        if name is None:
            if phrase:
                phrases.append(phrase)
                phrase = []
        else:
            phrase.append((beat, beats, midi(name), ornaments.get(idx, '')))
        beat += beats
        idx += 1
    if phrase:
        phrases.append(phrase)
    for ph in phrases:
        start = ph[0][0]
        notes = [((b - start) * track.beat, d * track.beat * 0.97, m, o) for b, d, m, o in ph]
        sig = flute(notes, track.rng)
        track.add(sig, track.at(bar, start), pan=pan, gain=0.32 * gain, send=0.32)


def place_tranh(track, bar, line, gain=1.0, pan=-0.3, bends=None, tremolo=(), vib=()):
    """Đặt giai điệu đàn tranh; [bends] {chỉ số nốt: (phách bắt đầu, phách xong,
    nửa cung, nhả ở phách)}, [tremolo] các nốt vê, [vib] các nốt rung."""
    bends = bends or {}
    beat = 0.0
    for idx, (name, beats) in enumerate(parse(line)):
        if name is not None:
            f0 = hz(midi(name))
            secs = beats * track.beat
            start = track.at(bar, beat)
            if idx in tremolo:
                k = 0
                step = track.beat / 4
                while k * step < secs - 0.05:
                    s = tranh(f0, step * 2.5, track.rng, bright=0.8, decay=0.4)
                    track.add(s, start + k * step, pan=pan, gain=0.2 * gain * (0.75 + 0.25 * (k % 2 == 0)), send=0.25)
                    k += 1
                track.add(tranh(f0, 1.4, track.rng, bright=0.8), start + k * step, pan=pan, gain=0.22 * gain, send=0.25)
            else:
                bend = None
                if idx in bends:
                    b0, b1, st, back = bends[idx]
                    bend = (b0 * track.beat, b1 * track.beat, st, None if back is None else back * track.beat)
                ring = min(secs + 1.3, 3.2)
                s = tranh(f0, ring, track.rng, bright=1.0, bend=bend, vib=0.3 if idx in vib else 0.0)
                track.add(s, start, pan=pan, gain=0.3 * gain, send=0.25)
        beat += beats


def gliss(track, seconds, names, gain=1.0, pan=-0.3, step=0.035):
    """Vuốt dây đàn tranh: lướt nhanh qua các dây ngũ cung."""
    for i, name in enumerate(names):
        s = tranh(hz(midi(name)), 1.6, track.rng, bright=0.9, decay=0.7)
        track.add(s, seconds + i * step, pan=pan + 0.02 * i, gain=0.16 * gain * (0.7 + 0.3 * i / len(names)), send=0.35)


def comp(track, bar, chord, gain=1.0, pan=0.35, style='arp', bright=0.7):
    """Đệm: rải hợp âm móc đơn (đàn tranh thứ hai) hoặc gảy nửa phách."""
    notes = CHORDS[chord]
    for i in range(8):
        if style == 'half' and i % 2:
            continue
        s = tranh(hz(midi(notes[i])), 1.2, track.rng, bright=bright, decay=0.45)
        accent = 1.0 if i % 4 == 0 else 0.75
        track.add(s, track.at(bar, i * 0.5), pan=pan, gain=0.12 * gain * accent, send=0.2)


def bassline(track, bar, chord, gain=1.0, bounce=True):
    root, fifth = ROOTS[chord]
    r = track.rng
    track.add(bass(hz(midi(root)), track.beat * 1.6, r), track.at(bar, 0), gain=0.27 * gain, send=0.05)
    track.add(bass(hz(midi(fifth)), track.beat * 1.2, r), track.at(bar, 2), gain=0.22 * gain, send=0.05)
    if bounce:
        track.add(bass(hz(midi(root)), track.beat * 0.6, r), track.at(bar, 3.5), gain=0.17 * gain, send=0.05)


def groove(track, bar, kind, gain=1.0, fill=False):
    """Trống, mõ, lắc tay cho một ô nhịp."""
    r = track.rng
    if kind == 1:
        drums = [(0, 1.0), (1.5, 0.55), (2, 0.85), (3.5, 0.5)]
        rims = [3.0]
        blocks = [1.0, 3.0]
    else:
        drums = [(0, 1.0), (1.5, 0.6), (2.0, 0.8), (2.75, 0.45)]
        rims = [1.0, 3.0]
        blocks = [0.5, 2.5, 3.5]
    for b, a in drums:
        track.add(drum(r, a), track.at(bar, b) + r.normal() * 0.004, pan=0.0, gain=0.3 * gain, send=0.08)
    for b in rims:
        track.add(rim(r), track.at(bar, b), pan=-0.15, gain=0.16 * gain, send=0.1)
    for b in blocks:
        track.add(woodblock(r, 1.0 if b % 1 == 0 else 1.12), track.at(bar, b) + 0.004, pan=-0.45, gain=0.13 * gain, send=0.12)
    for i in range(8):
        track.add(shaker(r, 0.9 if i % 2 else 0.55), track.at(bar, i * 0.5) + r.normal() * 0.003, pan=0.5, gain=0.07 * gain, send=0.05)
    if fill:
        for i in range(8):
            track.add(drum(r, 0.45 + 0.07 * i), track.at(bar, 2 + i * 0.25), gain=0.26 * gain, send=0.08)


def master(stereo, rms_db=-18.0):
    """Lọc trầm sâu, chuẩn hoá độ to, nén mềm đỉnh."""
    x = stereo.copy()
    f = np.fft.rfftfreq(x.shape[1], 1 / SR)
    hp = 1 / np.sqrt(1 + (40 / np.maximum(f, 1e-3)) ** 4)
    for ch in range(2):
        x[ch] = np.fft.irfft(np.fft.rfft(x[ch]) * hp, x.shape[1])
    x *= 10 ** (rms_db / 20) / (np.sqrt(np.mean(x ** 2)) + 1e-12)
    th = 0.7
    over = np.abs(x) > th
    x[over] = np.sign(x[over]) * (th + (0.94 - th) * np.tanh((np.abs(x[over]) - th) / (0.94 - th)))
    return x, np.mean(over)


def export(name, stereo, rms_db=-19.0):
    x, clipped = master(stereo, rms_db)
    tmp = tempfile.mkdtemp()
    wav = os.path.join(tmp, f'{name}.wav')
    data = (np.clip(x.T, -1, 1) * 32767).astype('<i2').tobytes()
    with wave.open(wav, 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)
    target = f'{OUT}/{name}.m4a'
    if shutil.which('afconvert'):
        subprocess.run(['afconvert', '-f', 'm4af', '-d', 'aac', '-b', '128000', '-q', '127', wav, target], check=True)
    elif shutil.which('ffmpeg'):
        subprocess.run(['ffmpeg', '-y', '-v', 'quiet', '-i', wav, '-c:a', 'aac', '-b:a', '128k', target], check=True)
    else:
        target = f'{OUT}/{name}.wav'
        shutil.copy(wav, target)
    peak = 20 * np.log10(np.max(np.abs(x)) + 1e-9)
    print(f'{target}: {x.shape[1] / SR:.1f}s rms {rms_db:.0f} dB peak {peak:.1f} dB clipped {clipped * 100:.3f}% '
          f'size {os.path.getsize(target) // 1024} KB')


# ================================================================== Bài 1
def song_one():
    """Xuân về trên phố — Sol trưởng ngũ cung (Sol La Si Rê Mi), 120 nhịp/phút."""
    tr = Track(bpm=120, bars=30, seed=2025)
    harmony = ['G', 'G',
               'G', 'D', 'Em', 'G', 'G', 'Em', 'Am', 'D',
               'G', 'D', 'G', 'Em', 'Em', 'G', 'D', 'G',
               'G', 'D', 'Em', 'G', 'G', 'Em', 'Am', 'D',
               'Em', 'G', 'D', 'D']
    # Giai điệu sáo đoạn A (ô 3–10).
    melody_a = [
        'D5 .5 E5 .5 G5 1 A5 .5 G5 .5 E5 1',
        'D5 1 E5 .5 G5 .5 A5 2',
        'B5 .5 A5 .5 G5 .5 E5 .5 D5 1 E5 1',
        'G5 3 r 1',
        'D5 .5 E5 .5 G5 1 A5 .5 B5 .5 D6 1',
        'B5 1 A5 .5 B5 .5 G5 2',
        'E5 .5 G5 .5 A5 .5 G5 .5 E5 1 D5 1',
        'E5 .5 D5 .5 E5 1 G5 2',
    ]
    # Đàn tranh dẫn đoạn B (ô 11–18), sáo đáp lại ở chỗ nghỉ.
    melody_b = [
        'G4 1 B4 .5 A4 .5 G4 1 E4 1',
        'D4 1 E4 .5 G4 .5 A4 2',
        'B4 .5 D5 .5 B4 .5 A4 .5 G4 1 A4 1',
        'B4 3 r 1',
        'E5 1 D5 .5 B4 .5 D5 1 E5 1',
        'G5 1 E5 .5 D5 .5 B4 2',
        'A4 .5 B4 .5 D5 .5 B4 .5 A4 1 G4 .5 E4 .5',
        'G4 2 r 2',
    ]
    outro = [
        'E5 1 G5 1 A5 1 B5 1',
        'D6 2 B5 1 A5 1',
        'G5 .5 A5 .5 G5 .5 E5 .5 D5 2',
    ]
    # Mở bài: vuốt dây lên, rải hợp âm.
    gliss(tr, tr.at(1, 0), ['G3', 'A3', 'B3', 'D4', 'E4', 'G4', 'A4', 'B4', 'D5', 'E5', 'G5'], gain=1.2)
    for bar, chord in enumerate(harmony, 1):
        section_b = 11 <= bar <= 18
        comp(tr, bar, chord, gain=0.8 if section_b else 1.0, style='half' if section_b else 'arp', pan=0.35 if not section_b else 0.4)
        if bar >= 2:
            bassline(tr, bar, chord, bounce=not section_b)
        if bar >= 2:
            groove(tr, bar, 1, gain=0.75 if section_b else (0.6 if bar == 2 else 1.0), fill=bar in (10, 18, 30))
    for i, line in enumerate(melody_a):
        orn = {0: 'slide'} if i in (0, 4) else ({3: 'grace'} if i == 1 else {})
        place_flute(tr, 3 + i, line, ornaments=orn)
    for i, line in enumerate(melody_b):
        bends = {3: (0.45, 0.75, 2, 1.5)} if i == 1 else ({1: (0.2, 0.4, 2, 0.8)} if i == 5 else {})
        place_tranh(tr, 11 + i, line, gain=1.15, bends=bends, tremolo=(0,) if i == 3 else (), vib=(3,) if i == 5 else ())
    # Sáo đáp ở ô 14 và 18.
    place_flute(tr, 14, 'r 3 D6 .5 B5 .5', gain=0.8, ornaments={1: 'grace'})
    place_flute(tr, 18, 'r 2 G5 .5 A5 .5 B5 .5 D6 .5', gain=0.85)
    gliss(tr, tr.at(18, 2), ['G4', 'A4', 'B4', 'D5', 'E5', 'G5'], gain=0.8)
    # Đoạn A nhắc lại có láy, đàn tranh đánh đôi nốt dài thấp một quãng tám.
    for i, line in enumerate(melody_a):
        orn = {0: 'mord', 2: 'grace'} if i in (0, 4) else ({1: 'grace', 3: 'slide'} if i == 1 else {})
        place_flute(tr, 19 + i, line, gain=1.05, ornaments=orn)
        beat = 0.0
        for name, beats in parse(line):
            if name and beats >= 1:
                tr.add(tranh(hz(midi(name) - 12), min(beats * tr.beat + 1.0, 3.0), tr.rng, bright=0.8),
                       tr.at(19 + i, beat), pan=-0.35, gain=0.14, send=0.25)
            beat += beats
    for i, line in enumerate(outro):
        place_flute(tr, 27 + i, line, gain=1.0, ornaments={0: 'slide'} if i == 0 else {})
    # Kết: vuốt dây xuống trên hợp âm Rê, dẫn về đầu bài (Sol).
    gliss(tr, tr.at(30, 0), ['D6', 'B5', 'A5', 'G5', 'E5', 'D5', 'B4', 'A4', 'G4', 'E4', 'D4'], gain=1.0, step=0.06)
    for bar in (3, 19):
        tr.add(cymbal(tr.rng), tr.at(bar, 0), pan=0.2, gain=0.05, send=0.2)
    return tr.render(rt60=1.7, wet=0.55)


# ================================================================== Bài 2
def song_two():
    """Đường về quê — Rê trưởng ngũ cung (Rê Mi Fa# La Si), 104 nhịp/phút."""
    tr = Track(bpm=104, bars=26, seed=1990)
    harmony = ['D', 'D',
               'D', 'Bm', 'D', 'A', 'Bm', 'A', 'D', 'D',
               'D', 'A', 'Bm', 'D', 'E', 'A', 'D', 'D',
               'D', 'Bm', 'D', 'A', 'D', 'D',
               'A', 'A']
    melody_a = [
        'A4 .5 B4 .5 D5 1 E5 .5 D5 .5 B4 1',
        'A4 1 F#4 .5 A4 .5 B4 2',
        'D5 .5 E5 .5 F#5 .5 E5 .5 D5 1 B4 1',
        'A4 3 r 1',
        'B4 .5 D5 .5 E5 1 F#5 .5 A5 .5 F#5 1',
        'E5 1 D5 .5 E5 .5 F#5 2',
        'A5 .5 F#5 .5 E5 .5 D5 .5 B4 1 A4 1',
        'D5 3 r 1',
    ]
    melody_b = [
        'F#5 1 A5 1 B5 1.5 A5 .5',
        'F#5 1 E5 .5 D5 .5 E5 2',
        'F#5 .5 A5 .5 B5 .5 D6 .5 B5 1 A5 1',
        'F#5 3 r 1',
        'E5 1 F#5 .5 A5 .5 B5 1 A5 1',
        'F#5 1 E5 1 D5 1 E5 1',
        'D5 .5 E5 .5 F#5 1 E5 .5 D5 .5 E5 1',
        'D5 3 r 1',
    ]
    # Mở bài: vê nốt La rồi vuốt dây.
    place_tranh(tr, 1, 'A4 2 r 2', gain=0.9, tremolo=(0,))
    gliss(tr, tr.at(1, 2.5), ['D4', 'E4', 'F#4', 'A4', 'B4', 'D5', 'E5', 'F#5', 'A5'], gain=1.1)
    for bar, chord in enumerate(harmony, 1):
        tranh_lead = 3 <= bar <= 10 or 19 <= bar <= 24
        comp(tr, bar, chord, gain=0.75 if tranh_lead else 1.0, style='half' if tranh_lead else 'arp', pan=0.4, bright=0.6)
        if bar >= 2:
            bassline(tr, bar, chord)
            groove(tr, bar, 2, gain=0.6 if bar == 2 else (0.85 if tranh_lead else 1.0), fill=bar in (10, 18, 26))
    for i, line in enumerate(melody_a):
        bends = {3: (0.5, 0.8, 2, 1.4)} if i == 1 else ({4: (0.15, 0.35, 2, 0.45)} if i == 4 else {})
        place_tranh(tr, 3 + i, line, gain=1.2, bends=bends, tremolo=(0,) if i in (3, 7) else (), vib=(5,) if i == 5 else ())
    for i, line in enumerate(melody_b):
        orn = {0: 'slide'} if i == 0 else ({2: 'grace'} if i == 2 else ({0: 'mord'} if i == 4 else {}))
        place_flute(tr, 11 + i, line, pan=0.25, ornaments=orn)
    # Đàn tranh nhắc giai điệu, sáo đi bè nốt dài.
    for i, line in enumerate(melody_a[:4]):
        place_tranh(tr, 19 + i, line, gain=1.15, bends={3: (0.5, 0.8, 2, 1.4)} if i == 1 else {}, tremolo=(0,) if i == 3 else ())
    place_flute(tr, 19, 'F#5 2 A5 2', gain=0.75)
    place_flute(tr, 20, 'B5 2 A5 2', gain=0.75)
    place_flute(tr, 21, 'F#5 2 E5 2', gain=0.75)
    place_flute(tr, 22, 'D5 3 r 1', gain=0.75)
    place_tranh(tr, 23, 'A5 .5 F#5 .5 E5 .5 D5 .5 E5 1 F#5 1', gain=1.1)
    place_flute(tr, 23, 'A5 .5 F#5 .5 E5 .5 D5 .5 E5 1 F#5 1', gain=0.9, ornaments={4: 'grace'})
    place_tranh(tr, 24, 'D5 4', gain=1.0, tremolo=(0,))
    place_flute(tr, 24, 'D5 3.5', gain=0.9)
    # Chuyển về đầu bài: sáo gọi, đàn tranh rải La.
    place_flute(tr, 25, 'A5 .5 B5 .5 A5 1 r 2', gain=0.85, ornaments={0: 'grace'})
    gliss(tr, tr.at(26, 0), ['A4', 'B4', 'D5', 'E5', 'F#5', 'A5', 'B5'], gain=0.9, step=0.05)
    for bar in (3, 11, 19):
        tr.add(cymbal(tr.rng), tr.at(bar, 0), pan=-0.2, gain=0.05, send=0.2)
    return tr.render(rt60=1.6, wet=0.5)


# ============================================================= Nhạc hiệu
def jingle():
    """Nhạc hiệu "Radio Giao thông": dò sóng rè rè, vuốt dây, ba tiếng chuông."""
    rate = 22050
    rng = np.random.default_rng(91)
    seconds = 2.6
    n = int(seconds * rate)
    t = np.arange(n) / rate
    out = np.zeros(n)
    # Dò sóng: ồn qua dải lọc trượt xuống, tiếng huýt phách trượt theo.
    tune = int(0.5 * rate)
    noise = rng.normal(size=tune)
    frames = np.array_split(np.arange(tune), 20)
    static = np.zeros(tune)
    for k, idx in enumerate(frames):
        c = 3200 * (0.25 ** (k / 20))
        static[idx] = bandpass(noise, c * 0.6, c * 1.6, rate=rate)[idx]
    u = np.arange(tune) / rate
    whistle = np.sin(2 * np.pi * np.cumsum(2600 * 0.3 ** (u / 0.5)) / rate) * 0.25
    tune_env = np.clip(u / 0.02, 0, 1) * (1 - smooth((u - 0.32) / 0.18))
    out[:tune] += (static * 0.5 + whistle) * tune_env
    # Vuốt dây ngũ cung đi lên.
    for i, name in enumerate(['G4', 'A4', 'B4', 'D5', 'E5', 'G5']):
        s = tranh(hz(midi(name)), 1.2, rng, bright=1.0, decay=0.6, rate=rate)
        a = int((0.34 + i * 0.038) * rate)
        m = min(len(s), n - a)
        out[a:a + m] += s[:m] * 0.22 * (0.7 + 0.06 * i)
    # Ba tiếng chuông: Sol – Rê – Sol cao, tiếng cuối ngân.
    for i, (name, when, ring) in enumerate([('G5', 0.66, 0.6), ('D6', 0.84, 0.6), ('G6', 1.02, 1.5)]):
        f0 = hz(midi(name))
        m = int(ring * rate)
        tb = np.arange(m) / rate
        bell = sum(np.sin(2 * np.pi * f0 * r * tb + rng.random()) * np.exp(-tb / (ring * 0.45 / r ** 0.7)) * g
                   for r, g in [(1, 1.0), (2.0, 0.45), (2.76, 0.3), (5.4, 0.12)])
        bell *= 1 - np.exp(-tb / 0.002)
        a = int(when * rate)
        out[a:a + m] += bell * 0.3 + tranh(f0, ring, rng, bright=0.9, decay=0.8, rate=rate)[:m] * 0.18
    out *= 1 - smooth((t - (seconds - 0.25)) / 0.25)
    out = out / (np.max(np.abs(out)) + 1e-9) * 0.89
    data = (out * 32767).astype('<i2').tobytes()
    with wave.open(f'{OUT}/sfx_radio_jingle.wav', 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(data)
    print(f'{OUT}/sfx_radio_jingle.wav: {seconds:.1f}s rms {20 * np.log10(np.sqrt(np.mean(out ** 2))):.1f} dB')


if __name__ == '__main__':
    import sys

    only = set(sys.argv[1:])
    if not only or 'jingle' in only:
        jingle()
    if not only or 'one' in only:
        export('radio_spring_1', song_one())
    if not only or 'two' in only:
        export('radio_spring_2', song_two())
