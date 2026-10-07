# Brand artwork

The supplied Echno mark, kept here as the source the app's assets are derived
from. `echno-logo.svg` is the navy mark for light backgrounds;
`echno-logo-white.svg` is the white one for dark.

## These are not vector files

Both are SVG wrappers around a pair of embedded base64 PNGs — a greyscale mask
and an RGB image, each 1536×1024, composited through an SVG `<mask>`. There is
one real `<path>` in each, and it is the clip rectangle. So nothing is gained by
shipping them as vectors: Xcode's "preserve vector data" would preserve a
bitmap, at roughly twice the bytes.

Worth replacing with true vector artwork if it exists. At the sizes used today
(up to 64 pt) the raster is indistinguishable, but an App Store icon is 1024 pt
and a real outline would also let the mark be tinted rather than shipped twice.

## Deriving `EchnoMark.imageset`

Rendered with `rsvg-convert`, which honours the mask, then trimmed to the alpha
bounding box and padded to a square so both variants land on identical geometry
and the mark does not shift when the appearance changes:

```sh
rsvg-convert -h 1440 -o out.png echno-logo.svg
# trim to alpha bbox (1357×1361), pad to square, resize to 128/256/384 px
```

Measured ink: navy `#173664`, white `#FAFBFB`.
