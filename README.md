`levent` is a WIP media tagger.

### whats working

- importing images into levent (w/ thumbnail generation)
- tagging images (very simple space separated tags)
- filtering images

### whats next

- use sqlite or something
- importing any file
- support showing more metadata about files
- add tabs for showing files (with separate filters)
- add filtering by various metadata (width, height, etc.)

## usage

obtain executables from [the latest nightly release](https://github.com/yusdacra/levent/releases/tag/nightly).
currently supports macos, linux and windows.

also see `levent -h` for CLI flags / commands.

## development

- obtain zig (current targeted version is `0.14.0-dev.2362+a47aa9dd9`).
    - on linux, you also need `gtk-3.0`, `gdk-3.0` and `atk-1.0`.
- run `zig build run` to run a debug build.