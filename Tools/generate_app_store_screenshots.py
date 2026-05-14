from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math
import textwrap

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "AppStore" / "iPad-13-Screenshots"
SRC = ROOT / "iPadServe" / "Resources" / "iPad Serve Guide" / "screenshots"
ICON = ROOT / "iPadServe" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "icon-1024.png"

W, H = 2732, 2048

COLORS = {
    "bg": (16, 20, 21),
    "surface": (29, 32, 34),
    "surface_hi": (39, 42, 44),
    "text": (224, 227, 229),
    "muted": (198, 198, 205),
    "quiet": (144, 144, 151),
    "secondary": (78, 222, 163),
    "primary": (190, 198, 224),
    "navy": (15, 23, 42),
}


def font(size, weight="regular"):
    candidates = {
        "regular": [
            "/System/Library/Fonts/SFNS.ttf",
            "/System/Library/Fonts/Helvetica.ttc",
            "/System/Library/Fonts/Avenir Next.ttc",
        ],
        "bold": [
            "/System/Library/Fonts/SFNS.ttf",
            "/System/Library/Fonts/Helvetica.ttc",
            "/System/Library/Fonts/Avenir Next.ttc",
        ],
        "mono": [
            "/System/Library/Fonts/SFNSMono.ttf",
            "/System/Library/Fonts/Menlo.ttc",
            "/System/Library/Fonts/Monaco.ttf",
        ],
    }[weight]
    for candidate in candidates:
        try:
            return ImageFont.truetype(candidate, size=size)
        except Exception:
            pass
    return ImageFont.load_default(size=size)


FONT_LABEL = font(30, "mono")
FONT_BODY = font(48, "regular")
FONT_BODY_SMALL = font(36, "regular")
FONT_TITLE = font(108, "bold")
FONT_TITLE_BIG = font(128, "bold")
FONT_CARD = font(56, "bold")
FONT_BRAND = font(46, "bold")


def rounded_mask(size, radius):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0], size[1]), radius=radius, fill=255)
    return mask


def paste_rounded(base, img, xy, radius):
    mask = rounded_mask(img.size, radius)
    base.paste(img, xy, mask)


def gradient_bg(accent=(78, 222, 163), warm=False):
    img = Image.new("RGB", (W, H), COLORS["bg"])
    px = img.load()
    for y in range(H):
        for x in range(W):
            nx, ny = x / W, y / H
            base = COLORS["bg"]
            t1 = max(0, 1 - math.hypot(nx - 0.92, ny - 0.18) / 0.95)
            t2 = max(0, 1 - math.hypot(nx - 0.12, ny - 0.92) / 0.86)
            gold = (217, 154, 40) if warm else COLORS["primary"]
            r = int(base[0] + accent[0] * t1 * 0.18 + gold[0] * t2 * 0.08)
            g = int(base[1] + accent[1] * t1 * 0.18 + gold[1] * t2 * 0.08)
            b = int(base[2] + accent[2] * t1 * 0.18 + gold[2] * t2 * 0.08)
            px[x, y] = (min(r, 255), min(g, 255), min(b, 255))
    return img


def draw_text(draw, text, xy, fnt, fill=COLORS["text"], width=18, line_gap=12):
    x, y = xy
    for line in textwrap.wrap(text, width=width):
        draw.text((x, y), line, font=fnt, fill=fill)
        bbox = draw.textbbox((x, y), line, font=fnt)
        y += (bbox[3] - bbox[1]) + line_gap
    return y


def text_size(draw, text, fnt):
    box = draw.textbbox((0, 0), text, font=fnt)
    return box[2] - box[0], box[3] - box[1]


def draw_brand(draw, canvas):
    icon = Image.open(ICON).convert("RGBA").resize((88, 88), Image.Resampling.LANCZOS)
    paste_rounded(canvas, icon, (140, 118), 22)
    draw.text((252, 136), "HTML Serve", font=FONT_BRAND, fill=COLORS["text"])


def draw_pill(draw, text, xy):
    x, y = xy
    tw, th = text_size(draw, text, FONT_LABEL)
    pad_x, pad_y = 24, 13
    box = (x, y, x + tw + pad_x * 2, y + th + pad_y * 2)
    draw.rounded_rectangle(box, radius=30, fill=(22, 47, 40), outline=(55, 125, 97), width=2)
    draw.text((x + pad_x, y + pad_y - 2), text, font=FONT_LABEL, fill=COLORS["secondary"])
    return box[3]


def add_device(canvas, source, box, radius=52, rotate=0, shadow=True):
    shot = Image.open(SRC / source).convert("RGBA")
    x, y, w, h = box
    frame = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    border = max(16, int(min(w, h) * 0.025))
    inner = (border, border, w - border, h - border)
    d = ImageDraw.Draw(frame)
    d.rounded_rectangle((0, 0, w - 1, h - 1), radius=radius, fill=COLORS["navy"] + (255,))
    d.rounded_rectangle(inner, radius=max(24, radius - border), fill=COLORS["surface"] + (255,))

    iw, ih = inner[2] - inner[0], inner[3] - inner[1]
    scale = max(iw / shot.width, ih / shot.height)
    resized = shot.resize((int(shot.width * scale), int(shot.height * scale)), Image.Resampling.LANCZOS)
    crop_x = max(0, (resized.width - iw) // 2)
    crop_y = max(0, (resized.height - ih) // 2)
    cropped = resized.crop((crop_x, crop_y, crop_x + iw, crop_y + ih))
    paste_rounded(frame, cropped, (inner[0], inner[1]), max(24, radius - border))

    if rotate:
        frame = frame.rotate(rotate, expand=True, resample=Image.Resampling.BICUBIC)
    if shadow:
        sh = Image.new("RGBA", frame.size, (0, 0, 0, 170))
        sh = sh.filter(ImageFilter.GaussianBlur(42))
        canvas.alpha_composite(sh, (x + 24, y + 34))
    canvas.alpha_composite(frame, (x, y))


def add_browser(canvas, source, box):
    shot = Image.open(SRC / source).convert("RGBA")
    x, y, w, h = box
    frame = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(frame)
    d.rounded_rectangle((0, 0, w - 1, h - 1), radius=28, fill=(245, 249, 250, 255))
    bar_h = 74
    d.rounded_rectangle((0, 0, w - 1, bar_h), radius=28, fill=(234, 240, 242, 255))
    d.rectangle((0, bar_h - 28, w, bar_h), fill=(234, 240, 242, 255))
    for i, c in enumerate([(151, 170, 178), (170, 187, 194), (190, 204, 210)]):
        d.ellipse((28 + i * 34, 27, 44 + i * 34, 43), fill=c + (255,))
    inner_h = h - bar_h
    scale = max(w / shot.width, inner_h / shot.height)
    resized = shot.resize((int(shot.width * scale), int(shot.height * scale)), Image.Resampling.LANCZOS)
    crop_x = max(0, (resized.width - w) // 2)
    crop_y = max(0, (resized.height - inner_h) // 2)
    cropped = resized.crop((crop_x, crop_y, crop_x + w, crop_y + inner_h))
    frame.alpha_composite(cropped, (0, bar_h))

    sh = Image.new("RGBA", frame.size, (0, 0, 0, 150)).filter(ImageFilter.GaussianBlur(34))
    canvas.alpha_composite(sh, (x + 18, y + 32))
    canvas.alpha_composite(frame, (x, y))


def make_slide(index, title, body, source, layout="hero", badge=None, warm=False):
    bg = gradient_bg(warm=warm).convert("RGBA")
    draw = ImageDraw.Draw(bg)
    draw_brand(draw, bg)

    if layout == "hero":
        if badge:
            draw_pill(draw, badge, (140, 278))
        draw_text(draw, title, (140, 382), FONT_TITLE_BIG, width=16, line_gap=8)
        draw_text(draw, body, (146, 760), FONT_BODY, fill=COLORS["muted"], width=30, line_gap=16)
        add_device(bg, source, (1268, 418, 1280, 880), rotate=-4)
    elif layout == "browser":
        if badge:
            draw_pill(draw, badge, (140, 278))
        draw_text(draw, title, (140, 382), FONT_TITLE, width=18, line_gap=8)
        draw_text(draw, body, (146, 650), FONT_BODY_SMALL, fill=COLORS["muted"], width=42, line_gap=12)
        add_browser(bg, source, (550, 830, 1630, 1020))
    elif layout == "split":
        if badge:
            draw_pill(draw, badge, (140, 278))
        draw_text(draw, title, (140, 392), FONT_TITLE, width=13, line_gap=8)
        draw_text(draw, body, (146, 730), FONT_BODY, fill=COLORS["muted"], width=24, line_gap=16)
        add_browser(bg, source, (1100, 418, 1420, 920))
    elif layout == "focus":
        if badge:
            draw_pill(draw, badge, (140, 278))
        draw_text(draw, title, (140, 392), FONT_TITLE, width=20, line_gap=8)
        add_browser(bg, source, (220, 600, 2290, 1260))
        draw_text(draw, body, (220, 1880), FONT_BODY_SMALL, fill=COLORS["muted"], width=64, line_gap=12)
    else:
        raise ValueError(layout)

    filename = OUT / f"{index:02d}-{title.lower().replace(' ', '-').replace('.', '').replace(',', '')}.png"
    bg.convert("RGB").save(filename, "PNG", optimize=True)
    return filename


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    slides = [
        ("Open HTML projects locally.", "Import a complete folder and run it locally with CSS, JavaScript, images, video, and links resolving correctly.", "03-running-guide.png", "hero", "No desktop server required", True),
        ("Serve folders, not single files.", "HTML Serve keeps your project structure intact so relative paths work the way they do on a real local server.", "01-projects.png", "browser", "Project folders", False),
        ("Browse every file in context.", "Folders, HTML pages, CSS, JavaScript, images, fonts, PDFs, and media stay visible inside one focused workspace.", "02-file-browser.png", "split", "File browser", False),
        ("Run any HTML page.", "Choose a page and preview it in WebKit while HTML Serve hosts the folder privately on the device.", "03-running-guide.png", "focus", "Embedded browser", True),
        ("JavaScript interactions work.", "Use modals, tabs, menus, charts, and browser-only app logic without leaving the device.", "03-running-guide.png", "split", "Client-side JS", False),
        ("Media files are served locally.", "MOV, MP4, images, fonts, PDFs, and other static assets are delivered from the same project folder.", "02-file-browser.png", "browser", "Video and assets", True),
        ("Built for repeated previewing.", "Navigate, reload, and inspect project pages without setting up a desktop web server.", "03-running-guide.png", "hero", "Fast preview loop", False),
        ("Your Files workflow stays simple.", "Copy projects through Files, cloud storage, AirDrop, or USB-C storage and run them directly on the device.", "01-projects.png", "split", "Import workflow", False),
        ("Private local server.", "Projects run on the device using a local address, keeping previews self-contained and portable.", "03-running-guide.png", "focus", "127.0.0.1", True),
        ("A portable HTML lab.", "Carry static sites, prototypes, demos, and documentation as runnable folders wherever you work.", "01-projects.png", "hero", "Local workflow", False),
    ]

    written = []
    for i, slide in enumerate(slides, 1):
        written.append(make_slide(i, *slide))

    print(f"Generated {len(written)} screenshots:")
    for path in written:
        with Image.open(path) as im:
            print(f"{path.relative_to(ROOT)} {im.width}x{im.height}")


if __name__ == "__main__":
    main()
