#!/usr/bin/env python3
"""LumaBounce ozgun ses efekti ureteci.

Tum sesler burada sifirdan sentezlenir - hicbir harici/telifli kaynak
kullanilmaz. Cikti: assets/audio/sfx/*.wav (mono, 44.1 kHz, 16-bit PCM).

Ses yonu:
  - modern, yumusak, minimal; camgobegi neon gorsel dile uyacak "camimsi" tini
  - inharmonik can partial'lari (her biri farkli hizda soner) -> cam/kristal his
  - keskin transient yok, 8-bit kare dalga yok, agir bas ve yanki yok
  - 180 Hz altindaki gurultu kesilir; enerji telefon hoparlorunun net
    bastigi 500 Hz - 5 kHz bandinda toplanir

Yeniden uretmek icin:
    Windows:        py -3 tools/generate_sfx.py
    Linux / macOS:  python3 tools/generate_sfx.py

Yalnizca standart kutuphane kullanir (math, random, struct, wave) - kurulum
gerekmez. Ciktilar deterministiktir (sabit RNG tohumu), tekrar calistirmak
birebir ayni dosyalari uretir.
"""

from __future__ import annotations

import math
import os
import random
import struct
import wave

SAMPLE_RATE = 44100
BIT_DEPTH = 16
OUTPUT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "assets", "audio", "sfx",
)

# Tum seslere uygulanan alt kesim: telefon hoparlorunde duyulmayan ama
# limiter'i mesgul eden sub-bas enerjisini atar.
GLOBAL_HIGHPASS_HZ = 180.0

# Inharmonik can oranlari -> "camimsi" tini. Yuksek partial'lar hizli soner.
BELL_PARTIALS = ((1.00, 1.00), (2.76, 0.42), (5.40, 0.18), (8.93, 0.08))
# Daha harmonik, daha yumusak/sicak; basarisizlik gibi nazik sesler icin.
SOFT_PARTIALS = ((1.00, 1.00), (2.00, 0.26), (3.00, 0.10))

Signal = list[float]


# --- Temel yardimcilar --------------------------------------------------------

def _samples(duration: float) -> int:
    return max(1, int(round(duration * SAMPLE_RATE)))


def silence(duration: float) -> Signal:
    return [0.0] * _samples(duration)


def glass(freq: float, duration: float, decay: float = 8.0,
          attack: float = 0.004, partials=BELL_PARTIALS) -> Signal:
    """Inharmonik partial yiginindan camimsi bir ton."""
    n = _samples(duration)
    out = [0.0] * n
    for ratio, amp in partials:
        f = freq * ratio
        if f >= SAMPLE_RATE * 0.45:
            continue
        # Yuksek partial ne kadar tizse o kadar cabuk soner.
        rate = decay * (1.0 + 0.55 * (ratio - 1.0))
        step = 2.0 * math.pi * f / SAMPLE_RATE
        for i in range(n):
            out[i] += amp * math.exp(-rate * i / SAMPLE_RATE) * math.sin(step * i)
    return _apply_attack(out, attack)


def sweep(f0: float, f1: float, duration: float, curve: float = 1.0,
          decay: float = 6.0, attack: float = 0.005) -> Signal:
    """Yumusak frekans kaymasi (firlatma / restart hissi)."""
    n = _samples(duration)
    out = [0.0] * n
    phase = 0.0
    for i in range(n):
        x = i / max(1, n - 1)
        freq = f0 + (f1 - f0) * (x ** curve)
        phase += 2.0 * math.pi * freq / SAMPLE_RATE
        out[i] = math.sin(phase) * math.exp(-decay * i / SAMPLE_RATE)
    return _apply_attack(out, attack)


def noise_layer(duration: float, rng: random.Random, lowpass_hz: float,
                highpass_hz: float, decay: float, attack: float = 0.003) -> Signal:
    """Hava/nefes katmani: filtrelenmis, hizla sonen gurultu."""
    n = _samples(duration)
    raw = [rng.uniform(-1.0, 1.0) for _ in range(n)]
    shaped = highpass(lowpass(raw, lowpass_hz), highpass_hz)
    for i in range(n):
        shaped[i] *= math.exp(-decay * i / SAMPLE_RATE)
    return _apply_attack(shaped, attack)


def _apply_attack(buf: Signal, attack: float) -> Signal:
    """Yukselen kosinus atak: baslangicta click olusmasini engeller."""
    ramp = min(len(buf), max(1, _samples(attack)))
    for i in range(ramp):
        buf[i] *= 0.5 - 0.5 * math.cos(math.pi * i / ramp)
    return buf


def lowpass(buf: Signal, cutoff_hz: float) -> Signal:
    a = math.exp(-2.0 * math.pi * cutoff_hz / SAMPLE_RATE)
    out = [0.0] * len(buf)
    y = 0.0
    for i, x in enumerate(buf):
        y = (1.0 - a) * x + a * y
        out[i] = y
    return out


def highpass(buf: Signal, cutoff_hz: float) -> Signal:
    a = math.exp(-2.0 * math.pi * cutoff_hz / SAMPLE_RATE)
    out = [0.0] * len(buf)
    y = 0.0
    prev_x = 0.0
    for i, x in enumerate(buf):
        y = a * (y + x - prev_x)
        prev_x = x
        out[i] = y
    return out


def mix(*layers: tuple[Signal, float, float]) -> Signal:
    """(sinyal, kazanc, baslangic_saniyesi) katmanlarini toplar."""
    total = 0
    for buf, _gain, offset in layers:
        total = max(total, _samples(offset) + len(buf) if buf else 0)
    out = [0.0] * total
    for buf, gain, offset in layers:
        start = _samples(offset) if offset > 0.0 else 0
        for i, value in enumerate(buf):
            out[start + i] += value * gain
    return out


def fade(buf: Signal, fade_in: float = 0.003, fade_out: float = 0.02) -> Signal:
    """Iki uca da rampa uygular; son ornek tam olarak 0 olur."""
    n = len(buf)
    head = min(n, max(1, _samples(fade_in)))
    for i in range(head):
        buf[i] *= 0.5 - 0.5 * math.cos(math.pi * i / head)
    tail = min(n, max(1, _samples(fade_out)))
    for i in range(tail):
        buf[n - 1 - i] *= 0.5 - 0.5 * math.cos(math.pi * i / tail)
    buf[-1] = 0.0
    return buf


def normalize(buf: Signal, peak: float) -> Signal:
    """Hedef tepe degerine olcekler. peak < 1.0 -> clipping yok."""
    current = max((abs(v) for v in buf), default=0.0)
    if current <= 1e-9:
        return buf
    scale = peak / current
    return [v * scale for v in buf]


def write_wav(name: str, buf: Signal) -> str:
    path = os.path.join(OUTPUT_DIR, name)
    frames = bytearray()
    for value in buf:
        clamped = max(-1.0, min(1.0, value))
        frames += struct.pack("<h", int(round(clamped * 32767.0)))
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(BIT_DEPTH // 8)
        handle.setframerate(SAMPLE_RATE)
        handle.writeframes(bytes(frames))
    return path


def finish(name: str, buf: Signal, peak: float, fade_out: float = 0.02) -> str:
    buf = highpass(buf, GLOBAL_HIGHPASS_HZ)
    buf = fade(buf, fade_out=fade_out)
    buf = normalize(buf, peak)
    return write_wav(name, buf)


# --- Ses tarifleri ------------------------------------------------------------

def build_ui_click(rng: random.Random) -> Signal:
    """Cok kisa, alcak seviyeli tiz blip."""
    body = glass(2200.0, 0.05, decay=55.0, attack=0.002)
    tick = noise_layer(0.014, rng, lowpass_hz=6000.0, highpass_hz=1400.0, decay=260.0)
    return mix((body, 0.85, 0.0), (tick, 0.22, 0.0))


def build_launch(rng: random.Random) -> Signal:
    """Yukari kayan yumusak firlatma; nefes katmani hafif."""
    rise = sweep(300.0, 780.0, 0.20, curve=0.6, decay=7.0)
    body = glass(520.0, 0.18, decay=14.0, attack=0.006)
    air = noise_layer(0.20, rng, lowpass_hz=2400.0, highpass_hz=420.0, decay=11.0, attack=0.02)
    return mix((rise, 0.90, 0.0), (body, 0.35, 0.0), (air, 0.26, 0.0))


def build_bounce(freq: float, duration: float, decay: float,
                 tick_gain: float, rng: random.Random) -> Signal:
    body = glass(freq, duration, decay=decay, attack=0.0025)
    if tick_gain <= 0.0:
        return body
    tick = noise_layer(0.012, rng, lowpass_hz=7000.0, highpass_hz=1600.0, decay=300.0)
    return mix((body, 1.0, 0.0), (tick, tick_gain, 0.0))


def build_block_break(rng: random.Random) -> Signal:
    """Kirilabilir blogun kirilmasi: kisa seramik/cam parcalanmasi.

    Sekme sesleri TEK bir can tonudur; bu ses bilerek COKLU ve gurultuludur
    (art arda gelen dort detune parca + kuru bir cirpinti). Ayni ses
    ailesinde kalir ama sekmeyle karistirilamaz.
    """
    shards = mix(
        (glass(1480.0, 0.20, decay=26.0, attack=0.001), 1.00, 0.000),
        (glass(1180.0, 0.22, decay=22.0, attack=0.001), 0.70, 0.012),
        (glass(1870.0, 0.16, decay=34.0, attack=0.001), 0.45, 0.024),
        (glass(2360.0, 0.13, decay=42.0, attack=0.001), 0.28, 0.036),
    )
    grit = noise_layer(0.09, rng, lowpass_hz=8000.0, highpass_hz=1900.0, decay=48.0)
    return mix((shards, 1.0, 0.0), (grit, 0.34, 0.0))


def build_target_hit() -> Signal:
    """Parlak, tatmin edici cam cinlamasi (E6 + B6 - temiz beslik)."""
    low = glass(1318.5, 0.42, decay=9.0, attack=0.003)
    high = glass(1975.5, 0.42, decay=13.0, attack=0.003)
    return mix((low, 1.0, 0.0), (high, 0.45, 0.0))


def build_level_complete() -> Signal:
    """Kisa yukselen uclu: A5 - D6 - G6."""
    return mix(
        (glass(880.00, 0.55, decay=7.0), 0.85, 0.00),
        (glass(1174.66, 0.55, decay=7.0), 0.90, 0.12),
        (glass(1567.98, 0.60, decay=6.0), 1.00, 0.24),
    )


def build_failure() -> Signal:
    """Nazik inen ikili - cezalandirici degil, sadece 'olmadi' hissi."""
    first = glass(392.0, 0.28, decay=11.0, attack=0.008, partials=SOFT_PARTIALS)
    second = glass(311.1, 0.34, decay=9.0, attack=0.010, partials=SOFT_PARTIALS)
    return mix((first, 0.85, 0.0), (second, 1.0, 0.10))


def build_restart(rng: random.Random) -> Signal:
    """Kisa, notr bir 'sifirlandi' kabarmasi."""
    tone = sweep(420.0, 660.0, 0.16, curve=0.8, decay=12.0, attack=0.008)
    air = noise_layer(0.16, rng, lowpass_hz=3000.0, highpass_hz=600.0, decay=16.0, attack=0.03)
    return mix((tone, 0.80, 0.0), (air, 0.22, 0.0))


def build_splash_bounce() -> Signal:
    """Oynanis sekmesinden daha yuvarlak ve parildayan acilis sekmesi."""
    body = glass(700.0, 0.26, decay=15.0, attack=0.004)
    shimmer = glass(1400.0, 0.26, decay=20.0, attack=0.006)
    return mix((body, 1.0, 0.0), (shimmer, 0.30, 0.0))


def build_logo_reveal() -> Signal:
    """Yavas atakli, yumusak parilti - logo belirirken."""
    low = glass(660.0, 0.70, decay=3.5, attack=0.14, partials=SOFT_PARTIALS)
    high = glass(990.0, 0.70, decay=4.2, attack=0.18, partials=SOFT_PARTIALS)
    lift = sweep(880.0, 1320.0, 0.60, curve=1.4, decay=4.0, attack=0.20)
    return mix((low, 0.85, 0.0), (high, 0.55, 0.05), (lift, 0.30, 0.10))


# --- Giris noktasi ------------------------------------------------------------

def main() -> None:
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    rng = random.Random(20240517)  # sabit tohum -> tekrarlanabilir cikti

    written = [
        finish("ui_click.wav", build_ui_click(rng), peak=0.42, fade_out=0.008),
        finish("launch.wav", build_launch(rng), peak=0.72),
        finish("bounce_soft.wav", build_bounce(600.0, 0.11, 34.0, 0.0, rng), peak=0.50),
        finish("bounce_medium.wav", build_bounce(820.0, 0.13, 28.0, 0.16, rng), peak=0.60),
        finish("bounce_hard.wav", build_bounce(1100.0, 0.16, 22.0, 0.24, rng), peak=0.72),
        finish("target_hit.wav", build_target_hit(), peak=0.80, fade_out=0.04),
        finish("level_complete.wav", build_level_complete(), peak=0.80, fade_out=0.05),
        finish("failure.wav", build_failure(), peak=0.55, fade_out=0.05),
        finish("restart.wav", build_restart(rng), peak=0.50),
        finish("splash_bounce.wav", build_splash_bounce(), peak=0.68, fade_out=0.03),
        finish("logo_reveal.wav", build_logo_reveal(), peak=0.60, fade_out=0.06),
        # YENI SESLER LISTENIN SONUNA EKLENIR. rng tek bir akistir; araya
        # eklenen her rng'li tarif kendinden SONRAKI tum seslerin orneklerini
        # kaydirir ve degismemis dosyalari gereksiz yere yeniden yazardi.
        finish("block_break.wav", build_block_break(rng), peak=0.62, fade_out=0.03),
    ]

    for path in written:
        size_kb = os.path.getsize(path) / 1024.0
        print(f"{os.path.basename(path):<20} {size_kb:7.1f} KB")
    print(f"\n{len(written)} ses dosyasi uretildi -> {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
