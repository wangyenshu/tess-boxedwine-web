# tess-boxedwine-web

[Tess](http://www.peda.com/tess/) 1.75 for Windows (Pedagoguery Software's symmetry and tessellation drawing program) running in the browser on [Boxedwine](https://github.com/danoon2/Boxedwine). The layout follows [elona-boxedwine-web](https://github.com/wangyenshu/elona-boxedwine-web): one `build.sh` that downloads everything and writes a static site to `dist/`, plus the page and launcher in `web/`.

```
build.sh                 downloads, unpacks and assembles dist/
web/index.html           the page
web/shell.js             launcher: loads the zips, mounts IndexedDB, starts tess.exe
web/coi-serviceworker.js cross-origin isolation for the multi-threaded build
```

## Build

Needs bash, curl, unzip, zip and 7-Zip (`7z`, from p7zip-full or 7zip). About 320 MB is downloaded once into `cache/`.

```sh
./build.sh
cd dist && python3 -m http.server 8000   # open http://localhost:8000/
```

Upload the contents of `dist/` (about 61 MB) to any static host. GitHub Pages works: `coi-serviceworker.js` supplies the COOP/COEP headers the multi-threaded build needs.

Options (environment variables):

| Variable | Default | |
|---|---|---|
| `BUILD` | `MultiThreaded` | or `SingleThreaded` (slower, but needs no cross-origin isolation or service worker) |
| `BOXEDWINE_VERSION` | `26R1` | Boxedwine web release |
| `TESS_SETUP` | | path to a local `tess_setup.exe` instead of downloading it from peda.com |
| `MESA` | `1` | `0` leaves out the software OpenGL (9 MB smaller, but the 3D views then crash) |
| `MESA_VERSION` | `20.1.8` | mesa-dist-win release |

URL parameters: `?resolution=1280x1024`, `?winedebug=+seh`, `?gl=llvmpipe` (Mesa driver; default `softpipe`), `?sound=true`.

## What the build does

1. Takes `boxedwine.js` / `boxedwine.wasm` and the stripped Wine 11 file system from the official Boxedwine web release. No compiler is involved: elona-boxedwine-web recompiles Boxedwine to fix an audio crash and to let the heap grow, and Tess needs neither.
2. Adds `glu32.dll.so` from Boxedwine's full Wine 11 file system. `tess.exe` imports GLU32, and the stripped file system doesn't have it, so Tess won't start without it.
3. Unpacks `tess_setup.exe` (an NSIS installer) with 7-Zip into `C:\Tess`. Wine doesn't run the installer.
4. Puts Mesa's software `opengl32.dll` (x86, from [mesa-dist-win](https://github.com/pal1000/mesa-dist-win)) next to `tess.exe`, and `shell.js` sets `WINEDLLOVERRIDES=opengl32=n,b`. Tess's 3D views (cone, cylinder, torus) use OpenGL, and Boxedwine's web build has none. Without Mesa, choosing a 3D view hits a page fault that escapes Boxedwine's CPU loop and kills the emulator. With Mesa, softpipe renders those views on the emulated CPU.
5. Copies Tess's own help pages to `dist/help/` and links them from the page, because Tess's Help menu can't open a browser from inside Wine.

## Using it

- Tess runs as the unregistered evaluation version. Everything works except saving, exporting and printing, and a reminder screen appears every 10 minutes (its buttons change places each time). To unlock saving, [buy a license](http://www.peda.com/prices) and enter it under File > Register....
- Everything Tess writes, including its settings, goes into Boxedwine's writable layer, which is kept in the browser's IndexedDB. The page lists files under `C:\` so you can download them.
- 3D views need a tiling with translations, for example one from File > New Heesch Tiling.

Tess is commercial software © Pedagoguery Software Inc. The build downloads it from peda.com rather than shipping it. Check Pedagoguery's terms before hosting a built `dist/` publicly.

## Credits

Tess by Pedagoguery Software Inc. · Boxedwine (GPL-2.0) · Mesa 3D (MIT), Windows build by mesa-dist-win · coi-serviceworker (MIT) · layout from elona-boxedwine-web
