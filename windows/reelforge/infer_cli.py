from __future__ import annotations

import argparse
from pathlib import Path

from reelforge import infer


def main() -> None:
    parser = argparse.ArgumentParser(prog="reelforge-infer")
    parser.add_argument("mode", choices=("video", "image", "scan"))
    parser.add_argument("--out", dest="out")
    parser.add_argument("--prompt", default="")
    parser.add_argument("--aspect", default="9:16")
    parser.add_argument("--seconds", type=float, default=3.0)
    parser.add_argument("--models-dir", dest="models_dir")
    args = parser.parse_args()
    if args.mode == "scan":
        import json
        print(json.dumps(infer.available(args.models_dir)))
        return
    dest = Path(args.out or "")
    ok = False
    if args.mode == "video":
        ok = infer.generate_video(args.prompt, dest, aspect=args.aspect, seconds=args.seconds, models_dir=args.models_dir)
    else:
        ok = infer.generate_image(args.prompt, dest, aspect=args.aspect, models_dir=args.models_dir)
    raise SystemExit(0 if ok else 2)


if __name__ == "__main__":
    main()
