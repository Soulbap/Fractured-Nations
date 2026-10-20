"""Vectorized gradient noise for the reference terrain generator (numpy only).

Deterministic for a given seed: the permutation table comes from numpy's PCG64 seeded
with the integer seed, so the same layout file always produces the same terrain.
"""
import numpy as np

_GRAD = np.array([(np.cos(a), np.sin(a)) for a in np.linspace(0, 2 * np.pi, 16, endpoint=False)], dtype=np.float32)
_PERMS = {}


def _perm(seed):
    p = _PERMS.get(seed)
    if p is None:
        rng = np.random.Generator(np.random.PCG64(seed))
        base = rng.permutation(256).astype(np.int32)
        p = np.concatenate([base, base])
        _PERMS[seed] = p
    return p


def _fade(t):
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


def perlin(x, y, seed=0):
    """2D gradient noise, roughly in [-1, 1]. x, y are float arrays in noise units."""
    p = _perm(seed)
    xf0 = np.floor(x)
    yf0 = np.floor(y)
    xi = xf0.astype(np.int64) & 255
    yi = yf0.astype(np.int64) & 255
    fx = (x - xf0).astype(np.float32)
    fy = (y - yf0).astype(np.float32)
    u = _fade(fx)
    v = _fade(fy)
    xi1 = (xi + 1) & 255
    yi1 = (yi + 1) & 255
    px0 = p[xi]
    px1 = p[xi1]

    def g(hx, yy, dx, dy):
        h = p[hx + yy] & 15
        gr = _GRAD[h]
        return gr[..., 0] * dx + gr[..., 1] * dy

    n00 = g(px0, yi, fx, fy)
    n10 = g(px1, yi, fx - 1.0, fy)
    n01 = g(px0, yi1, fx, fy - 1.0)
    n11 = g(px1, yi1, fx - 1.0, fy - 1.0)
    nx0 = n00 + u * (n10 - n00)
    nx1 = n01 + u * (n11 - n01)
    return (nx0 + v * (nx1 - nx0)) * 1.41


def fbm(x, y, seed, octaves=4, lacunarity=2.0, gain=0.5):
    """Fractal sum of perlin octaves, normalized to roughly [-1, 1]."""
    total = np.zeros(np.shape(x), dtype=np.float32)
    amp = 1.0
    norm = 0.0
    fx, fy = x, y
    for o in range(octaves):
        total += perlin(fx, fy, seed + o * 101) * amp
        norm += amp
        amp *= gain
        # Rotate each octave a little so lattice artifacts do not line up.
        fx, fy = (fx * 0.8 - fy * 0.6) * lacunarity, (fx * 0.6 + fy * 0.8) * lacunarity
    return total / norm


def ridged(x, y, seed, octaves=5, lacunarity=2.0, gain=0.5):
    """Ridged multifractal in [0, 1]: sharp crests, rounded valleys."""
    total = np.zeros(np.shape(x), dtype=np.float32)
    amp = 1.0
    norm = 0.0
    weight = np.ones(np.shape(x), dtype=np.float32)
    fx, fy = x, y
    for o in range(octaves):
        n = 1.0 - np.abs(perlin(fx, fy, seed + o * 131))
        n = n * n * weight
        weight = np.clip(n * 1.6, 0.0, 1.0)
        total += n * amp
        norm += amp
        amp *= gain
        fx, fy = (fx * 0.8 - fy * 0.6) * lacunarity, (fx * 0.6 + fy * 0.8) * lacunarity
    return total / norm


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)
