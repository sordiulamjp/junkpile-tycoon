"""Generate the Play Store feature graphic (1024x500) from existing in-repo art.

One-off asset generator for ALTA-286: composites assets/icon.png plus flat
gear/crystal shapes matching its palette. No screenshot/device frame is used
(Play policy forbids that on the feature graphic). Re-run after editing to
regenerate store/assets/feature-graphic-1024x500.png.
"""
import math

from PIL import Image, ImageDraw, ImageFont

W, H = 1024, 500
BG_TOP = (26, 21, 18)
BG_BOTTOM = (58, 44, 34)
ROCK = (122, 99, 79)
GEAR = (94, 99, 107)
CYAN = (139, 224, 226)
YELLOW = (240, 190, 60)
ORANGE = (204, 107, 45)

img = Image.new("RGB", (W, H), BG_TOP)
draw = ImageDraw.Draw(img)

for y in range(H):
    t = y / H
    r = int(BG_TOP[0] + (BG_BOTTOM[0] - BG_TOP[0]) * t)
    g = int(BG_TOP[1] + (BG_BOTTOM[1] - BG_TOP[1]) * t)
    b = int(BG_TOP[2] + (BG_BOTTOM[2] - BG_TOP[2]) * t)
    draw.line([(0, y), (W, y)], fill=(r, g, b))


def gear(cx, cy, r_outer, r_inner, teeth, color, rot=0.0):
    pts = []
    n = teeth * 2
    for i in range(n):
        a = rot + i * math.pi / teeth
        r = r_outer if i % 2 == 0 else r_inner
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    draw.polygon(pts, fill=color)
    draw.ellipse([cx - r_inner * 0.55, cy - r_inner * 0.55, cx + r_inner * 0.55, cy + r_inner * 0.55], fill=BG_TOP)


gear(900, 90, 95, 78, 9, GEAR, rot=0.2)
gear(970, 430, 60, 48, 9, GEAR, rot=0.6)

pile_base_y = 430
draw.polygon([(560, pile_base_y), (760, 230), (960, pile_base_y)], fill=ROCK)
draw.polygon([(560, pile_base_y), (760, 230), (660, pile_base_y)], fill=(102, 82, 65))


def crystal(cx, top_y, half_w, height, color):
    draw.polygon(
        [(cx, top_y), (cx - half_w, top_y + height), (cx + half_w, top_y + height)],
        fill=color,
    )


crystal(650, 330, 30, 60, YELLOW)
crystal(760, 260, 34, 90, CYAN)
crystal(870, 340, 26, 55, ORANGE)

icon = Image.open("assets/icon.png").convert("RGBA")
icon_size = 380
icon = icon.resize((icon_size, icon_size), Image.LANCZOS)
img.paste(icon, (40, (H - icon_size) // 2), icon)

title = "JUNKPILE TYCOON"
max_title_w = W - 40 - 430
title_size = 68
title_font = ImageFont.truetype("/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf", title_size)
while draw.textbbox((0, 0), title, font=title_font)[2] > max_title_w and title_size > 30:
    title_size -= 2
    title_font = ImageFont.truetype("/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf", title_size)

sub_font = ImageFont.truetype(
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Black.ttc", 34
)
tag_font = ImageFont.truetype(
    "/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf", 26
)

tx, ty = 430, 150
draw.text((tx + 3, ty + 3), title, font=title_font, fill=(0, 0, 0))
draw.text((tx, ty), title, font=title_font, fill=(250, 240, 225))

sub = "廢料礦場大亨・放置挖礦"
draw.text((tx + 2, ty + 92), sub, font=sub_font, fill=(0, 0, 0))
draw.text((tx, ty + 90), sub, font=sub_font, fill=YELLOW)

tag = "IDLE MINING TYCOON"
draw.text((tx, ty + 150), tag, font=tag_font, fill=(200, 190, 180))

img.save("store/assets/feature-graphic-1024x500.png")
print("saved", img.size, img.mode)
