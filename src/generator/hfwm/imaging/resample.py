"""Resizing that does not throw away the colour under transparent pixels.

Pillow resamples RGBA images in premultiplied space and divides the alpha
back out afterwards, which is correct for compositing but destroys the RGB
of any pixel whose alpha is zero — 0/0 comes back as black.  That matters
here because the sea is erased by clearing *only* the alpha
(:func:`hfwm.imaging.ocean.apply_erase`), which deliberately leaves its real
colour in the RGB channels so the coastline downscales into sea rather
than into black.  One ordinary ``Image.resize`` and the sea is black
again, halo and all.

Resampling the channels separately avoids it: the colour plane never sees
the alpha plane, so a transparent pixel contributes its colour to its
neighbours and keeps its own.  The visible consequence at a coastline is
that a part-transparent fringe pixel blends land into *sea* rather than
land into black, which is both what the raw stitch does and the better
input to alpha blending — part-black at partial alpha is the classic dark
halo.

Use this for every resize of an image whose transparent regions carry
meaning.  Plain ``Image.resize`` is still right for opaque images and for
ones where transparent means "nothing here".
"""


def resize_rgba(img, size, resample=None):
    """Resize *img* to *size*, preserving RGB under fully transparent pixels.

    *img* must be RGBA.  Returns a new image; the input is untouched.
    """
    from PIL import Image

    if resample is None:
        resample = Image.LANCZOS
    if img.size == tuple(size):
        return img.copy()

    rgb = img.convert("RGB").resize(size, resample)
    alpha = img.getchannel("A").resize(size, resample)
    out = rgb.convert("RGBA")
    out.putalpha(alpha)
    return out
