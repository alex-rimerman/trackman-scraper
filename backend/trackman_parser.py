"""
Trackman PDF parser - uses color tags from PDF (same logic as trackman_pdf_parser).
Pitch type classification is based on colored dots next to pitch labels, NOT velocity.
"""

import math
import re
from collections import defaultdict
from pathlib import Path

import numpy as np
import pdfplumber


def _spin_axis_from_movement(ivb: float, hb: float) -> float:
    """Estimate spin axis from IVB and HB (same as PitchData.spinAxisFromMovement)."""
    if np.isnan(ivb) or np.isnan(hb):
        return 180.0
    normalized = math.degrees(math.atan2(hb, ivb))
    return (180.0 + normalized) % 360.0

# Pitch type names in Trackman PDF legend
PITCH_NAME_MAP = {
    "Fastball": "FF",
    "Sinker": "SI",
    "Splitter": "FS",
    "Cutter": "FC",
    "Slider": "SL",
    "Curveball": "CU",
    "ChangeUp": "CH",
    "Sweeper": "ST",
    "Knuckle Curve": "KC",
}


def _strip_units(value: str) -> str:
    return value.replace("mph", "").replace("RPM", "").replace("rpm", "").replace(",", "")


def _feet_inches_to_float(value: str) -> float:
    value = (value or "").strip().replace('"', "")
    if not value or value == "-":
        return float("nan")
    if "'" in value:
        try:
            feet, rest = value.split("'", 1)
            inches = rest.replace('"', "").strip() or "0"
            return float(feet) + float(inches) / 12.0
        except ValueError:
            return float("nan")
    try:
        return float(value)
    except ValueError:
        return float("nan")


def _parse_rel_side(value: str) -> float:
    raw = (value or "").strip()
    if not raw or raw == "-":
        return float("nan")
    val = _feet_inches_to_float(value)
    if np.isnan(val):
        return float("nan")
    if "'" in raw:
        return val
    return val / 12.0


def _parse_float(value: str) -> float:
    value = (value or "").strip()
    if not value or value == "-":
        return float("nan")
    try:
        return float(_strip_units(value))
    except ValueError:
        return float("nan")


def _color_to_rgb(color_tuple):
    if not color_tuple:
        return None
    try:
        return tuple(int(round(c * 255)) for c in color_tuple)
    except (TypeError, ValueError):
        return None


def infer_pitcher_hand_from_release_side(pitches: list[dict]) -> str | None:
    """
    Infer pitcher hand from release_side (RelSide).
    Trackman convention: negative RelSide → LHP (glove / third-base side), positive → RHP.
    Uses the mean sign across all pitches with valid RelSide (works for a single pitch too).
    Returns 'L', 'R', or None if no release_side data or mean is exactly zero.
    """
    rel_sides = [
        float(p["release_side"])
        for p in pitches
        if p.get("release_side") is not None and not np.isnan(p["release_side"])
    ]
    if not rel_sides:
        return None
    avg = float(np.mean(rel_sides))
    if avg < 0:
        return "L"
    if avg > 0:
        return "R"
    return None


def parse_pitcher_hand_from_pdf(pdf_path: str | Path, pitches: list[dict] | None = None) -> str:
    """
    Infer pitcher hand (L/R). Tries in order:
    1. Release side (mean RelSide < 0 → LHP, > 0 → RHP)
    2. PDF text (LHP, LEFT, RHP, RIGHT on first page)
    Default 'R'.
    """
    if pitches:
        hand = infer_pitcher_hand_from_release_side(pitches)
        if hand:
            return hand
    with pdfplumber.open(pdf_path) as pdf:
        if not pdf.pages:
            return "R"
        text = (pdf.pages[0].extract_text() or "").upper()
        has_left = "LHP" in text or " LEFT" in text or "LEFT " in text or text.startswith("LEFT")
        has_right = "RHP" in text or " RIGHT" in text or "RIGHT " in text or text.startswith("RIGHT")
        if has_left and not has_right:
            return "L"
        return "R"


def parse_trackman_pdf(pdf_path: str | Path) -> list[dict]:
    """
    Parse Trackman PDF and return list of pitches with TaggedPitchType from color matching.
    Each pitch dict: pitch_type (code), pitch_speed, induced_vert_break, horz_break,
    release_height, release_side, extension_ft, total_spin, efficiency, stuff_plus, stuff_plus_raw.
    """
    pitch_line_re = re.compile(
        r"#(?P<no>\d+)\s+"
        r"(?P<velo>-?\d+(?:\.\d+)?)\s+"
        r"(?P<spin>-|\d+(?:\.\d+)?)\s+"
        r"(?P<tilt>-|\d+:\d+)\s+"
        r"(?P<ivb>-|-?\d+(?:\.\d+)?)\s+"
        r"(?P<hb>-|-?\d+(?:\.\d+)?)\s+"
        r"(?P<ext>-|[\d'\"]+)\s+"
        r"(?P<relh>-|-?[\d'\"]+)\s+"
        r"(?P<rels>-|-?[\d'\"]+)\s+"
        r"(?P<spin_eff>-|\d+(?:\.\d+)?%?)"
    )
    pitch_line_start_re = re.compile(r"#\s*(?P<no>\d+)\s+")

    def _parse_page_text(page, pitch_rows):
        text = page.extract_text() or ""
        for raw_line in text.splitlines():
            line = raw_line.strip()
            if not line:
                continue
            match = pitch_line_re.search(line)
            if match:
                g = match.groupdict()
                pitch_rows.append({
                    "PitchNo": int(g["no"]),
                    "Page": page.page_number,
                    "RelSpeed": _parse_float(g["velo"]),
                    "SpinRate": _parse_float(g["spin"]),
                    "Tilt": g["tilt"],
                    "InducedVertBreak": _parse_float(g["ivb"]),
                    "HorzBreak": _parse_float(g["hb"]),
                    "Extension": _feet_inches_to_float(g["ext"]),
                    "RelHeight": _feet_inches_to_float(g["relh"]),
                    "RelSide": _parse_rel_side(g["rels"]),
                    "SpinEfficiency": (
                        _parse_float(g["spin_eff"].replace("%", "")) if g.get("spin_eff") and g["spin_eff"] != "-"
                        else float("nan")
                    ),
                })
                continue
            start = pitch_line_start_re.match(line)
            if start:
                toks = line.split()
                if len(toks) >= 10:
                    try:
                        pitch_no = int(toks[0].lstrip("#")) if toks[0].startswith("#") else int(toks[1])
                        base = 1 if toks[0].startswith("#") else 2
                        spin_eff_str = toks[base + 8] if len(toks) > base + 8 else "-"
                        pitch_rows.append({
                            "PitchNo": pitch_no,
                            "Page": page.page_number,
                            "RelSpeed": _parse_float(toks[base]),
                            "SpinRate": _parse_float(toks[base + 1]) if len(toks) > base + 1 else float("nan"),
                            "Tilt": toks[base + 2] if len(toks) > base + 2 and ":" in str(toks[base + 2]) else "-",
                            "InducedVertBreak": _parse_float(toks[base + 3]) if len(toks) > base + 3 else float("nan"),
                            "HorzBreak": _parse_float(toks[base + 4]) if len(toks) > base + 4 else float("nan"),
                            "Extension": _feet_inches_to_float(toks[base + 5]) if len(toks) > base + 5 else float("nan"),
                            "RelHeight": _feet_inches_to_float(toks[base + 6]) if len(toks) > base + 6 else float("nan"),
                            "RelSide": _parse_rel_side(toks[base + 7]) if len(toks) > base + 7 else float("nan"),
                            "SpinEfficiency": (
                                _parse_float(spin_eff_str.replace("%", "").strip())
                                if spin_eff_str and spin_eff_str != "-" else float("nan")
                            ),
                        })
                    except (ValueError, IndexError):
                        pass

    pitch_rows = []
    with pdfplumber.open(pdf_path) as pdf:
        pages = list(pdf.pages)
        if not pages:
            raise ValueError("PDF has no pages")

        # Legend: map colors to pitch names (from page 1)
        legend_colors = {}
        legend_words = pages[0].extract_words() or []
        legend_targets = {
            w["text"]: ((w["x0"] + w["x1"]) / 2, (w["top"] + w["bottom"]) / 2)
            for w in legend_words
            if w["text"] in PITCH_NAME_MAP
        }
        objs = getattr(pages[0], "objects", None)
        curve_objects = (objs.get("curve", []) if isinstance(objs, dict) else [])
        legend_dots = []
        for curve in curve_objects:
            if not curve.get("fill"):
                continue
            color = _color_to_rgb(curve.get("non_stroking_color"))
            if color is None:
                continue
            center = ((curve["x0"] + curve["x1"]) / 2, (curve["top"] + curve["bottom"]) / 2)
            legend_dots.append((center, color))

        for pitch_name, target_center in legend_targets.items():
            best_color = None
            best_dist = float("inf")
            for center, color in legend_dots:
                dist = abs(center[0] - target_center[0]) + abs(center[1] - target_center[1])
                if dist < best_dist:
                    best_color = color
                    best_dist = dist
            if best_color is not None:
                legend_colors[best_color] = pitch_name

        # Extract pitch rows from text
        for page in pages:
            _parse_page_text(page, pitch_rows)

        # Fallback: column-order parse
        if not pitch_rows:
            for page in pages:
                text = page.extract_text() or ""
                for raw_line in text.splitlines():
                    line = raw_line.strip()
                    start = pitch_line_start_re.match(line)
                    if not start or len(line.split()) < 10:
                        continue
                    toks = line.split()
                    try:
                        pitch_no = int(toks[0].lstrip("#")) if toks[0].startswith("#") else int(toks[1])
                        base = 1 if toks[0].startswith("#") else 2
                        pitch_rows.append({
                            "PitchNo": pitch_no,
                            "Page": page.page_number,
                            "RelSpeed": _parse_float(toks[base]),
                            "SpinRate": _parse_float(toks[base + 1]) if len(toks) > base + 1 else float("nan"),
                            "Tilt": toks[base + 2] if len(toks) > base + 2 and ":" in str(toks[base + 2]) else "-",
                            "InducedVertBreak": _parse_float(toks[base + 3]) if len(toks) > base + 3 else float("nan"),
                            "HorzBreak": _parse_float(toks[base + 4]) if len(toks) > base + 4 else float("nan"),
                            "Extension": _feet_inches_to_float(toks[base + 5]) if len(toks) > base + 5 else float("nan"),
                            "RelHeight": _feet_inches_to_float(toks[base + 6]) if len(toks) > base + 6 else float("nan"),
                            "RelSide": _parse_rel_side(toks[base + 7]) if len(toks) > base + 7 else float("nan"),
                            "SpinEfficiency": float("nan"),
                        })
                    except (ValueError, IndexError):
                        pass

        if not pitch_rows:
            raise ValueError("Could not extract pitch-by-pitch data from PDF")

        # Map pitch numbers to y positions
        pitch_y_positions = {}
        for page in pages:
            for word in (page.extract_words() or []):
                text = word["text"]
                if text.startswith("#") and text[1:].isdigit():
                    pitch_no = int(text[1:])
                    y_center = (word["top"] + word["bottom"]) / 2
                    pitch_y_positions[pitch_no] = (page.page_number, y_center)

        # Collect colored dots (x < 40 = left-side dots)
        pitch_color = {}
        for page in pages:
            objs = getattr(page, "objects", None) or {}
            curves = [c for c in objs.get("curve", []) if c.get("fill")]
            dots_by_y = defaultdict(list)
            for curve in curves:
                if curve.get("x1", 0) > 40:
                    continue
                color = _color_to_rgb(curve.get("non_stroking_color"))
                if color is None:
                    continue
                y_center = (curve["top"] + curve["bottom"]) / 2
                dots_by_y[round(y_center, 1)].append(color)

            dot_candidates = []
            for y, colors in dots_by_y.items():
                averaged = tuple(int(round(np.mean([c[i] for c in colors]))) for i in range(3))
                dot_candidates.append((y, averaged))
            dot_candidates.sort(key=lambda x: x[0])

            page_pitches = sorted(
                [(no, y) for no, (pno, y) in pitch_y_positions.items() if pno == page.page_number],
                key=lambda x: x[1],
            )
            for (pitch_no, _), (_, color) in zip(page_pitches, dot_candidates):
                pitch_color[pitch_no] = color

        def _match_pitch_type(color_rgb):
            if not color_rgb or not legend_colors:
                return None
            arr = np.array(color_rgb)
            best_pitch = None
            best_dist = float("inf")
            for legend_color, pitch in legend_colors.items():
                dist = float(np.linalg.norm(arr - np.array(legend_color)))
                if dist < best_dist:
                    best_dist = dist
                    best_pitch = pitch
            if best_pitch and best_dist <= 40:
                return best_pitch
            return None

        # Build result with pitch_type from color (not velocity). Skip Unknown/Undefined.
        result = []
        for row in pitch_rows:
            tagged = _match_pitch_type(pitch_color.get(row["PitchNo"]))
            if not tagged or tagged not in PITCH_NAME_MAP:
                continue
            pitch_type_code = PITCH_NAME_MAP[tagged]
            rel_speed = row["RelSpeed"]
            ivb = row["InducedVertBreak"]
            hb = row["HorzBreak"]
            ext = row["Extension"]
            relh = row["RelHeight"]
            rels = row["RelSide"]
            spin = row["SpinRate"]
            eff = row["SpinEfficiency"]

            ivb_f = float(ivb) if not np.isnan(ivb) else None
            hb_f = float(hb) if not np.isnan(hb) else None
            result.append({
                "pitch_type": pitch_type_code,
                "pitch_speed": float(rel_speed) if not np.isnan(rel_speed) else None,
                "induced_vert_break": ivb_f,
                "horz_break": hb_f,
                "release_height": float(relh) if not np.isnan(relh) else None,
                "release_side": float(rels) if not np.isnan(rels) else None,
                "extension_ft": float(ext) if not np.isnan(ext) else None,
                "total_spin": float(spin) if not np.isnan(spin) else None,
                "efficiency": float(eff) if not np.isnan(eff) else None,
                "spin_axis": _spin_axis_from_movement(ivb, hb) if ivb_f is not None and hb_f is not None else None,
                "tilt_string": row.get("Tilt") if row.get("Tilt") and row.get("Tilt") != "-" else None,
            })
        return result
