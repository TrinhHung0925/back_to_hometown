"""Tổng hợp bằng code tiếng nền (ambience) cho từng cảnh đường — vòng lặp
liền mạch, tự soạn hoàn toàn nên không vướng bản quyền:

- amb_delta_day.wav: đồng bằng ban ngày — chào mào, chim sẻ, chích chòe, cu
  gáy, gió lùa ruộng lúa và lũy tre (tre kẽo kẹt), gà gáy xa.
- amb_delta_night.wav: đêm đồng quê / miệt vườn — dế, ếch đồng, ễnh ương,
  chó sủa xa, gió nhẹ.
- amb_coast_day.wav: sóng vỗ bờ, hải âu, gió biển, rặng phi lao vi vu.
- amb_coast_night.wav: sóng đêm, gió, dế trong bãi cát.
- amb_mountain_day.wav: gió đèo giật, chim rừng vọng vách núi, suối xa,
  diều hâu, lục lạc ngựa thồ.
- amb_mountain_night.wav: gió rét hú, cú kêu, dế thưa, suối.
- amb_mekong_day.wav: nước vỗ mạn xuồng, ghe máy nổ xa, vịt chạy đồng, bìm
  bịp, chim.
- amb_city.wav: phố — ù ù xe cộ, xe máy chạy qua, còi xa, loa phường văng vẳng.
- amb_tet_eve.wav: đêm giao thừa — trống lân xa, người reo, pháo hoa xa.

Mọi thứ dựng trên một vòng thời gian khép kín: ồn nền lọc bằng FFT vòng,
tiếng lẻ đặt quấn quanh mép, vang dựng bằng tích chập vòng — chỗ nối vòng
lặp không có vết. Mono 22,05 kHz, 16-bit.

Chạy từ thư mục gốc project (cần numpy, scipy):
    python tool/asset_pipeline/build_ambient_audio.py
"""
import wave

import numpy as np
from scipy import signal

OUT = 'assets/audio'
RATE = 22050
NYQ = RATE / 2


# ----------------------------------------------------------------- Vòng lặp
class Loop:
    """Một vòng tiếng nền gồm nhiều lớp (gió, chim, dế…), mỗi lớp một mức to.

    Lớp nền ('bed') đo theo RMS cả vòng; lớp tiếng lẻ ('event') đo theo đoạn
    to nhất (RMS 50 ms, bách phân vị 99) — tiếng chim thưa thớt vẫn nghe rõ
    trên nền gió mà không phải đoán hệ số. Mỗi lớp có phần gửi sang vang.
    """

    def __init__(self, seconds, seed):
        self.n = int(seconds * RATE)
        self.seconds = self.n / RATE
        self.rng = np.random.default_rng(seed)
        self.layers = {}

    def layer(self, name, level, kind='event', send=0.0):
        self.layers[name] = {'level': level, 'kind': kind, 'send': send, 'dry': np.zeros(self.n), 'wet': np.zeros(self.n)}

    def put(self, name, sig, at, gain=1.0, send=None):
        """Đặt tiếng [sig] lúc [at] giây vào lớp [name]; phần tràn mép quấn về đầu vòng."""
        lay = self.layers[name]
        send = lay['send'] if send is None else send
        sig = np.asarray(sig, dtype=np.float64) * gain
        i = int(round(at * RATE)) % self.n
        wrap_add(lay['dry'], sig, i)
        if send > 0:
            wrap_add(lay['wet'], sig * send, i)

    def bed(self, name, x, gain=1.0):
        lay = self.layers[name]
        lay['dry'] += x * gain
        if lay['send'] > 0:
            lay['wet'] += x * gain * lay['send']

    def noise(self, shape):
        """Ồn tuần hoàn đúng [n] mẫu, nhuộm phổ theo shape(f) (độ lệch chuẩn 1)."""
        f = np.fft.rfftfreq(self.n, 1 / RATE)
        spec = (self.rng.normal(size=f.size) + 1j * self.rng.normal(size=f.size)) * shape(f)
        spec[0] = 0
        x = np.fft.irfft(spec, self.n)
        return x / (x.std() + 1e-12)

    def slow(self, cutoff):
        """Dao động chậm ngẫu nhiên tuần hoàn (độ lệch chuẩn 1) dưới [cutoff] Hz."""
        return self.noise(lambda f: np.exp(-(f / cutoff) ** 2))

    def times(self, rate, jitter=0.6):
        """Các mốc rải đều quanh vòng, trung bình [rate] lần mỗi giây, có xô lệch."""
        count = max(1, int(round(rate * self.seconds)))
        step = self.seconds / count
        start = self.rng.random() * step
        return [start + k * step + (self.rng.random() - 0.5) * jitter * step for k in range(count)]

    def mix(self, ir, wet_gain=1.0):
        dry = np.zeros(self.n)
        wet = np.zeros(self.n)
        for name, lay in self.layers.items():
            x = lay['dry']
            if not np.any(x):
                continue
            current = rms(x) if lay['kind'] == 'bed' else np.percentile(short_rms(x, 0.05), 99)
            k = 10 ** (lay['level'] / 20) / (current + 1e-12)
            dry += x * k
            wet += lay['wet'] * k
        out = dry
        if ir is not None and np.any(wet):
            out = dry + np.fft.irfft(np.fft.rfft(wet) * np.fft.rfft(ir, self.n), self.n) * wet_gain
        return out


def rms(x):
    return np.sqrt(np.mean(x ** 2))


def short_rms(x, seconds):
    blk = max(1, int(seconds * RATE))
    n = len(x) // blk
    return np.sqrt(np.mean(x[: n * blk].reshape(n, blk) ** 2, 1))


def k_weighted(x):
    """Lọc trọng số K (kiểu đo LUFS): bỏ siêu trầm, nhấn nhẹ dải cao — để
    so độ to nghe được giữa các cảnh."""
    f = np.fft.rfftfreq(len(x), 1 / RATE)
    hp = bp(38, None, order=2)(f)
    shelf = 10 ** (4 / 20 / (1 + (1681 / np.maximum(f, 1)) ** 2))
    return np.fft.irfft(np.fft.rfft(x) * hp * shelf, len(x))


def wrap_add(buf, sig, i):
    n = len(buf)
    pos = 0
    while pos < len(sig):
        take = min(len(sig) - pos, n - i)
        buf[i:i + take] += sig[pos:pos + take]
        pos += take
        i = 0


# ------------------------------------------------------------------ Phổ, lọc
def bp(lo=None, hi=None, order=2):
    """Đáp ứng biên độ kiểu Butterworth (dùng cho ồn lọc bằng FFT)."""

    def shape(f):
        g = np.ones_like(f)
        if lo:
            g = g / np.sqrt(1 + (lo / np.maximum(f, 1e-3)) ** (2 * order))
        if hi:
            g = g / np.sqrt(1 + (f / hi) ** (2 * order))
        return g

    return shape


def pink(shape):
    return lambda f: shape(f) / np.sqrt(np.maximum(f, 20))


def brown(shape):
    return lambda f: shape(f) / np.maximum(f, 20)


def sos_filter(x, kind, freq, order=2):
    if kind == 'band':
        lo, hi = freq
        freq = (max(lo, 10) / NYQ, min(hi, NYQ * 0.95) / NYQ)
    else:
        freq = min(freq, NYQ * 0.95) / NYQ
    sos = signal.butter(order, freq, btype=kind, output='sos')
    return signal.sosfilt(sos, x)


def lowpass(x, hz, order=2):
    return sos_filter(x, 'low', hz, order)


def highpass(x, hz, order=2):
    return sos_filter(x, 'high', hz, order)


def bandpass(x, lo, hi, order=2):
    return sos_filter(x, 'band', (lo, hi), order)


def pad(x, seconds):
    """Thêm khoảng lặng phía sau để đuôi lọc / tiếng vọng không bị cụt."""
    return np.concatenate([x, np.zeros(int(seconds * RATE))])


def far(x, distance):
    """Nghe từ xa: không khí nuốt dần tiếng cao. [distance] 0 (gần) .. 1 (rất xa)."""
    cutoff = 9000 * (1 - distance) ** 1.6 + 900
    return lowpass(pad(x, 0.05), cutoff)


# --------------------------------------------------------------- Dựng tiếng
def tt(seconds):
    return np.arange(int(seconds * RATE)) / RATE


def tone(freq, harmonics=(1.0,), phase=0.0):
    """Tổng các bội của tần số tức thời [freq] (mảng Hz); bỏ bội vượt Nyquist."""
    ph = 2 * np.pi * np.cumsum(freq) / RATE + phase
    out = np.zeros_like(ph)
    for k, a in enumerate(harmonics, 1):
        if a == 0:
            continue
        alias = np.clip((0.46 * RATE - k * freq) / (0.04 * RATE), 0, 1)
        if not np.any(alias):
            break
        out += a * np.sin(k * ph) * alias
    return out


def hump(n, peak=0.25, power=1.0):
    """Đường bao một cái bướu mượt: lên nhanh tới [peak] (0..1) rồi tắt dần."""
    u = np.linspace(0, 1, n, endpoint=False) + 0.5 / max(n, 1)
    a = max(peak, 1e-3)
    b = max(1 - peak, 1e-3)
    e = (u / a) ** (a * 4 * power) * ((1 - u) / b) ** (b * 4 * power)
    return e / (e.max() + 1e-12)


def fade(x, inn=0.005, out=0.01):
    x = x.copy()
    a = min(len(x), int(inn * RATE))
    b = min(len(x), int(out * RATE))
    if a:
        x[:a] *= np.sin(np.linspace(0, np.pi / 2, a)) ** 2
    if b:
        x[-b:] *= np.cos(np.linspace(0, np.pi / 2, b)) ** 2
    return x


def contour(n, f0, f1, shape='lin'):
    u = np.linspace(0, 1, n)
    if shape == 'lin':
        return f0 + (f1 - f0) * u
    if shape == 'exp':
        return f0 * (f1 / f0) ** u
    if shape == 'arch':  # lên rồi về lại
        return f0 + (f1 - f0) * np.sin(np.pi * u)
    if shape == 'hook':  # vọt nhanh rồi giữ
        return f0 + (f1 - f0) * (1 - (1 - u) ** 3)
    if shape == 'drop':  # giữ rồi rơi nhanh
        return f0 + (f1 - f0) * u ** 3
    raise ValueError(shape)


def syllable(dur, f0, f1, shape='lin', harm=(1, 0.12, 0.04), peak=0.25, trill=0.0, trill_rate=0.0, rng=None):
    n = max(8, int(dur * RATE))
    f = contour(n, f0, f1, shape)
    if trill:
        f = f * (1 + trill * np.sin(2 * np.pi * trill_rate * np.arange(n) / RATE + (rng.random() * 6 if rng is not None else 0)))
    return tone(f, harm) * hump(n, peak)


def seq(parts):
    """Nối các (tiếng, khoảng nghỉ sau nó)."""
    out = []
    for sig, gap in parts:
        out.append(sig)
        out.append(np.zeros(int(max(gap, 0) * RATE)))
    return np.concatenate(out)


def norm(x):
    return x / (np.max(np.abs(x)) + 1e-12)


def reverb_ir(seconds, rt60, rng, bright=0.5, early=(), predelay=0.012):
    """Đáp ứng xung tiếng vang: ồn tắt dần, tiếng cao tắt nhanh hơn tiếng trầm."""
    n = int(seconds * RATE)
    t = np.arange(n) / RATE
    ir = np.zeros(n)
    bands = [(40, 300, 1.25), (300, 1200, 1.0), (1200, 3500, 0.75 + 0.2 * bright), (3500, 9500, 0.45 + 0.3 * bright)]
    for lo, hi, k in bands:
        b = bandpass(rng.normal(size=n), lo, hi)
        ir += b / (b.std() + 1e-12) * np.exp(-6.9 * t / (rt60 * k)) * (1.0 if hi < 4000 else 0.7)
    ir *= np.clip((t - predelay) / 0.03, 0, 1)
    for delay, gain in early:
        i = int(delay * RATE)
        if i < n:
            spread = lowpass(np.concatenate([[1.0], np.zeros(200)]), 3500)
            ir[i:i + len(spread)] += spread[: n - i] * gain * 12
    return ir / np.sqrt(np.sum(ir ** 2))


def write(name, x, loud_db):
    """Chuẩn hoá về độ to nghe được [loud_db] dBFS (trọng số K, trung bình cả
    vòng) để các cảnh chuyển qua nhau không chênh; đỉnh vượt -4 dB thì uốn
    mềm cho khỏi vỡ tiếng. Xuất WAV 16-bit mono."""
    x = np.asarray(x, dtype=np.float64)
    f = np.fft.rfftfreq(len(x), 1 / RATE)
    x = np.fft.irfft(np.fft.rfft(x) * bp(90, None, order=3)(f), len(x))
    x = x * (10 ** (loud_db / 20) / (rms(k_weighted(x)) + 1e-12))
    th = 0.6
    over = np.abs(x) > th
    x[over] = np.sign(x[over]) * (th + (0.92 - th) * np.tanh((np.abs(x[over]) - th) / (0.92 - th)))
    data = (np.clip(x, -1, 1) * 32767).astype('<i2').tobytes()
    with wave.open(f'{OUT}/{name}.wav', 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)
    db = lambda v: 20 * np.log10(v + 1e-9)  # noqa: E731
    st = short_rms(x, 0.4)
    print(f'{name}: {len(x) / RATE:.1f}s  loud {loud_db:.0f} dB(K)  rms {db(rms(x)):.1f} dB  peak {db(np.max(np.abs(x))):.1f} dB  '
          f'400ms p10/p90 {db(np.percentile(st, 10)):.1f}/{db(np.percentile(st, 90)):.1f} dB  clipped {np.mean(over) * 100:.3f}%')


# =================================================================== Chim
def bulbul_song(rng):
    """Chào mào: câu hót ngắn, lảnh lót, nốt uốn cong lên xuống 1,6–3,2 kHz."""
    k = rng.uniform(0.92, 1.1)
    templates = [
        [('arch', 1900, 2650, 0.11), ('lin', 2500, 1850, 0.08), ('hook', 1750, 2900, 0.13), ('arch', 2300, 2750, 0.15)],
        [('hook', 2000, 2700, 0.09), ('arch', 2400, 3100, 0.12), ('lin', 2900, 2100, 0.1), ('drop', 2300, 1700, 0.14)],
        [('arch', 1800, 2300, 0.1), ('arch', 2100, 2800, 0.1), ('hook', 1900, 3000, 0.16)],
    ]
    t = templates[rng.integers(len(templates))]
    parts = []
    for shape, f0, f1, d in t:
        s = syllable(d * rng.uniform(0.9, 1.1), f0 * k, f1 * k, shape, harm=(1, 0.18, 0.05), peak=0.3)
        parts.append((s * rng.uniform(0.7, 1.0), rng.uniform(0.03, 0.06)))
    return seq(parts)


def sparrow_chirps(rng):
    """Chim sẻ ríu rít: chuỗi tiếng "chíp" ngắn 3–4,5 kHz, hơi rè."""
    parts = []
    k = rng.uniform(0.9, 1.1)
    for _ in range(rng.integers(2, 7)):
        d = rng.uniform(0.04, 0.07)
        n = int(d * RATE)
        u = np.linspace(0, 1, n)
        f = k * (3300 + 1100 * np.sin(np.pi * u ** 0.7) - 500 * u)
        f *= 1 + 0.02 * rng.normal(size=n).cumsum() / np.sqrt(n)
        s = tone(f, (1, 0.35, 0.12)) * hump(n, 0.2)
        parts.append((s * rng.uniform(0.6, 1.0), rng.uniform(0.09, 0.3)))
    return seq(parts)


def robin_song(rng):
    """Chích chòe than: câu hót dài, nhiều nốt huýt sáo uốn lượn và láy rền."""
    parts = []
    k = rng.uniform(0.95, 1.05)
    for _ in range(rng.integers(6, 11)):
        kind = rng.random()
        if kind < 0.45:
            f0, f1 = rng.uniform(1600, 3600), rng.uniform(1600, 4200)
            s = syllable(rng.uniform(0.08, 0.2), f0 * k, f1 * k, rng.choice(['lin', 'arch', 'hook', 'exp']), harm=(1, 0.08, 0.02), peak=0.35)
        elif kind < 0.75:
            f0 = rng.uniform(2200, 3800)
            s = syllable(rng.uniform(0.12, 0.25), f0 * k, f0 * k * rng.uniform(0.85, 1.1), 'lin', harm=(1, 0.1),
                         trill=0.08, trill_rate=rng.uniform(25, 45), peak=0.4, rng=rng)
        else:
            f0 = rng.uniform(1400, 2000)
            s = syllable(rng.uniform(0.15, 0.3), f0 * k, f0 * k * 1.5, 'exp', harm=(1, 0.06), peak=0.6)
        parts.append((s * rng.uniform(0.5, 1.0), rng.uniform(0.04, 0.12)))
    return seq(parts)


def dove_coo(rng):
    """Cu gáy: "cúc cù cu" trầm ấm, mềm, chừng 500–600 Hz."""
    k = rng.uniform(0.93, 1.07)
    harm = (1, 0.07, 0.02)
    a = syllable(0.16, 560 * k, 600 * k, 'arch', harm, peak=0.45)
    b = syllable(0.34, 610 * k, 530 * k, 'lin', harm, peak=0.35, trill=0.012, trill_rate=22, rng=rng)
    c = syllable(0.5, 540 * k, 500 * k, 'lin', harm, peak=0.3)
    s = seq([(a, 0.09), (b * 0.9, 0.12), (c * 0.75, 0.0)])
    breath = bandpass(np.random.default_rng(rng.integers(1 << 30)).normal(size=len(s)), 400, 900) * 0.04
    return s + breath * np.abs(s) / (np.abs(s).max() + 1e-9)


def raspy(n, rng, depth=0.5, lo=40, hi=140):
    """Độ rè (rung biên độ ngẫu nhiên) cho tiếng gà, tiếng hải âu."""
    m = bandpass(rng.normal(size=n + 400), lo, hi)[400:]
    return 1 + depth * m / (np.abs(m).max() + 1e-9)


def formants(x, fs, gains, bw=0.35):
    out = np.zeros(len(x))
    for f, g in zip(fs, gains):
        out += bandpass(x, f * (1 - bw / 2), f * (1 + bw / 2)) * g
    return out


def rooster(rng):
    """Gà trống gáy "ò ó o o": giọng giàu bội âm, rè, lên cao rồi kéo dài rơi xuống."""
    k = rng.uniform(0.93, 1.06)
    segs = [(0.22, 500, 620, 'hook'), (0.32, 700, 780, 'arch'), (0.5, 760, 660, 'lin'), (0.65, 650, 420, 'drop')]
    fs = [np.full(int(0.03 * RATE), 480 * k)]
    for d, f0, f1, sh in segs:
        fs.append(contour(int(d * RATE), f0 * k, f1 * k, sh))
    f = np.concatenate(fs)
    n = len(f)
    f *= 1 + 0.012 * np.sin(2 * np.pi * 7 * np.arange(n) / RATE)
    harm = [1 / (h ** 0.8) for h in range(1, 14)]
    s = tone(f, harm) * raspy(n, rng, 0.6)
    s = formants(s, (900, 1700, 2700), (1, 0.7, 0.35), bw=0.5) + 0.25 * s
    u = np.linspace(0, 1, n)
    env = np.clip(u / 0.04, 0, 1) * (1 - u ** 3) * (0.8 + 0.2 * np.sin(np.pi * np.clip(u * 1.6, 0, 1)))
    return fade(s * env, 0.01, 0.12)


def gull_calls(rng):
    """Hải âu kêu "keo… keo": giọng the thé, rè, rơi cao độ nhanh."""
    parts = []
    k = rng.uniform(0.9, 1.12)
    for i in range(rng.integers(2, 5)):
        d = rng.uniform(0.2, 0.34) * (1.4 if i == 0 else 1)
        n = int(d * RATE)
        u = np.linspace(0, 1, n)
        f = k * (1450 - 520 * u ** 0.8 + 260 * np.exp(-u * 18))
        s = tone(f, (1, 0.75, 0.55, 0.4, 0.28, 0.18, 0.12, 0.08)) * raspy(n, rng, 0.45, 60, 160)
        s = formants(s, (1700, 3200), (1, 0.5), bw=0.8) + 0.3 * s
        parts.append((s * hump(n, 0.12) * rng.uniform(0.7, 1.0), rng.uniform(0.07, 0.16)))
    return seq(parts)


def kite_cry(rng):
    """Diều hâu kêu "kíii…" cao vút, rung, rơi dần (vọng giữa thung lũng)."""
    n = int(1.1 * RATE)
    u = np.linspace(0, 1, n)
    f = 2900 - 900 * u ** 1.5 + 180 * np.sin(2 * np.pi * 9 * u * 1.1)
    s = tone(f, (1, 0.3, 0.1)) * hump(n, 0.08)
    return s


def owl_hoot(rng):
    """Cú mèo: "hú… hù hú" trầm, mềm, có hơi thở."""
    k = rng.uniform(0.95, 1.05)
    harm = (1, 0.12, 0.03)
    a = syllable(0.42, 390 * k, 360 * k, 'arch', harm, peak=0.35)
    b = syllable(0.2, 380 * k, 350 * k, 'lin', harm, peak=0.3)
    c = syllable(0.55, 370 * k, 330 * k, 'lin', harm, peak=0.25)
    s = seq([(a, 0.35), (b * 0.8, 0.12), (c * 0.9, 0)])
    breath = bandpass(rng.normal(size=len(s)), 250, 700)
    return s + breath * 0.06 * np.abs(s) / (np.abs(s).max() + 1e-9)


def coucal(rng):
    """Bìm bịp kêu: chuỗi "bịp bịp bịp" trầm, rỗng, nhanh dần và xuống dần."""
    parts = []
    count = rng.integers(6, 10)
    for i in range(count):
        f0 = 430 - i * 9
        s = syllable(0.13, f0, f0 * 0.93, 'lin', (1, 0.25, 0.06), peak=0.3)
        parts.append((s * (1 - 0.05 * i), max(0.08, 0.26 - i * 0.02)))
    return seq(parts)


def duck_quacks(rng, count=None):
    """Đàn vịt chạy đồng: "cạc cạc" mũi, giàu bội âm."""
    parts = []
    for _ in range(count or rng.integers(2, 5)):
        d = rng.uniform(0.12, 0.2)
        n = int(d * RATE)
        u = np.linspace(0, 1, n)
        f = rng.uniform(260, 340) * (1.12 - 0.22 * u)
        s = tone(f, [1 / h ** 0.5 for h in range(1, 16)]) * raspy(n, rng, 0.35, 30, 90)
        s = formants(s, (1100, 2100), (1, 0.6), bw=0.5)
        parts.append((s * hump(n, 0.15) * rng.uniform(0.6, 1.0), rng.uniform(0.06, 0.2)))
    return seq(parts)


def bird_scene(loop, name, makers, rate, dist=(0.2, 0.8), send=0.3):
    """Rải tiếng chim quanh vòng: mỗi con ở một khoảng cách."""
    rng = loop.rng
    for at in loop.times(rate, jitter=0.9):
        make, weight = makers[rng.integers(len(makers))]
        d = rng.uniform(*dist)
        s = far(make(rng), d)
        loop.put(name, s / (np.abs(s).max() + 1e-9), at, weight * (1 - 0.75 * d), send=send + 0.4 * d)


# ================================================================ Côn trùng
def cricket(loop, name, carrier, pulses, pulse_len, pulse_gap, period, gain, send=0.15, distance=0.3, jitter=0.03):
    """Dế gáy đều cả đêm: mỗi lần "re-re-re" vài xung sóng mang [carrier] Hz."""
    rng = loop.rng
    one = []
    for p in range(pulses):
        n = int(pulse_len * RATE)
        u = np.linspace(0, 1, n)
        f = carrier * (1.0 - 0.025 * u) * (1 + 0.004 * p)
        s = tone(f, (1, 0.06)) * np.sin(np.pi * u) ** 1.5
        one.append((s, pulse_gap))
    chirp = far(seq(one), distance)
    count = max(1, int(round(loop.seconds / period)))
    step = loop.seconds / count
    phase = rng.random() * step
    # Lúc gáy dồn, lúc ngừng nghỉ (tuần hoàn theo vòng).
    activity = np.clip(0.75 + 0.6 * loop.slow(0.08), 0, 1.2)
    for k in range(count):
        at = phase + k * step + rng.normal() * jitter * step
        a = activity[int(at * RATE) % loop.n]
        if a > 0.08:
            loop.put(name, chirp, at, gain * a * rng.uniform(0.85, 1.0), send=send)


def trill_insect(loop, name, carrier, rate, gain=1.0, width=0.05, lo_mod=0.05):
    """Côn trùng rỉ rả liên tục làm nền đêm: một dải ồn hẹp quanh [carrier]
    rung đều [rate] lần mỗi giây (không phải một nốt sine trơn kiểu tiếng bíp)."""
    t = np.arange(loop.n) / RATE
    car = loop.noise(bp(carrier * (1 - width), carrier * (1 + width), order=4))
    pr = round(rate * loop.seconds) / loop.seconds
    am = np.clip(np.sin(2 * np.pi * pr * t), 0, None) ** 2
    swell = np.clip(0.7 + 0.5 * loop.slow(lo_mod), 0.1, 1.3)
    loop.bed(name, car * am * swell, gain)


# ===================================================================== Ếch
def frog_croak(rng, pulse_hz, f1, f2, dur):
    """Ếch đồng "ộp": chuỗi xung thanh môn qua hai cộng hưởng."""
    n = int(dur * RATE)
    exc = np.zeros(n)
    t = 0.0
    while t < dur:
        i = int(t * RATE)
        if i < n:
            exc[i] = 1.0 + 0.2 * rng.normal()
        t += (1 / pulse_hz) * (1 + 0.05 * rng.normal())
    ir_t = np.arange(int(0.025 * RATE)) / RATE
    ir = np.sin(2 * np.pi * f1 * ir_t) * np.exp(-ir_t * np.pi * 140) + 0.55 * np.sin(2 * np.pi * f2 * ir_t) * np.exp(-ir_t * np.pi * 220)
    s = signal.fftconvolve(exc, ir)[:n]
    return s * hump(n, 0.3)


def frog_chorus(loop, name, count, dist=(0.2, 0.9)):
    rng = loop.rng
    for _ in range(count):
        pulse = rng.uniform(70, 120)
        f1, f2 = rng.uniform(500, 800), rng.uniform(1100, 1600)
        d = rng.uniform(*dist)
        # Mỗi con kêu từng đợt 2–5 tiếng, nghỉ vài giây.
        for at in loop.times(rng.uniform(0.12, 0.3), jitter=0.9):
            bout = []
            for _ in range(rng.integers(2, 6)):
                bout.append((frog_croak(rng, pulse, f1, f2, rng.uniform(0.12, 0.22)), rng.uniform(0.14, 0.3)))
            s = far(seq(bout), d)
            loop.put(name, s, at, 1 - 0.7 * d, send=0.15 + 0.4 * d)


def banded_bullfrog(rng):
    """Ễnh ương "ễnh… ương": trầm, rỗng, như tiếng bò rống nhỏ."""
    k = rng.uniform(0.92, 1.08)
    harm = (1, 0.6, 0.4, 0.22, 0.12, 0.06)
    a = syllable(0.12, 400 * k, 440 * k, 'arch', harm, peak=0.35)
    b = syllable(0.4, 330 * k, 290 * k, 'lin', harm, peak=0.25)
    s = seq([(a, 0.06), (b, 0)])
    return bandpass(pad(s, 0.05), 200, 1200) + 0.2 * pad(s, 0.05)


def toad_trill(rng, dur=1.6):
    """Cóc rền: chuỗi xung đều ~18 lần/giây kéo dài."""
    n = int(dur * RATE)
    t = np.arange(n) / RATE
    rate = rng.uniform(16, 21)
    gate = np.clip(np.sin(2 * np.pi * rate * t), 0, None) ** 3
    car = tone(np.full(n, rng.uniform(1100, 1400)), (1, 0.3, 0.1))
    return car * gate * hump(n, 0.15, 0.6)


def dog_barks(rng):
    """Chó sủa xa "gâu gâu": giọng rè giàu bội âm, rơi cao độ."""
    parts = []
    base = rng.uniform(380, 520)
    for _ in range(rng.integers(2, 4)):
        d = rng.uniform(0.13, 0.2)
        n = int(d * RATE)
        u = np.linspace(0, 1, n)
        f = base * (1.25 - 0.35 * u ** 0.6)
        s = tone(f, [1 / h ** 0.6 for h in range(1, 12)]) * raspy(n, rng, 0.4, 30, 100)
        s += bandpass(rng.normal(size=n), 600, 2500) * 0.35
        s = formants(s, (700, 1400, 2300), (1, 0.8, 0.4), bw=0.6)
        parts.append((s * hump(n, 0.1), rng.uniform(0.22, 0.4)))
    return seq(parts)


# ==================================================================== Gió
def wind(loop, name, lo, hi, gust_hz=0.12, depth=0.7, floor=0.3, color=pink, gust=None):
    """Gió: ồn lọc dải, to nhỏ theo cơn (trả về đường bao cơn gió để lớp lá
    cây, gió hú bám theo)."""
    g = gust if gust is not None else np.clip(1 + depth * loop.slow(gust_hz), floor, None)
    x = loop.noise(color(bp(lo, hi)))
    loop.bed(name, x * g)
    return g


def rustle(loop, name, gust, lo=1800, hi=8000):
    """Lá cây, ruộng lúa xào xạc: ồn cao, rung lật phật theo cơn gió."""
    flutter = np.abs(loop.noise(bp(6, 28)))
    x = loop.noise(bp(lo, hi))
    loop.bed(name, x * flutter * gust ** 1.8)


def howl(loop, name, gust, centers=(360, 520, 760)):
    """Gió hú qua khe núi: mấy dải ồn hẹp, to lên khi cơn gió mạnh."""
    for c in centers:
        q = loop.noise(bp(c * 0.95, c * 1.05, order=4))
        m = np.clip(0.4 + 0.6 * loop.slow(0.09), 0, None)
        loop.bed(name, q * m * np.clip(gust - 0.8, 0, None) ** 2)


def bamboo_creak(rng):
    """Thân tre cọ vào nhau kẽo kẹt: ma sát dính-trượt qua cộng hưởng gỗ."""
    dur = rng.uniform(0.35, 0.7)
    n = int(dur * RATE)
    t = np.arange(n) / RATE
    rate = rng.uniform(28, 55) * (1 + 0.3 * np.sin(np.pi * t / dur))
    ph = np.cumsum(rate) / RATE
    exc = (np.diff(np.floor(ph), prepend=0) > 0).astype(float) * (1 + 0.3 * rng.normal(size=n))
    ir_t = np.arange(int(0.04 * RATE)) / RATE
    f = rng.uniform(650, 1100)
    ir = np.sin(2 * np.pi * f * ir_t) * np.exp(-ir_t * 90) + 0.5 * np.sin(2 * np.pi * f * 2.3 * ir_t) * np.exp(-ir_t * 160)
    return signal.fftconvolve(exc, ir)[:n] * hump(n, 0.5)


# ===================================================================== Nước
def wave_event(rng, size=1.0):
    """Một con sóng: dâng ù ù, vỡ ào, bọt xèo xèo, rút về lạo xạo cát sỏi."""
    T = rng.uniform(6.5, 8.5)
    n = int(T * RATE)
    t = np.arange(n) / RATE
    rise = rng.uniform(1.4, 2.0)
    out = np.zeros(n)
    after = np.clip(t - rise, 0, None)
    up = np.clip(t / rise, 0, 1) ** 2.5
    bands = [
        (40, 150, 1.0, 2.2, 0.0),
        (150, 400, 0.95, 1.6, 0.0),
        (400, 1000, 0.8, 1.2, 0.05),
        (1000, 2500, 0.55, 1.0, 0.12),
        (2500, 6000, 0.32, 1.3, 0.22),
        (6000, 10000, 0.1, 0.8, 0.3),
    ]
    for lo, hi, g, tau, lag in bands:
        b = bandpass(rng.normal(size=n), lo, hi)
        b /= b.std() + 1e-12
        env = np.where(t < rise + lag, up * (0.3 if lo >= 1000 else 1.0), np.exp(-np.clip(t - rise - lag, 0, None) / tau))
        out += b * env * g
    # Bọt vỡ lách tách sau khi sóng đổ.
    fizz = np.zeros(n)
    count = int(260 * size)
    for _ in range(count):
        at = rise + rng.exponential(1.1)
        i = int(at * RATE)
        if i + 60 >= n:
            continue
        fizz[i:i + 60] += rng.normal(size=60) * np.exp(-np.arange(60) / 12) * rng.uniform(0.3, 1)
    out += highpass(fizz, 2500) * 0.9
    # Nước rút: cát sỏi lạo xạo.
    back = bandpass(rng.normal(size=n), 2200, 6500) * np.abs(bandpass(rng.normal(size=n), 8, 40)) * 4
    win = np.exp(-((t - rise - 3.2) / 1.0) ** 2)
    out += back * win * 0.35
    return fade(out * size, 0.05, 0.3)


def bubbles(loop, name, rate, lo, hi, distance=0.5):
    """Suối chảy róc rách: vô số bọt nước nhỏ (tần số hơi vút lên khi vỡ)."""
    rng = loop.rng
    buf = np.zeros(loop.n)
    count = int(rate * loop.seconds)
    for _ in range(count):
        f0 = np.exp(rng.uniform(np.log(lo), np.log(hi)))
        tau = 0.0025 + 0.012 * (lo / f0) ** 0.5 * rng.random()
        n = int(tau * 6 * RATE) + 8
        t = np.arange(n) / RATE
        f = f0 * (1 + 0.15 * t / (tau * 6))
        s = np.sin(2 * np.pi * np.cumsum(f) / RATE) * np.exp(-t / tau) * rng.uniform(0.2, 1.0)
        wrap_add(buf, s, rng.integers(loop.n))
    bed = loop.noise(bp(lo * 0.7, hi * 1.3)) * 0.35 * np.abs(loop.noise(bp(3, 14)))
    x = buf / (buf.std() + 1e-12) + bed
    cutoff = 9000 * (1 - distance) ** 1.6 + 900
    x = np.fft.irfft(np.fft.rfft(x) * bp(None, cutoff)(np.fft.rfftfreq(loop.n, 1 / RATE)), loop.n)
    loop.bed(name, x / (x.std() + 1e-12))


def lap(rng):
    """Nước vỗ mạn xuồng / bờ kênh: tiếng "óc ách" trầm, ngắn."""
    n = int(rng.uniform(0.25, 0.45) * RATE)
    t = np.arange(n) / RATE
    body = bandpass(rng.normal(size=n), 160, 700) * np.exp(-t / 0.09) * np.clip(t / 0.035, 0, 1)
    hull = np.sin(2 * np.pi * rng.uniform(220, 360) * t) * np.exp(-t / 0.07) * 0.5 * np.clip(t / 0.01, 0, 1)
    slap = bandpass(rng.normal(size=n), 700, 2200) * np.exp(-t / 0.02) * np.clip(t / 0.008, 0, 1) * 0.12
    s = body / (body.std() + 1e-9) * 0.4 + hull + slap
    for _ in range(rng.integers(0, 3)):
        f0 = rng.uniform(500, 1400)
        k = rng.integers(int(0.03 * RATE), n // 2)
        m = n - k
        tb = np.arange(m) / RATE
        s[k:] += np.sin(2 * np.pi * np.cumsum(f0 * (1 + 0.6 * tb)) / RATE) * np.exp(-tb / 0.012) * 0.3
    return s


# ================================================================ Máy, còi
def boat_engine(loop, name, firing=15.0, closest=0.35):
    """Ghe máy nổ "tạch tạch" xa xa trên sông: xung nổ đều, lại gần rồi đi xa."""
    rng = loop.rng
    n = loop.n
    t = np.arange(n) / RATE
    rate = firing * (1 + 0.03 * loop.slow(0.3))
    ph = np.cumsum(rate) / RATE
    ph *= round(ph[-1]) / ph[-1]
    fire = np.diff(np.floor(ph), prepend=0) > 0
    exc = fire * (1 + 0.25 * rng.normal(size=n))
    pop_t = np.arange(int(0.06 * RATE)) / RATE
    body = sum(np.sin(2 * np.pi * 150 * h * pop_t) / h for h in (1, 2, 3, 4)) * np.exp(-pop_t / 0.016)
    pop = body * 0.6 + bandpass(rng.normal(size=len(pop_t)), 250, 1800) * np.exp(-pop_t / 0.007) * 1.4
    spec = np.fft.rfft(exc) * np.fft.rfft(pop, n)
    x = np.fft.irfft(spec, n)
    # Ghe đi ngang qua: gần nhất ở giữa vòng (khoảng cách tuần hoàn).
    center = loop.seconds * rng.uniform(0.35, 0.65)
    dt = (t - center + loop.seconds / 2) % loop.seconds - loop.seconds / 2
    r = np.sqrt(closest ** 2 + (dt / loop.seconds * 2.2) ** 2)
    near = closest / r
    f = np.fft.rfftfreq(n, 1 / RATE)
    dark = np.fft.irfft(np.fft.rfft(x) * bp(None, 700)(f), n)
    bright = np.fft.irfft(np.fft.rfft(x) * bp(None, 2400)(f), n)
    w = np.clip((near - 0.3) / 0.7, 0, 1)
    y = dark * (1 - w) + bright * w
    loop.bed(name, y / (y.std() + 1e-12) * near)


def scooter_pass(rng, dur=5.0, fire=None, speed=None, closest=None, bright=1.0):
    """Xe máy chạy ngang qua: tiếng máy bốn thì có Doppler, lốp rào rào."""
    fire = fire or rng.uniform(38, 55)
    speed = speed or rng.uniform(7, 12)
    closest = closest or rng.uniform(5, 12)
    n = int(dur * RATE)
    t = np.arange(n) / RATE - dur / 2
    x = speed * t
    r = np.sqrt(closest ** 2 + x ** 2)
    vr = speed * x / r
    doppler = 343 / (343 + vr)
    f = fire * (1 + 0.035 * np.sin(2 * np.pi * rng.uniform(0.4, 0.9) * t + rng.random() * 6)) * doppler
    harm = [0.5, 0.8, 1, 0.9, 0.8, 0.7, 0.6, 0.52, 0.45, 0.4, 0.35, 0.3, 0.26, 0.22, 0.19, 0.16, 0.14, 0.12, 0.1, 0.09, 0.08, 0.07, 0.06, 0.05]
    eng = tone(f, harm)
    ph = 2 * np.pi * np.cumsum(f) / RATE
    exhaust = bandpass(rng.normal(size=n), 250, 2500) * (0.5 + 0.5 * np.cos(ph)) ** 4 * 2.4
    # Dây curoa hộp số vô cấp (xe tay ga) rít khẽ, lên xuống theo Doppler.
    whine = tone(f * rng.uniform(26, 34), (1, 0.2)) * 0.06
    tire = bandpass(rng.normal(size=n), 500, 3500) * 0.4
    s = eng * 0.4 + exhaust * 0.5 + whine + tire
    near = closest / r
    dark = lowpass(s, 1100)
    s = dark * (1 - near) + s * near * bright
    return fade(s * near, 0.2, 0.2)


def horn(rng, car=False):
    """Còi xe: "bíp bíp" xe máy, hoặc còi kép ô tô; vang qua dãy nhà."""
    patterns = [[0.11, 0.13], [0.35], [0.09, 0.09, 0.14], [0.18]]
    pat = patterns[rng.integers(len(patterns))]
    f0 = rng.uniform(400, 480) if not car else rng.uniform(380, 430)
    parts = []
    for d in pat:
        n = int(d * RATE)
        f = np.full(n, f0) * (1 + 0.004 * np.sin(2 * np.pi * 30 * np.arange(n) / RATE))
        harm = [1, 0.15, 0.4, 0.1, 0.25, 0.06, 0.15, 0.04, 0.1]
        s = tone(f, harm)
        if car:
            s += tone(f * 1.26, harm) * 0.8
        s = bandpass(s, 300, 3200)
        parts.append((fade(s, 0.006, 0.02), rng.uniform(0.07, 0.11)))
    return seq(parts)


VOWELS = [(800, 1250, 2500), (500, 1850, 2500), (320, 2250, 3000), (500, 880, 2400), (360, 800, 2300), (520, 1300, 2400), (380, 1450, 2400)]


def babble(rng, seconds, f0=125, rate=4.5, phrase=(6, 10)):
    """Lời nói không thành chữ (giọng có thanh điệu lên xuống) — để làm loa
    phường văng vẳng, tiếng người lao xao. Không nghe ra câu chữ nào."""
    out = []
    total = 0.0
    left = rng.integers(*phrase)
    while total < seconds:
        d = rng.uniform(0.7, 1.3) / rate
        n = int(d * RATE)
        u = np.linspace(0, 1, n)
        tone_kind = rng.integers(5)
        bend = [np.zeros(n), 0.18 * u, -0.2 * u, -0.15 * np.sin(np.pi * u), 0.1 * u ** 2][tone_kind]
        f = f0 * rng.uniform(0.92, 1.08) * (1 + bend)
        src = tone(f, [1 / h for h in range(1, 26)])
        v = VOWELS[rng.integers(len(VOWELS))]
        s = formants(src, v, (1, 0.55, 0.25), bw=0.25)
        if rng.random() < 0.6:
            c = int(0.035 * RATE)
            s[:c] += bandpass(rng.normal(size=c), 2000, 5500) * 0.4 * np.linspace(1, 0, c)
        out.append(s * hump(n, 0.3))
        total += d
        left -= 1
        if left <= 0:
            gap = rng.uniform(0.35, 0.8)
            out.append(np.zeros(int(gap * RATE)))
            total += gap
            left = rng.integers(*phrase)
    return np.concatenate(out)


def loudspeaker(rng, seconds):
    """Loa phường đọc thông báo xa xa: giọng qua loa nén méo, vọng giữa phố."""
    v = babble(rng, seconds, f0=rng.uniform(170, 210), rate=4.8)
    v = bandpass(v, 450, 3200, order=3)
    v = np.tanh(v / (np.abs(v).max() + 1e-9) * 3.0)
    v = bandpass(v, 500, 3000)
    v = pad(v, 1.2)
    echo = v.copy()
    for delay, g in [(0.19, 0.55), (0.41, 0.35), (0.73, 0.2)]:
        i = int(delay * RATE)
        echo[i:] += v[:-i] * g
    return lowpass(echo, 2400)


def crowd(loop, name, voices, f0=(110, 260)):
    """Người lao xao (chợ, phố đêm giao thừa)."""
    rng = loop.rng
    for _ in range(voices):
        v = babble(rng, rng.uniform(4, 9), f0=rng.uniform(*f0), rate=rng.uniform(4, 6))
        v = lowpass(v, 3000)
        loop.put(name, fade(v, 0.3, 0.6) / (np.abs(v).max() + 1e-9), rng.uniform(0, loop.seconds), rng.uniform(0.5, 1.0))


def cheer(rng):
    """Mọi người reo "ồ… ê…" khi pháo hoa nở."""
    dur = rng.uniform(1.4, 2.2)
    n = int(dur * RATE)
    out = np.zeros(n)
    for _ in range(18):
        f0 = rng.uniform(170, 380)
        u = np.linspace(0, 1, n)
        f = f0 * (1 + 0.15 * np.sin(np.pi * u) + 0.01 * rng.normal())
        src = tone(f, [1 / h for h in range(1, 18)])
        v = VOWELS[rng.choice([1, 3, 0])]
        s = formants(src, v, (1, 0.5, 0.2), bw=0.3)
        out += s * hump(n, rng.uniform(0.2, 0.4)) * rng.uniform(0.4, 1)
    out += bandpass(rng.normal(size=n), 300, 3000) * hump(n, 0.3) * 0.15 * np.abs(out).max()
    return lowpass(out, 3200)


# ============================================================== Trống, pháo
def big_drum(rng, accent=1.0):
    n = int(0.45 * RATE)
    t = np.arange(n) / RATE
    f = 62 + 45 * np.exp(-t / 0.03)
    body = np.sin(2 * np.pi * np.cumsum(f) / RATE) * np.exp(-t / 0.22)
    skin = lowpass(rng.normal(size=n), 900) * np.exp(-t / 0.03) * 0.5
    return (body + skin) * accent


def rim_click(rng):
    n = int(0.05 * RATE)
    t = np.arange(n) / RATE
    return (np.sin(2 * np.pi * 1900 * t) * np.exp(-t / 0.008) + bandpass(rng.normal(size=n), 1500, 4000) * np.exp(-t / 0.004)) * 0.5


def cymbal(rng, dur=0.5):
    """Chập chõa (não bạt) đội lân: nhiều sóng kim loại không hoà âm."""
    n = int(dur * RATE)
    t = np.arange(n) / RATE
    s = np.zeros(n)
    for _ in range(40):
        s += np.sin(2 * np.pi * rng.uniform(2500, 8500) * t + rng.random() * 6)
    s = s / 6 + highpass(rng.normal(size=n), 4000) * 0.8
    return s * np.exp(-t / (dur / 3.5)) * np.clip(t / 0.003, 0, 1)


def lion_dance(loop, name, bpm=150, play=(0.0, 0.62)):
    """Đội múa lân xa xa: trống cái "tùng tùng cắc", chập chõa dồn."""
    rng = loop.rng
    beat = 60 / bpm
    eighth = beat / 2
    # 2 ô nhịp (16 móc đơn): T = trống, C = cắc vành, X = chập chõa.
    pattern = ['T', '', 'T', '', 'TX', '', 'C', 'T', 'T', '', 'TX', 'C', '', 'T', 'TX', 'C']
    start = loop.seconds * play[0]
    length = loop.seconds * play[1]
    at = 0.0
    k = 0
    while at < length:
        hit = pattern[k % len(pattern)]
        time = start + at + rng.normal() * 0.006
        # Đội lân ở xa: tiếng cao bị không khí nuốt bớt.
        if 'T' in hit:
            loop.put(name, far(big_drum(rng, 1.0 if k % 4 == 0 else 0.75), 0.4), time)
        if 'C' in hit:
            loop.put(name, far(rim_click(rng), 0.45), time, 0.6)
        if 'X' in hit:
            loop.put(name, far(cymbal(rng, 0.35), 0.5), time, 0.3)
        at += eighth
        k += 1


def firework_far(rng):
    """Pháo hoa nổ xa: tiếng "ùm" trầm vọng rồi lách tách."""
    n = int(2.8 * RATE)
    t = np.arange(n) / RATE
    boom = lowpass(rng.normal(size=n), 160) * np.exp(-t / 0.35) * np.clip(t / 0.01, 0, 1)
    thump = bandpass(rng.normal(size=n), 150, 700) * np.exp(-t / 0.12) * np.clip(t / 0.005, 0, 1)
    boom = boom / (boom.std() + 1e-9) * 0.45 + thump / (thump.std() + 1e-9) * 0.35
    crack = np.zeros(n)
    for _ in range(120):
        at = 0.35 + rng.random() ** 1.5 * 1.8
        i = int(at * RATE)
        if i + 50 < n:
            crack[i:i + 50] += rng.normal(size=50) * np.exp(-np.arange(50) / 10) * rng.uniform(0.2, 1) * np.exp(-(at - 0.35))
    crack = lowpass(crack, 3500) * 0.8
    return boom + crack


def bell_tinkle(rng):
    """Lục lạc ngựa thồ: mấy tiếng leng keng kim loại nhỏ."""
    out = []
    for _ in range(rng.integers(3, 7)):
        n = int(0.35 * RATE)
        t = np.arange(n) / RATE
        f0 = rng.uniform(2400, 3000)
        s = sum(np.sin(2 * np.pi * f0 * r * t) * np.exp(-t / (0.12 / r)) / r for r in (1, 1.52, 2.33, 3.1))
        out.append((s * np.clip(t / 0.002, 0, 1), rng.uniform(0.12, 0.35)))
    return seq(out)


# ============================================================ Các cảnh nền
# Mức các lớp tính bằng dB (tương đối với nhau; cả cảnh được chuẩn hoá lại
# theo độ to nghe được ở bước ghi file).
def delta_day():
    loop = Loop(24, seed=101)
    rng = loop.rng
    loop.layer('wind', -33, 'bed')
    loop.layer('wind_low', -41, 'bed')
    loop.layer('rustle', -39, 'bed')
    loop.layer('birds', -16, send=0.3)
    loop.layer('dove', -21, send=0.5)
    loop.layer('creak', -31, send=0.2)
    loop.layer('rooster', -21, send=0.7)
    gust = wind(loop, 'wind', 150, 2500, gust_hz=0.1, depth=0.55)
    rustle(loop, 'rustle', gust)
    wind(loop, 'wind_low', 40, 300, gust_hz=0.07, color=brown)
    bird_scene(loop, 'birds', [(bulbul_song, 1.0), (sparrow_chirps, 0.7), (robin_song, 0.6)], rate=0.55, dist=(0.15, 0.75))
    for at in loop.times(0.12):
        loop.put('dove', far(dove_coo(rng), 0.5), at, rng.uniform(0.6, 1.0))
    for at in loop.times(0.09):
        loop.put('creak', far(bamboo_creak(rng), 0.35), at, rng.uniform(0.5, 1.0))
    loop.put('rooster', far(rooster(rng), 0.6), loop.seconds * 0.62)
    return loop.mix(reverb_ir(1.2, 0.7, rng, bright=0.3), 0.5)


def delta_night():
    loop = Loop(22, seed=202)
    rng = loop.rng
    loop.layer('breeze', -41, 'bed')
    loop.layer('rustle', -48, 'bed')
    loop.layer('trill', -37, 'bed', send=0.2)
    loop.layer('trill_hi', -43, 'bed', send=0.2)
    loop.layer('crickets', -20, send=0.15)
    loop.layer('frogs', -24)
    loop.layer('bullfrog', -21, send=0.4)
    loop.layer('toad', -29, send=0.3)
    loop.layer('dog', -28, send=0.8)
    gust = wind(loop, 'breeze', 100, 1500, gust_hz=0.08, depth=0.5)
    rustle(loop, 'rustle', gust)
    trill_insect(loop, 'trill', 5200, 52)
    trill_insect(loop, 'trill_hi', 7100, 64)
    cricket(loop, 'crickets', 4300, 3, 0.018, 0.016, 0.62, 1.0, distance=0.2)
    cricket(loop, 'crickets', 4750, 4, 0.016, 0.014, 0.83, 0.7, distance=0.4)
    cricket(loop, 'crickets', 3900, 2, 0.022, 0.02, 0.55, 0.5, distance=0.6)
    cricket(loop, 'crickets', 5100, 5, 0.012, 0.012, 1.1, 0.4, distance=0.5)
    frog_chorus(loop, 'frogs', 7)
    for at in loop.times(0.18):
        loop.put('bullfrog', far(banded_bullfrog(rng), rng.uniform(0.3, 0.7)), at, rng.uniform(0.5, 1.0))
    loop.put('toad', far(toad_trill(rng), 0.5), loop.seconds * 0.3)
    loop.put('dog', far(dog_barks(rng), 0.8), loop.seconds * 0.7)
    return loop.mix(reverb_ir(1.4, 0.9, rng, bright=0.25), 0.55)


def coast_day():
    loop = Loop(24, seed=303)
    rng = loop.rng
    loop.layer('surf', -29, 'bed')
    loop.layer('waves', -14, send=0.1)
    loop.layer('wind', -34, 'bed')
    loop.layer('casuarina', -41, 'bed')
    loop.layer('gulls', -19, send=0.3)
    # Sóng xa ì ầm làm nền, ba bốn con sóng gần vỗ bờ.
    loop.bed('surf', loop.noise(pink(bp(70, 2000))) * np.clip(1 + 0.5 * loop.slow(0.14), 0.25, None))
    at = rng.uniform(0, 2)
    while at < loop.seconds - 0.5:
        loop.put('waves', wave_event(rng, 1.0), at, rng.uniform(0.6, 1.0))
        at += rng.uniform(5.2, 7.5)
    gust = wind(loop, 'wind', 200, 3000, gust_hz=0.12, depth=0.6)
    # Phi lao vi vu: ồn cao mỏng, lên xuống theo gió.
    loop.bed('casuarina', loop.noise(bp(1800, 5500)) * gust ** 2)
    for at in loop.times(0.16):
        d = rng.uniform(0.2, 0.7)
        loop.put('gulls', far(gull_calls(rng), d), at, 1 - 0.6 * d)
    return loop.mix(reverb_ir(1.0, 0.5, rng, bright=0.4), 0.35)


def coast_night():
    loop = Loop(22, seed=404)
    rng = loop.rng
    loop.layer('surf', -28, 'bed')
    loop.layer('waves', -15, send=0.12)
    loop.layer('wind', -35, 'bed')
    loop.layer('casuarina', -45, 'bed')
    loop.layer('crickets', -27, send=0.2)
    loop.bed('surf', loop.noise(pink(bp(60, 1600))) * np.clip(1 + 0.5 * loop.slow(0.12), 0.25, None))
    at = rng.uniform(0, 2)
    while at < loop.seconds - 0.5:
        loop.put('waves', lowpass(wave_event(rng, 1.0), 4500), at, rng.uniform(0.55, 1.0))
        at += rng.uniform(5.5, 8.0)
    gust = wind(loop, 'wind', 150, 2400, gust_hz=0.1, depth=0.6)
    loop.bed('casuarina', loop.noise(bp(1800, 5000)) * gust ** 2)
    cricket(loop, 'crickets', 4500, 3, 0.017, 0.015, 0.7, 1.0, distance=0.45)
    cricket(loop, 'crickets', 4100, 2, 0.02, 0.018, 0.9, 0.6, distance=0.6)
    return loop.mix(reverb_ir(1.0, 0.5, rng, bright=0.3), 0.35)


def mountain_day():
    loop = Loop(24, seed=505)
    rng = loop.rng
    loop.layer('wind_low', -33, 'bed')
    loop.layer('wind', -34, 'bed')
    loop.layer('howl', -39, 'bed', send=0.3)
    loop.layer('pines', -41, 'bed')
    loop.layer('stream', -38, 'bed', send=0.3)
    loop.layer('birds', -21, send=0.6)
    loop.layer('kite', -19, send=0.9)
    loop.layer('bells', -29, send=0.6)
    gust = wind(loop, 'wind_low', 50, 900, gust_hz=0.16, depth=0.8, floor=0.25, color=brown)
    wind(loop, 'wind', 300, 4000, gust=gust * np.clip(1 + 0.3 * loop.slow(0.4), 0.5, None))
    howl(loop, 'howl', gust)
    rustle(loop, 'pines', gust, lo=2500, hi=8500)  # rừng thông reo
    bubbles(loop, 'stream', 70, 350, 2600, distance=0.6)
    bird_scene(loop, 'birds', [(robin_song, 0.8), (bulbul_song, 0.7), (sparrow_chirps, 0.5)], rate=0.4, dist=(0.35, 0.9), send=0.6)
    loop.put('kite', far(kite_cry(rng), 0.45), loop.seconds * 0.4)
    loop.put('bells', far(bell_tinkle(rng), 0.6), loop.seconds * 0.78)
    # Thung lũng: vang dài, có tiếng dội từ vách đá.
    ir = reverb_ir(2.6, 1.9, rng, bright=0.35, early=[(0.23, 0.35), (0.47, 0.22), (0.81, 0.12)])
    return loop.mix(ir, 0.6)


def mountain_night():
    loop = Loop(22, seed=606)
    rng = loop.rng
    loop.layer('wind_low', -32, 'bed')
    loop.layer('wind', -35, 'bed')
    loop.layer('howl', -36, 'bed', send=0.3)
    loop.layer('stream', -37, 'bed', send=0.3)
    loop.layer('crickets', -28, send=0.25)
    loop.layer('owl', -19, send=0.7)
    gust = wind(loop, 'wind_low', 40, 700, gust_hz=0.13, depth=0.9, floor=0.25, color=brown)
    wind(loop, 'wind', 250, 3000, gust=gust * np.clip(1 + 0.3 * loop.slow(0.4), 0.5, None))
    howl(loop, 'howl', gust, centers=(300, 440, 610))
    bubbles(loop, 'stream', 60, 300, 2200, distance=0.55)
    cricket(loop, 'crickets', 4000, 2, 0.02, 0.02, 0.95, 1.0, distance=0.5)
    cricket(loop, 'crickets', 4600, 3, 0.016, 0.016, 1.3, 0.6, distance=0.65)
    loop.put('owl', far(owl_hoot(rng), 0.5), loop.seconds * 0.25)
    loop.put('owl', far(owl_hoot(rng), 0.7), loop.seconds * 0.72, 0.6)
    ir = reverb_ir(2.6, 1.9, rng, bright=0.3, early=[(0.25, 0.3), (0.52, 0.18)])
    return loop.mix(ir, 0.6)


def mekong_day():
    loop = Loop(24, seed=707)
    rng = loop.rng
    loop.layer('breeze', -41, 'bed')
    loop.layer('palms', -43, 'bed')
    loop.layer('water', -38, 'bed')
    loop.layer('laps', -22, send=0.1)
    loop.layer('boat', -31, 'bed', send=0.35)
    loop.layer('birds', -18, send=0.3)
    loop.layer('dove', -22, send=0.5)
    loop.layer('coucal', -21, send=0.6)
    loop.layer('ducks', -24, send=0.5)
    gust = wind(loop, 'breeze', 120, 2000, gust_hz=0.1, depth=0.5)
    rustle(loop, 'palms', gust, lo=1500, hi=6000)  # lá dừa nước sột soạt
    loop.bed('water', loop.noise(pink(bp(80, 900))) * np.clip(1 + 0.4 * loop.slow(0.3), 0.2, None))
    for at in loop.times(0.9, jitter=0.8):
        loop.put('laps', lap(rng), at, rng.uniform(0.4, 1.0))
    boat_engine(loop, 'boat')
    bird_scene(loop, 'birds', [(bulbul_song, 1.0), (sparrow_chirps, 0.7)], rate=0.45, dist=(0.2, 0.8))
    for at in loop.times(0.1):
        loop.put('dove', far(dove_coo(rng), 0.5), at, rng.uniform(0.6, 1.0))
    loop.put('coucal', far(coucal(rng), 0.55), loop.seconds * 0.15)
    for at in loop.times(0.15):
        loop.put('ducks', far(duck_quacks(rng), rng.uniform(0.5, 0.8)), at, rng.uniform(0.5, 1.0))
    return loop.mix(reverb_ir(1.3, 0.8, rng, bright=0.3), 0.45)


def city():
    loop = Loop(22, seed=808)
    rng = loop.rng
    loop.layer('hum', -37, 'bed')
    loop.layer('traffic', -37, 'bed')
    loop.layer('swarm', -27, send=0.4)
    loop.layer('scooters', -19, send=0.25)
    loop.layer('horns', -21, send=0.5)
    loop.layer('speaker', -30, send=0.8)
    loop.layer('crowd', -37, send=0.4)
    loop.bed('hum', loop.noise(brown(bp(30, 400))) * np.clip(1 + 0.3 * loop.slow(0.1), 0.3, None))
    loop.bed('traffic', loop.noise(pink(bp(150, 2500))) * np.clip(1 + 0.4 * loop.slow(0.2), 0.2, None))
    # Đàn xe máy xa xa rì rì không dứt, vài chiếc chạy sát qua.
    for at in loop.times(1.4, jitter=1.0):
        loop.put('swarm', scooter_pass(rng, dur=6, closest=rng.uniform(25, 60), bright=0.6), at, rng.uniform(0.5, 1.0))
    for at in loop.times(0.16, jitter=0.7):
        loop.put('scooters', scooter_pass(rng, dur=5), at, rng.uniform(0.6, 1.0))
    for at in loop.times(0.38, jitter=0.9):
        d = rng.uniform(0.35, 0.8)
        loop.put('horns', far(horn(rng, car=rng.random() < 0.3), d), at, 1 - 0.6 * d)
    loop.put('speaker', fade(loudspeaker(rng, 9.0), 1.0, 1.5), loop.seconds * 0.35)
    crowd(loop, 'crowd', 6)
    ir = reverb_ir(1.6, 1.1, rng, bright=0.4, early=[(0.05, 0.4), (0.11, 0.25)])
    return loop.mix(ir, 0.5)


def tet_eve():
    loop = Loop(22.4, seed=909)  # 14 ô nhịp trống lân ở 150 nhịp/phút
    rng = loop.rng
    loop.layer('hum', -41, 'bed')
    loop.layer('crowd', -29, send=0.5)
    loop.layer('drums', -21, send=0.5)
    loop.layer('fireworks', -19, send=0.7)
    loop.layer('cheer', -24, send=0.6)
    loop.layer('horns', -31, send=0.5)
    loop.bed('hum', loop.noise(brown(bp(30, 350))) * np.clip(1 + 0.3 * loop.slow(0.1), 0.3, None))
    crowd(loop, 'crowd', 18, f0=(110, 300))
    lion_dance(loop, 'drums')
    for at in loop.times(0.2, jitter=0.6):
        loop.put('fireworks', firework_far(rng), at, rng.uniform(0.6, 1.0))
    loop.put('cheer', cheer(rng), loop.seconds * 0.71)
    for at in loop.times(0.15):
        loop.put('horns', far(horn(rng), 0.7), at)
    ir = reverb_ir(2.0, 1.4, rng, bright=0.35, early=[(0.08, 0.35), (0.17, 0.2)])
    return loop.mix(ir, 0.6)


# Độ to nghe được (dBFS, trọng số K) của từng cảnh: đêm khẽ hơn ngày một chút.
SCENES = {
    'amb_delta_day': (delta_day, -22),
    'amb_delta_night': (delta_night, -23),
    'amb_coast_day': (coast_day, -22),
    'amb_coast_night': (coast_night, -23),
    'amb_mountain_day': (mountain_day, -22),
    'amb_mountain_night': (mountain_night, -23),
    'amb_mekong_day': (mekong_day, -22),
    'amb_city': (city, -22),
    'amb_tet_eve': (tet_eve, -22),
}


if __name__ == '__main__':
    import sys

    only = set(sys.argv[1:])
    for name, (build, level) in SCENES.items():
        if only and name not in only:
            continue
        write(name, build(), level)
