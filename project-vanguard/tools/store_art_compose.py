from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance, ImageChops
import numpy as np

D = "/home/claude/thumbs/"
ANTON = "/usr/share/fonts/truetype/google-fonts/ofl/anton/Anton-Regular.ttf"
MONT = "/usr/share/fonts/truetype/google-fonts/ofl/montserrat/Montserrat[wght].ttf"
CYAN = (0, 220, 255)
MAGENTA = (255, 60, 200)


def grade(im, lift=0.72, sat=1.25, contrast=1.08):
    a = np.asarray(im).astype(np.float32) / 255.0
    a = np.power(a, lift)  # lift the dark scene so heroes read
    im = Image.fromarray((a * 255).clip(0, 255).astype(np.uint8))
    im = ImageEnhance.Contrast(im).enhance(contrast)
    im = ImageEnhance.Color(im).enhance(sat)
    return im


def bloom(im, radius, strength=0.55, thresh=170):
    g = im.convert("L").point(lambda v: 255 if v > thresh else 0)
    bright = Image.composite(im, Image.new("RGB", im.size), g)
    glow = bright.filter(ImageFilter.GaussianBlur(radius))
    glow = ImageEnhance.Brightness(glow).enhance(strength)
    return ImageChops.add(im, glow)


def vignette(im, amount=0.55):
    w, h = im.size
    y, x = np.ogrid[:h, :w]
    d = np.sqrt(((x - w / 2) / (w / 2)) ** 2 + ((y - h / 2) / (h / 2)) ** 2)
    m = 1 - amount * np.clip(d - 0.55, 0, 1) ** 1.4
    a = np.asarray(im).astype(np.float32) * m[..., None]
    return Image.fromarray(a.clip(0, 255).astype(np.uint8))


def glow_text(base, xy, text, font, fill=(255, 255, 255), glow=CYAN, glow_r=18, anchor="mm", stroke=0, stroke_fill=None, shadow=True):
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.text(xy, text, font=font, fill=glow + (255,), anchor=anchor, stroke_width=stroke + 4, stroke_fill=glow + (255,))
    g = layer.filter(ImageFilter.GaussianBlur(glow_r))
    out = base.convert("RGBA")
    if shadow:
        sh = Image.new("RGBA", base.size, (0, 0, 0, 0))
        ImageDraw.Draw(sh).text((xy[0] + 0, xy[1] + glow_r // 3), text, font=font, fill=(0, 0, 0, 200), anchor=anchor, stroke_width=stroke + 2, stroke_fill=(0, 0, 0, 200))
        out = Image.alpha_composite(out, sh.filter(ImageFilter.GaussianBlur(glow_r / 2)))
    out = Image.alpha_composite(out, g)
    out = Image.alpha_composite(out, g)
    d2 = ImageDraw.Draw(out)
    d2.text(xy, text, font=font, fill=fill, anchor=anchor, stroke_width=stroke, stroke_fill=stroke_fill or glow)
    return out.convert("RGB")


def title_bar(img, cy, size):
    """PROJECT (small, spaced) over VANGUARD (big). Returns image."""
    W = img.size[0]
    big = ImageFont.truetype(ANTON, size)
    small = ImageFont.truetype(MONT, int(size * 0.26))
    small.set_variation_by_name("ExtraBold")
    img = glow_text(img, (W // 2, cy), "VANGUARD", big, fill=(255, 255, 255), glow=CYAN, glow_r=int(size * 0.14), stroke=max(2, size // 40), stroke_fill=(0, 150, 255))
    # spaced PROJECT with magenta glow
    spaced = " ".join("PROJECT")
    img = glow_text(img, (W // 2, cy - int(size * 0.62)), spaced, small, fill=(255, 235, 250), glow=MAGENTA, glow_r=int(size * 0.07), shadow=False)
    # accent underline
    d = ImageDraw.Draw(img)
    bw = int(size * 1.9)
    y = cy + int(size * 0.56)
    line = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(line).rectangle([W // 2 - bw // 2, y, W // 2 + bw // 2, y + max(3, size // 28)], fill=MAGENTA + (255,))
    img = Image.alpha_composite(img.convert("RGBA"), line.filter(ImageFilter.GaussianBlur(size // 30)))
    img = Image.alpha_composite(img, line).convert("RGB")
    return img


def thumb(src, cx, out, title_y=190, title_size=170, lift=0.72):
    im = Image.open(D + src).convert("RGB")
    w, h = im.size
    cw = int(h * 16 / 9)
    x0 = max(0, min(w - cw, cx - cw // 2))
    im = im.crop((x0, 0, x0 + cw, h))
    im = grade(im, lift=lift)
    im = im.resize((1920, 1080), Image.LANCZOS)
    im = im.filter(ImageFilter.UnsharpMask(radius=2.2, percent=90, threshold=2))
    im = bloom(im, 22)
    im = vignette(im)
    im = title_bar(im, title_y, title_size)
    im.save(D + out, quality=95)
    print(out, im.size)


thumb("lineup.jpg", 772, "thumb1_lineup.jpg", title_y=175, title_size=150)
thumb("combat.jpg", 748, "thumb2_combat.jpg", title_y=175, title_size=150)
thumb("skins.jpg", 770, "thumb3_skins.jpg", title_y=175, title_size=150)

# Icon: Titan close-up, square
im = Image.open(D + "icon.jpg").convert("RGB")
im = im.crop((520, 0, 1030, 510))
im = grade(im, lift=0.68, sat=1.3)
im = im.resize((1024, 1024), Image.LANCZOS).filter(ImageFilter.UnsharpMask(radius=2, percent=80, threshold=2))
im = bloom(im, 18)
im = vignette(im, 0.7)
# dark gradient at the bottom for the title
grad = Image.new("L", (1, 1024))
for y in range(1024):
    grad.putpixel((0, y), int(255 * max(0, (y - 560) / 464) ** 1.2 * 0.92))
grad = grad.resize((1024, 1024))
im = Image.composite(Image.new("RGB", im.size, (4, 6, 16)), im, grad)
im = title_bar(im, 880, 190)
# neon frame
fr = Image.new("RGBA", im.size, (0, 0, 0, 0))
ImageDraw.Draw(fr).rectangle([10, 10, 1013, 1013], outline=CYAN + (255,), width=8)
im = Image.alpha_composite(im.convert("RGBA"), fr.filter(ImageFilter.GaussianBlur(8)))
im = Image.alpha_composite(im, fr).convert("RGB")
im = im.resize((512, 512), Image.LANCZOS)
im.save(D + "icon_512.png")
print("icon", im.size)
