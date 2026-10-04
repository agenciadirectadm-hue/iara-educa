#!/usr/bin/env python3
"""
Recorta o fundo do mascote oficial (mascote-ipe-roxo.png) e gera os recursos da interface:
  public/iara/iara-full.webp      — mascote inteiro, fundo transparente
  public/iara/iara-body.webp      — mascote sem o braço que acena (mesmo enquadramento)
  public/iara/iara-arm.webp       — somente o braço (mesmo enquadramento) para animação de aceno
  public/iara/iara-avatar.webp    — rosto + copa em círculo (chat, ajuda contextual)
  public/icons/*.png              — ícones PWA / favicon
Método: modelo polinomial da cor de fundo a partir das bordas + componentes conectados + sombra suave
removida + borda com alfa suavizado e descontaminação de cor. Nada é redesenhado: é a arte oficial.
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "mascote-ipe-roxo.png"
OUT = ROOT / "public" / "iara"
ICONS = ROOT / "public" / "icons"
OUT.mkdir(parents=True, exist_ok=True)
ICONS.mkdir(parents=True, exist_ok=True)

# Polígono do braço que acena (coordenadas da imagem original 1145×1374)
ARM = [(800, 852), (800, 772), (810, 760), (806, 652), (818, 638), (840, 640), (862, 660), (868, 628), (888, 617),
       (912, 617), (930, 632), (944, 634), (958, 628), (974, 640), (972, 668), (990, 676), (998, 694), (992, 718),
       (952, 754), (906, 780), (872, 806), (846, 832), (816, 852)]
PIVOT = (792, 812)  # dentro da manga: o giro esconde a emenda
# Tênis e meias brancos têm tom muito próximo do fundo creme: dentro destes polígonos usa-se limiar estrito
PROTECT = [
    [(357, 1281), (373, 1300), (460, 1304), (524, 1298), (537, 1281), (536, 1238), (545, 1190), (543, 1150), (480, 1140),
     (455, 1150), (452, 1190), (420, 1200), (388, 1228), (365, 1258)],
    [(612, 1250), (612, 1282), (628, 1291), (730, 1296), (828, 1289), (830, 1270), (815, 1240), (760, 1215), (722, 1200),
     (720, 1158), (680, 1152), (632, 1160), (630, 1205), (618, 1225)],
]


def fit_background(rgb: np.ndarray, border: int = 18) -> np.ndarray:
    h, w, _ = rgb.shape
    yy, xx = np.mgrid[0:h, 0:w]
    m = np.zeros((h, w), bool)
    m[:border, :] = m[-border:, :] = True
    m[:, :border] = m[:, -border:] = True
    x = xx[m] / w
    y = yy[m] / h
    feats = np.stack([np.ones_like(x), x, y, x * y, x * x, y * y], 1)
    model = np.zeros_like(rgb, dtype=np.float32)
    X = xx / w
    Y = yy / h
    F = np.stack([np.ones_like(X), X, Y, X * Y, X * X, Y * Y], -1)
    for c in range(3):
        coef, *_ = np.linalg.lstsq(feats, rgb[..., c][m].astype(np.float64), rcond=None)
        model[..., c] = F @ coef
    return model


def main() -> None:
    img = Image.open(SRC).convert("RGB")
    rgb = np.asarray(img).astype(np.float32)
    h, w, _ = rgb.shape
    bg = fit_background(rgb)
    diff = np.sqrt(((rgb - bg) ** 2).sum(-1))

    # Sombra no chão: escurecimento proporcional do fundo (razões dos canais parecidas), só na faixa inferior
    ratio = rgb / np.maximum(bg, 1)
    spread = ratio.max(-1) - ratio.min(-1)
    yy = np.mgrid[0:h, 0:w][0]
    shadow = (yy > h * 0.86) & (ratio.mean(-1) > 0.45) & (ratio.mean(-1) < 0.995) & (spread < 0.16)

    cand = (diff < 24) | shadow
    labels, _ = ndimage.label(cand)
    edge_labels = np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))
    edge_labels = edge_labels[edge_labels > 0]
    background = np.isin(labels, edge_labels)
    prot = Image.new("L", (w, h), 0)
    for poly in PROTECT:
        ImageDraw.Draw(prot).polygon(poly, fill=255)
    prot = np.asarray(prot) > 0
    background = np.where(prot, diff < 9, background)
    # fecha buracos pequenos do primeiro plano (reflexos claros dentro da arte)
    fg = ~background
    fg = ndimage.binary_fill_holes(fg)
    fg = ndimage.binary_opening(fg, iterations=1)
    # mantém só o maior componente (o mascote)
    lab, n = ndimage.label(fg)
    if n > 1:
        sizes = ndimage.sum(fg, lab, range(1, n + 1))
        fg = lab == (1 + int(np.argmax(sizes)))

    # Alfa suave na borda (faixa de ~2 px) + descontaminação da cor do fundo
    dist_in = ndimage.distance_transform_edt(fg)
    alpha = np.clip(dist_in / 2.2, 0, 1)
    soft = np.clip((diff - 10) / 30, 0, 1)
    alpha = np.where(dist_in < 3, np.minimum(alpha + soft * 0.6, 1), alpha)
    alpha = np.where(fg, alpha, 0)
    a3 = alpha[..., None]
    color = np.where(a3 > 0.02, (rgb - (1 - a3) * bg) / np.maximum(a3, 0.02), rgb)
    color = np.clip(color, 0, 255)
    rgba = np.dstack([color, alpha * 255]).astype(np.uint8)
    full = Image.fromarray(rgba, "RGBA")

    # Enquadramento comum (corte pelo conteúdo + margem)
    bbox = full.getbbox()
    pad = 16
    box = (max(bbox[0] - pad, 0), max(bbox[1] - pad, 0), min(bbox[2] + pad, w), min(bbox[3] + pad, h))

    arm_mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(arm_mask).polygon(ARM, fill=255)
    arm_mask = arm_mask.filter(ImageFilter.GaussianBlur(0.6))
    am = np.asarray(arm_mask).astype(np.float32) / 255.0
    body = rgba.copy()
    body[..., 3] = (body[..., 3].astype(np.float32) * (1 - am)).astype(np.uint8)
    arm = rgba.copy()
    arm[..., 3] = (arm[..., 3].astype(np.float32) * am).astype(np.uint8)

    def save(arr_or_img, name, height=None, quality=88):
        im = arr_or_img if isinstance(arr_or_img, Image.Image) else Image.fromarray(arr_or_img, "RGBA")
        im = im.crop(box)
        if height:
            im = im.resize((round(im.width * height / im.height), height), Image.LANCZOS)
        im.save(OUT / name, "WEBP", quality=quality, method=6)
        return im

    full_c = save(full, "iara-full.webp", 900)
    save(body, "iara-body.webp", 900)
    save(arm, "iara-arm.webp", 900)
    save(full, "iara-full-sm.webp", 420, quality=86)
    scale = 900 / (box[3] - box[1])
    pivot = ((PIVOT[0] - box[0]) * scale / full_c.width, (PIVOT[1] - box[1]) * scale / full_c.height)

    # Avatar: rosto + copa
    face_box = (300, 330, 860, 890)
    av = full.crop(face_box).resize((512, 512), Image.LANCZOS)
    bgc = Image.new("RGBA", av.size, (244, 233, 252, 255))
    circle = Image.new("L", av.size, 0)
    ImageDraw.Draw(circle).ellipse((0, 0, 511, 511), fill=255)
    comp = Image.alpha_composite(bgc, av)
    comp.putalpha(circle)
    comp.resize((256, 256), Image.LANCZOS).save(OUT / "iara-avatar.webp", "WEBP", quality=90, method=6)

    # Ícones PWA: mascote sobre gradiente roxo→azul
    def icon(size, name, maskable=False):
        g = Image.new("RGBA", (size, size))
        top, bottom = np.array([122, 36, 197]), np.array([8, 109, 182])
        grad = (top[None, :] + (bottom - top)[None, :] * np.linspace(0, 1, size)[:, None]).astype(np.uint8)
        g = Image.fromarray(np.repeat(grad[:, None, :], size, 1), "RGB").convert("RGBA")
        inner = int(size * (0.72 if maskable else 0.9))
        mascot = full.crop(box)
        mascot.thumbnail((inner, inner), Image.LANCZOS)
        g.alpha_composite(mascot, ((size - mascot.width) // 2, size - mascot.height - int(size * (0.1 if maskable else 0.04))))
        if not maskable:
            r = int(size * 0.22)
            mask = Image.new("L", (size, size), 0)
            ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), r, fill=255)
            g.putalpha(mask)
        g.save(ICONS / name, "PNG", optimize=True)

    icon(192, "icon-192.png")
    icon(512, "icon-512.png")
    icon(512, "maskable-512.png", maskable=True)
    icon(180, "apple-touch-icon.png", maskable=True)
    icon(64, "favicon-64.png")

    print("ok", {"box": box, "full": full_c.size, "pivot_rel": [round(pivot[0], 4), round(pivot[1], 4)]})


if __name__ == "__main__":
    main()
