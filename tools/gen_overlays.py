#!/usr/bin/env python3
import os
from PIL import Image, ImageDraw, ImageFont


def find_font():
    candidates = [
        "/Library/Fonts/Arial.ttf",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/SFNSDisplay.ttf",
        "/System/Library/Fonts/SFNSRounded.ttf",
    ]
    for p in candidates:
        if os.path.exists(p):
            return p
    return None


def wrap_text(draw, text, font, max_width):
    words = text.split()
    lines = []
    cur = []
    for w in words:
        test = (" ".join(cur + [w])).strip()
        w_px, _ = draw.textbbox((0, 0), test, font=font)[2:]
        if w_px <= max_width or not cur:
            cur.append(w)
        else:
            lines.append(" ".join(cur))
            cur = [w]
    if cur:
        lines.append(" ".join(cur))
    return lines


def draw_centered_text(draw, box, lines, font, fill=(255, 255, 255, 255), line_spacing=1.2, stroke=2):
    line_heights = [draw.textbbox((0, 0), ln, font=font)[3] for ln in lines]
    h = sum(line_heights) + int((len(lines) - 1) * (line_heights[0] if line_heights else 0) * (line_spacing - 1))
    x0, y0, x1, y1 = box
    y = y0 + (y1 - y0 - h) // 2
    for i, ln in enumerate(lines):
        w = draw.textbbox((0, 0), ln, font=font)[2]
        x = x0 + (x1 - x0 - w) // 2
        draw.text((x, y), ln, font=font, fill=fill, stroke_width=stroke, stroke_fill=(0, 0, 0, 180))
        y += int(line_heights[i] * line_spacing)


def rounded_rect(draw, xy, radius, fill):
    x0, y0, x1, y1 = xy
    draw.rounded_rectangle(xy, radius=radius, fill=fill)


def make_title(path):
    W, H = 1920, 320
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    font_path = find_font()
    font = ImageFont.truetype(font_path, 72) if font_path else ImageFont.load_default()
    text = "MicroRaceDriver — Built and Shipped with AI (Zero‑Code)"
    lines = wrap_text(draw, text, font, int(W * 0.9))
    draw_centered_text(draw, (0, 0, W, H), lines, font)
    img.save(path)


def make_lower_third(path):
    W, H = 1600, 200
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    rounded_rect(draw, (0, 0, W, H), radius=28, fill=(0, 0, 0, 150))
    font_path = find_font()
    font = ImageFont.truetype(font_path, 64) if font_path else ImageFont.load_default()
    text = "John Doktor • Zero‑Code Devlog"
    w = draw.textbbox((0, 0), text, font=font)[2]
    x = (W - w) // 2
    y = (H - draw.textbbox((0, 0), text, font=font)[3]) // 2
    draw.text((x, y), text, font=font, fill=(255, 255, 255, 255), stroke_width=2, stroke_fill=(0, 0, 0, 180))
    img.save(path)


def make_end_card(path):
    W, H = 1920, 1080
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    # Semi-transparent backdrop bar
    rounded_rect(draw, (int(W * 0.08), int(H * 0.38), int(W * 0.92), int(H * 0.62)), radius=40, fill=(0, 0, 0, 170))
    font_path = find_font()
    title_font = ImageFont.truetype(font_path, 80) if font_path else ImageFont.load_default()
    sub_font = ImageFont.truetype(font_path, 52) if font_path else ImageFont.load_default()
    title = "Read the full case study"
    subtitle = "Link in description"
    # Title
    tw = draw.textbbox((0, 0), title, font=title_font)[2]
    tx = (W - tw) // 2
    ty = int(H * 0.44) - draw.textbbox((0, 0), title, font=title_font)[3] // 2
    draw.text((tx, ty), title, font=title_font, fill=(255, 255, 255, 255), stroke_width=2, stroke_fill=(0, 0, 0, 180))
    # Subtitle
    sw = draw.textbbox((0, 0), subtitle, font=sub_font)[2]
    sx = (W - sw) // 2
    sy = int(H * 0.54) - draw.textbbox((0, 0), subtitle, font=sub_font)[3] // 2
    draw.text((sx, sy), subtitle, font=sub_font, fill=(200, 230, 255, 255), stroke_width=2, stroke_fill=(0, 0, 0, 160))
    img.save(path)


def main():
    out_dir = os.path.join("docs", "overlays")
    os.makedirs(out_dir, exist_ok=True)
    make_title(os.path.join(out_dir, "title.png"))
    make_lower_third(os.path.join(out_dir, "lower_third.png"))
    make_end_card(os.path.join(out_dir, "end_card.png"))
    print(f"Exported overlays to {out_dir}")


if __name__ == "__main__":
    main()
