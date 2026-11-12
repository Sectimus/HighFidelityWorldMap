"""Colour bleed for alpha-erased art.

The sea is erased by clearing only its alpha (:func:`hfwm.imaging.ocean.apply_erase`).
Its RGB under alpha 0 is near-black, so any filter that reads RGB across a
coastline pulls the land colour towards black: the dark halo.

Pillow's RGBA ``resize`` works in premultiplied space, so transparent pixels
contribute no colour and downscaling is correct. What remains is the
transparent pixels themselves: the GPU bilinear-samples RGB and alpha
independently, so a sample straddling land and an alpha-0 neighbour still
blends towards that neighbour's RGB. :func:`bleed_colour` fixes this by
copying the nearest opaque colour into every alpha-0 pixel within a radius.
"""

import numpy as np
from PIL import Image
from scipy import ndimage


def bleed_colour(img, radius: int):
    """Return a copy of RGBA *img* with each alpha-0 pixel within *radius* of
    an opaque-enough pixel set to that pixel's colour. Alpha is unchanged.
    """
    arr = np.array(img)
    known = arr[:, :, 3] > 0
    if not known.any() or known.all():
        return img.copy()
    dist, (iy, ix) = ndimage.distance_transform_edt(~known, return_indices=True)
    near = (dist > 0) & (dist <= radius)
    rgb = arr[:, :, :3]
    rgb[near] = rgb[iy[near], ix[near]]
    return Image.fromarray(arr, "RGBA")
