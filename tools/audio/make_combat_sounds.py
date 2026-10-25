"""COMBAT-01 combat sounds: original, procedurally synthesised recordings-in-spirit, written as WAV files.

Run (no third-party modules):  python tools/audio/make_combat_sounds.py
Writes assets/audio/combat/*.wav (44.1 kHz, 16 bit, mono). Deterministic: the same seeds give the same files.
License: original work of the project (no third-party material), free to use and change like the rest of the repo.

Each sound is built from the parts a listener separates in a real firefight:
  report_<weapon>_<n>   close report: muzzle blast (broadband impulse + low thump), the action cycling (metallic clack),
                        ground slap, outdoor reflections (tree line / terrain echoes) and a diffuse decaying tail
  far_<light|heavy>_<n> the same weapon from far away: high frequencies lost to the air, a soft "pop" and a long roll
  crack_<n>             a supersonic round passing close: an N-wave (sharp double edge) with a short ringing tail
  whiz_<n>              a round passing very close / spent: a short falling band of noise
  impact_<material>_<n> dirt, wood, metal, stone, flesh
  boom_close, boom_far  an explosion near and far
"""
import math
import os
import random
import struct
import wave

RATE = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "audio", "combat")


# --- small DSP on lists of floats ---------------------------------------------------------------------------------

def zeros(sec):
    return [0.0] * int(RATE * sec)


def noise(n, rng):
    return [rng.uniform(-1.0, 1.0) for _ in range(n)]


def lowpass(x, fc):
    a = math.exp(-2.0 * math.pi * fc / RATE)
    y, s = [], 0.0
    for v in x:
        s = (1.0 - a) * v + a * s
        y.append(s)
    return y


def highpass(x, fc):
    lp = lowpass(x, fc)
    return [a - b for a, b in zip(x, lp)]


def lowpass2(x, fc, q=0.707):
    """RBJ 2nd-order low-pass (12 dB / octave)."""
    w = 2.0 * math.pi * fc / RATE
    alpha = math.sin(w) / (2.0 * q)
    c = math.cos(w)
    b0, b1, b2 = (1 - c) / 2, 1 - c, (1 - c) / 2
    a0, a1, a2 = 1 + alpha, -2 * c, 1 - alpha
    y = []
    x1 = x2 = y1 = y2 = 0.0
    for v in x:
        o = (b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0
        x2, x1, y2, y1 = x1, v, y1, o
        y.append(o)
    return y


def bandpass(x, f0, q):
    """RBJ band-pass (constant 0 dB peak)."""
    w = 2.0 * math.pi * f0 / RATE
    alpha = math.sin(w) / (2.0 * q)
    b0, b1, b2 = alpha, 0.0, -alpha
    a0, a1, a2 = 1.0 + alpha, -2.0 * math.cos(w), 1.0 - alpha
    y = []
    x1 = x2 = y1 = y2 = 0.0
    for v in x:
        o = (b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0
        x2, x1, y2, y1 = x1, v, y1, o
        y.append(o)
    return y


def env_exp(n, tau, attack=0.0005):
    na = max(1, int(attack * RATE))
    return [min(1.0, i / na) * math.exp(-max(0, i - na) / (tau * RATE)) for i in range(n)]


def mix_into(dst, src, at=0.0, gain=1.0):
    o = int(at * RATE)
    for i, v in enumerate(src):
        j = o + i
        if j >= len(dst):
            break
        dst[j] += v * gain


def mul(a, b):
    return [x * y for x, y in zip(a, b)]


def tone(n, f, tau, phase=0.0, sweep=0.0):
    return [math.sin(2 * math.pi * (f + sweep * i / RATE) * i / RATE + phase) * math.exp(-i / (tau * RATE)) for i in range(n)]


def reverb(x, size=1.0, decay=0.6, rng=None):
    """Schroeder reverb: four combs and two all-passes; an outdoor diffuse tail when lowpassed after."""
    combs = [int(d * size) for d in (1557, 1617, 1491, 1422)]
    out = [0.0] * len(x)
    for d in combs:
        buf = [0.0] * d
        k = 0
        g = decay ** (d / 1500.0)
        for i, v in enumerate(x):
            y = buf[k]
            buf[k] = v + y * g
            out[i] += y
            k = (k + 1) % d
    for d, g in ((225, 0.5), (556, 0.5)):
        buf = [0.0] * d
        k = 0
        for i, v in enumerate(out):
            b = buf[k]
            y = -v * g + b
            buf[k] = v + b * g
            out[i] = y
            k = (k + 1) % d
    return [v * 0.25 for v in out]


def normalize(x, peak=0.89):
    m = max(1e-9, max(abs(v) for v in x))
    return [v * peak / m for v in x]


def fade_out(x, sec=0.05):
    n = int(sec * RATE)
    for i in range(min(n, len(x))):
        x[-1 - i] *= i / n
    return x


def write(name, x):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".wav")
    x = fade_out(normalize(x))
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32000)) for v in x))
    print("wrote", os.path.relpath(path), "%.2f s" % (len(x) / RATE))


# --- the sounds ---------------------------------------------------------------------------------------------------

WEAPONS = {
    # name: (thump Hz, blast decay s, thump decay s, brightness Hz, mech delay s, mech level, tail s, echo level)
    "rifle": (95.0, 0.010, 0.045, 3200.0, 0.030, 0.22, 1.1, 0.30),
    "dmr": (72.0, 0.016, 0.070, 2400.0, 0.040, 0.18, 1.5, 0.38),
    "lmg": (88.0, 0.012, 0.050, 2900.0, 0.028, 0.26, 1.1, 0.30),
    "gpmg": (66.0, 0.018, 0.075, 2200.0, 0.032, 0.24, 1.4, 0.36),
}


def report(kind, seed):
    rng = random.Random(seed)
    f_th, blast_tau, th_tau, bright, mech_at, mech_lvl, tail_s, echo = WEAPONS[kind]
    n = int(RATE * (tail_s + 0.3))
    out = [0.0] * n
    # Muzzle blast: a 1-2 ms broadband edge, then a bright decaying burst.
    nb = int(RATE * 0.12)
    burst = noise(nb, rng)
    bright_b = bandpass(burst, bright * rng.uniform(0.9, 1.1), 0.7)
    low_b = lowpass(burst, 900.0)
    e = env_exp(nb, blast_tau, 0.0002)
    mix_into(out, mul(bright_b, e), 0.0, 2.2)
    mix_into(out, mul(low_b, e), 0.0, 1.2)
    # Pressure thump (the body of the report).
    mix_into(out, tone(int(RATE * 0.3), f_th * rng.uniform(0.95, 1.05), th_tau, sweep=-f_th * 0.5), 0.0, 0.9)
    # Ground slap ~4 ms later, duller.
    mix_into(out, mul(lowpass(noise(nb, rng), 1800.0), env_exp(nb, blast_tau * 1.3)), 0.004, 0.55)
    # The action cycling: two short metallic clacks.
    for k, (f1, f2) in enumerate(((2300.0, 3700.0), (1900.0, 3100.0))):
        nm = int(RATE * 0.04)
        m = [0.6 * a + 0.4 * b for a, b in zip(tone(nm, f1 * rng.uniform(0.95, 1.05), 0.006), tone(nm, f2, 0.004))]
        mix_into(out, mul(m, env_exp(nm, 0.008)), mech_at + k * 0.018, mech_lvl)
    # Outdoor reflections: a few discrete echoes from the tree line / terrain, lowpassed and quieter with distance.
    for d in (rng.uniform(0.09, 0.14), rng.uniform(0.22, 0.32), rng.uniform(0.38, 0.55)):
        mix_into(out, lowpass(mul(noise(nb, rng), env_exp(nb, 0.03)), 1400.0), d, echo * 0.6 * math.exp(-d * 2.0))
    # Diffuse tail.
    seed_tail = [0.0] * n
    mix_into(seed_tail, mul(noise(int(RATE * 0.05), rng), env_exp(int(RATE * 0.05), 0.01)), 0.0, 1.0)
    tail = lowpass2(reverb(seed_tail, size=1.0 + rng.uniform(-0.05, 0.05), decay=0.76), 1800.0)
    env_t = [math.exp(-i / (tail_s * 0.45 * RATE)) for i in range(n)]
    mix_into(out, mul(tail, env_t), 0.0, echo * 7.0)
    return out


def far(heavy, seed):
    rng = random.Random(seed)
    n = int(RATE * (2.2 if heavy else 1.8))
    out = [0.0] * n
    nb = int(RATE * 0.3)
    pop = lowpass2(lowpass2(noise(nb, rng), 420.0 if heavy else 600.0), 500.0 if heavy else 700.0)
    mix_into(out, mul(pop, env_exp(nb, 0.035 if heavy else 0.025, 0.002)), 0.0, 2.0)
    # what is left of the crack: a little 1-2 kHz snap on the front of the pop
    snap = lowpass2(bandpass(noise(nb, rng), 1300.0, 1.0), 2200.0)
    mix_into(out, mul(snap, env_exp(nb, 0.006, 0.001)), 0.0, 0.35)
    mix_into(out, tone(int(RATE * 0.6), 55.0 if heavy else 70.0, 0.12), 0.0, 0.5)
    # A long roll: echoes off distant terrain, smeared.
    seed_tail = [0.0] * n
    mix_into(seed_tail, mul(noise(int(RATE * 0.08), rng), env_exp(int(RATE * 0.08), 0.02)), 0.0, 1.0)
    roll = lowpass2(lowpass2(reverb(seed_tail, size=1.6, decay=0.8), 380.0), 380.0)
    mix_into(out, mul(roll, [math.exp(-i / (0.7 * RATE)) for i in range(n)]), 0.03, 3.0)
    return out


def crack(seed):
    rng = random.Random(seed)
    n = int(RATE * 0.35)
    out = [0.0] * n
    # N-wave: up to +1, a linear fall to -1 over ~0.35 ms, back to 0.
    w = int(RATE * rng.uniform(0.00030, 0.00045))
    o = 10
    for i in range(w):
        out[o + i] = 1.0 - 2.0 * i / w
    out[o + w] = -0.6
    # The sharp edges ring in the ear: high band-passed burst, then ground / near reflections.
    ring = bandpass(noise(int(RATE * 0.03), rng), 4500.0, 1.2)
    mix_into(out, mul(ring, env_exp(len(ring), 0.004)), 0.0005, 0.6)
    for d, g in ((rng.uniform(0.004, 0.009), 0.35), (rng.uniform(0.02, 0.05), 0.15)):
        mix_into(out, [v * g for v in out[: int(RATE * 0.004)]], d, 1.0)
    tail = lowpass(mul(noise(n, rng), env_exp(n, 0.05)), 2500.0)
    mix_into(out, tail, 0.002, 0.12)
    return out


def whiz(seed):
    """A short, tonal falling "zip": narrow bands of noise sliding down (the Doppler fall of a round going past)."""
    rng = random.Random(seed)
    n = int(RATE * 0.14)
    x = noise(n, rng)
    f0 = rng.uniform(2200.0, 2800.0)
    bands = [bandpass(x, f0 * r, 9.0) for r in (1.0, 0.75, 0.55, 0.42)]
    out = []
    for i in range(n):
        t = i / n
        pos = t * 3.0
        k = min(2, int(pos))
        fr = pos - k
        v = bands[k][i] * (1.0 - fr) + bands[k + 1][i] * fr
        a = math.sin(math.pi * min(1.0, t * 1.15)) ** 3
        out.append(v * a)
    return out


def impact(material, seed):
    rng = random.Random(seed)
    n = int(RATE * 0.5)
    out = [0.0] * n
    nb = int(RATE * 0.12)
    if material == "dirt":
        mix_into(out, mul(lowpass(noise(nb, rng), 900.0), env_exp(nb, 0.02)), 0.0, 1.0)
        mix_into(out, tone(int(RATE * 0.1), 110.0, 0.02), 0.0, 0.5)
        for k in range(6):   # debris patter
            mix_into(out, mul(bandpass(noise(400, rng), rng.uniform(1500, 3500), 2.0), env_exp(400, 0.002)), 0.02 + rng.uniform(0, 0.12), 0.25)
    elif material == "wood":
        mix_into(out, mul(bandpass(noise(nb, rng), 2500.0, 1.0), env_exp(nb, 0.004)), 0.0, 1.0)
        for f, g in ((340.0, 0.7), (560.0, 0.4), (910.0, 0.25)):
            mix_into(out, tone(int(RATE * 0.2), f * rng.uniform(0.9, 1.1), 0.035), 0.0, g)
    elif material == "metal":
        mix_into(out, mul(noise(400, rng), env_exp(400, 0.001)), 0.0, 0.8)
        for f, g, tau in ((1870.0, 0.6, 0.12), (3140.0, 0.4, 0.08), (4790.0, 0.3, 0.05), (6900.0, 0.2, 0.03)):
            mix_into(out, tone(int(RATE * 0.45), f * rng.uniform(0.95, 1.05), tau), 0.0, g)
    elif material == "stone":
        mix_into(out, mul(highpass(noise(nb, rng), 1500.0), env_exp(nb, 0.006)), 0.0, 1.0)
        mix_into(out, mul(lowpass(noise(nb, rng), 1200.0), env_exp(nb, 0.012)), 0.0, 0.5)
        for k in range(5):
            mix_into(out, mul(bandpass(noise(300, rng), rng.uniform(2500, 5000), 2.0), env_exp(300, 0.0015)), 0.01 + rng.uniform(0, 0.1), 0.3)
    else:  # flesh: a short dull thud
        mix_into(out, mul(lowpass(noise(nb, rng), 500.0), env_exp(nb, 0.012)), 0.0, 1.0)
        mix_into(out, tone(int(RATE * 0.08), 140.0, 0.015), 0.0, 0.6)
    return out


def boom(close, seed):
    rng = random.Random(seed)
    n = int(RATE * (2.4 if close else 3.0))
    out = [0.0] * n
    nb = int(RATE * 0.5)
    blast = noise(nb, rng)
    if close:
        mix_into(out, mul(blast, env_exp(nb, 0.012, 0.0003)), 0.0, 1.5)
    mix_into(out, mul(lowpass2(lowpass2(blast, 400.0 if close else 160.0), 600.0 if close else 220.0), env_exp(nb, 0.08)), 0.0, 3.0)
    mix_into(out, tone(int(RATE * 1.2), 42.0, 0.35, sweep=-15.0), 0.0, 1.2)
    seed_tail = [0.0] * n
    mix_into(seed_tail, mul(noise(int(RATE * 0.1), rng), env_exp(int(RATE * 0.1), 0.03)), 0.0, 1.0)
    roll = lowpass(reverb(seed_tail, size=1.8, decay=0.82), 500.0 if close else 250.0)
    mix_into(out, mul(roll, [math.exp(-i / (0.9 * RATE)) for i in range(n)]), 0.02, 4.0)
    if close:
        for k in range(14):  # falling debris
            mix_into(out, mul(bandpass(noise(500, rng), rng.uniform(800, 3000), 1.5), env_exp(500, 0.004)), rng.uniform(0.3, 1.6), 0.18)
    return out


def main():
    seed = 1000
    for kind in WEAPONS:
        for v in range(3):
            seed += 1
            write("report_%s_%d" % (kind, v), report(kind, seed))
    for heavy in (False, True):
        for v in range(3):
            seed += 1
            write("far_%s_%d" % ("heavy" if heavy else "light", v), far(heavy, seed))
    for v in range(4):
        seed += 1
        write("crack_%d" % v, crack(seed))
    for v in range(3):
        seed += 1
        write("whiz_%d" % v, whiz(seed))
    for m in ("dirt", "wood", "metal", "stone", "flesh"):
        for v in range(3):
            seed += 1
            write("impact_%s_%d" % (m, v), impact(m, seed))
    seed += 1
    write("boom_close", boom(True, seed))
    seed += 1
    write("boom_far", boom(False, seed))


if __name__ == "__main__":
    main()
