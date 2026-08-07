"""GELISTIRME ARACI - oyuna dahil degildir.

Bir bant icindeki bolumlerin ICERIGINI zorluga gore yeniden dagitir; level_id
SLOTLARI (dosya adlari) hep sabit kalir - yalniz hangi bulmacanin hangi
slotta oturdugu degisir. Boylece STAR_GATES / kayitli ilerleme / dosya
sayisi asla bozulmaz (bkz. proje plani, Faz B).

Mekanizma: her .tres dosyasinin TAMAMI (level_id satiri haric) "govde"dir.
Iki slotu takas etmek = govdeleri degistirip her govdedeki level_id satirini
KENDI (degismeyen) hedef slot numarasina sabitlemek. Sub_resource id'leri
dosya-yerel oldugu icin (baska dosyaya referans vermez) bu tamamen guvenli.

Kullanim:
    python tools/resequence_levels.py --scores scratchpad/scores.txt --band 1 20 --apply
    (once --apply olmadan calistirip "PLAN" ciktisini gozden gecirin)

scores dosyasi score_levels.gd ciktisidir (LEVEL N robust=.. bounces=.. ... satirlari).
"""
import argparse
import re

LEVEL_RE = re.compile(
    r"^LEVEL (\d+) robust=(-?\d+) bounces=(-?\d+)")
LEVEL_ID_LINE_RE = re.compile(r"^level_id = \d+\s*$", re.MULTILINE)


def load_scores(path):
    scores = {}
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            m = LEVEL_RE.match(line.strip())
            if not m:
                continue
            level_id, robust, bounces = int(m.group(1)), int(m.group(2)), int(m.group(3))
            scores[level_id] = (robust, bounces)
    return scores


def difficulty_key(level_id, scores):
    robust, bounces = scores[level_id]
    # Kolay -> zor siralama: az sekme + cok saglam hucre once gelir.
    # bounces=-1 (hic isabet yok) veya 9999 (saglam degil) kasitli olarak
    # en sona itilir - bunlar zaten score_levels.gd'de ayri incelenmeli.
    effective_bounces = 999 if bounces < 0 else bounces
    return (effective_bounces, -robust)


def read_body(path):
    """Dosyanin tamamini okur, level_id satirini haric tutup geri dondurur."""
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    if not LEVEL_ID_LINE_RE.search(text):
        raise ValueError(f"{path}: level_id satiri bulunamadi")
    return text


def with_level_id(text, new_id):
    return LEVEL_ID_LINE_RE.sub(f"level_id = {new_id}", text, count=1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scores", required=True)
    ap.add_argument("--band", nargs=2, type=int, metavar=("LO", "HI"), required=True)
    ap.add_argument("--levels-dir", default="levels")
    ap.add_argument("--apply", action="store_true", help="Olmazsa sadece PLAN yazdirir.")
    args = ap.parse_args()

    lo, hi = args.band
    scores = load_scores(args.scores)
    ids = list(range(lo, hi + 1))
    missing = [i for i in ids if i not in scores]
    if missing:
        raise SystemExit(f"HATA: skor eksik: {missing}")

    sorted_ids = sorted(ids, key=lambda i: difficulty_key(i, scores))

    print(f"PLAN (bant {lo}-{hi}, kolay -> zor):")
    for slot, source_id in zip(ids, sorted_ids):
        robust, bounces = scores[source_id]
        marker = " (degismedi)" if slot == source_id else ""
        print(f"  slot {slot:3d} <- eski bolum {source_id:3d}  "
              f"(robust={robust}, bounces={bounces}){marker}")

    if not args.apply:
        print("\n(--apply verilmedi, dosyalar degistirilmedi)")
        return

    bodies = {i: read_body(f"{args.levels_dir}/level_{i:02d}.tres") for i in ids}
    for slot, source_id in zip(ids, sorted_ids):
        new_text = with_level_id(bodies[source_id], slot)
        with open(f"{args.levels_dir}/level_{slot:02d}.tres", "w", encoding="utf-8") as f:
            f.write(new_text)
    print(f"\n{len(ids)} dosya yeniden yazildi.")


if __name__ == "__main__":
    main()
