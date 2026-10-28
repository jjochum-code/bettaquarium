"""Counts frames in which an eye of the fish contains a pure white pixel.

Expects in <run_dir>: eyepos.txt (output of eye_track.gd) and eyevid/f########.png
(a movie of the same run). Usage: python3 -I sparkles.py <run_dir> <label>
"""
import sys

from PIL import Image

RADIUS = 9  # px around each eye centre
WHITE = 250
FIRST_FRAME, LAST_FRAME = 5, 117


def load_eye_positions(path):
    positions = {}
    with open(path) as f:
        for line in f:
            fields = line.split()
            if fields and fields[0] == "EYE":
                frame, *coords = fields[1:]
                positions[int(frame)] = tuple(map(float, coords))
    return positions


def has_white_pixel(image, x, y):
    box = (int(x) - RADIUS, int(y) - RADIUS, int(x) + RADIUS, int(y) + RADIUS)
    return image.crop(box).getextrema()[1] > WHITE


def main(run_dir, label):
    positions = load_eye_positions(f"{run_dir}/eyepos.txt")
    frames = hits = 0
    for n in range(FIRST_FRAME, LAST_FRAME + 1):
        # The movie writer lags the script by one frame.
        if n + 1 not in positions:
            continue
        frames += 1
        image = Image.open(f"{run_dir}/eyevid/f{n:08d}.png").convert("L")
        x0, y0, x1, y1 = positions[n + 1]
        if has_white_pixel(image, x0, y0) or has_white_pixel(image, x1, y1):
            hits += 1
    print(f"{label}: frames with a pure white pixel on an eye: {hits}/{frames}")


if __name__ == "__main__":
    main(*sys.argv[1:3])
