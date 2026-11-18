// Minimal launcher for Tess on the Boxedwine web build.
var MULTI_THREADED = true;                           // build.sh sets false for the SingleThreaded build
var ROOT = "/root";                                  // Boxedwine's writable layer, kept in IndexedDB
var ZIPS = ["boxedwine.zip", "tess.zip"];            // Wine root file system, then Tess
var DRIVE_C = "/home/username/.wine/drive_c";
var APP_DIR = DRIVE_C + "/Tess";                     // C:\Tess
var EXE = "tess.exe";
var DEFAULT_RESOLUTION = "1024x768";

var statusEl = document.getElementById("status");
function setStatus(text) { statusEl.textContent = text; }
function param(name) { return new URLSearchParams(location.search).get(name); }

async function download(name) {
    var res = await fetch(name);
    if (!res.ok) throw new Error(name + ": HTTP " + res.status);
    var total = Number(res.headers.get("Content-Length")) || 0;
    var reader = res.body.getReader(), chunks = [], got = 0;
    for (;;) {
        var part = await reader.read();
        if (part.done) break;
        chunks.push(part.value);
        got += part.value.length;
        setStatus("Downloading " + name + ": " + (got >> 20) + (total ? " / " + (total >> 20) : "") + " MB");
    }
    var data = new Uint8Array(got), offset = 0;
    for (var chunk of chunks) { data.set(chunk, offset); offset += chunk.length; }
    return data;
}

function emulatorArgs() {
    var args = ["-root", ROOT];
    for (var zip of ZIPS) args.push("-zip", zip);
    if (param("sound") !== "true") args.push("-nosound");   // Tess makes no sound
    args.push("-resolution", param("resolution") || DEFAULT_RESOLUTION);
    if (param("winedebug")) args.push("-env", "WINEDEBUG=" + param("winedebug").replace(/ /g, "+"));  // e.g. ?winedebug=+seh
    // 3D views: Mesa's opengl32.dll sits next to tess.exe (build.sh); prefer it to Wine's,
    // which has no OpenGL to talk to in the browser. softpipe needs no JIT; ?gl=llvmpipe to compare.
    args.push("-env", "WINEDLLOVERRIDES=opengl32=n,b");
    args.push("-env", "GALLIUM_DRIVER=" + (param("gl") || "softpipe"));
    args.push("-w", APP_DIR, "/bin/wine", EXE);
    return args;
}

// Files Tess writes (saved tilings, exported images) land in Boxedwine's writable
// layer under ROOT. List those under C:\ (minus Wine's own folders) for download.
var SKIP = /^(windows|ProgramData|Program Files|Program Files \(x86\)|users\/[^/]+\/(AppData|Temp))(\/|$)/i;
function listUserFiles() {
    var base = ROOT + DRIVE_C, found = [];
    function walk(dir, rel) {
        var names;
        try { names = FS.readdir(dir); } catch (e) { return; }
        for (var name of names) {
            if (name === "." || name === "..") continue;
            var path = dir + "/" + name, sub = rel ? rel + "/" + name : name;
            if (SKIP.test(sub)) continue;
            var st;
            try { st = FS.stat(path); } catch (e) { continue; }
            if (FS.isDir(st.mode)) walk(path, sub);
            else if (FS.isFile(st.mode)) found.push({ path: path, rel: sub, size: st.size });
        }
    }
    walk(base, "");
    return found;
}

function refreshFiles() {
    var list = document.getElementById("files");
    if (!list || typeof FS === "undefined") return;
    var files = listUserFiles();
    list.textContent = "";
    if (!files.length) {
        var li = document.createElement("li");
        li.textContent = "No files yet. Anything Tess saves or exports under C:\\ shows up here.";
        list.appendChild(li);
        return;
    }
    for (var f of files) {
        var li = document.createElement("li"), a = document.createElement("a");
        a.href = "#";
        a.textContent = "C:\\" + f.rel.replace(/\//g, "\\");
        a.onclick = (function (file) {
            return function (ev) {
                ev.preventDefault();
                var blob = new Blob([FS.readFile(file.path)]);
                var link = document.createElement("a");
                link.href = URL.createObjectURL(blob);
                link.download = file.rel.split("/").pop();
                link.click();
                setTimeout(function () { URL.revokeObjectURL(link.href); }, 10000);
            };
        })(f);
        li.appendChild(a);
        li.appendChild(document.createTextNode(" (" + Math.max(1, Math.round(f.size / 1024)) + " KB)"));
        list.appendChild(li);
    }
}

var Module = {
    arguments: [],
    canvas: document.getElementById("canvas"),
    print: function (text) { console.log(text); },
    printErr: function (text) { console.error(text); },
    setStatus: function (text) { if (text) setStatus(text); },
    preRun: [function () {
        Module.addRunDependency("files");
        FS.mkdir(ROOT);
        FS.mount(IDBFS, { autoPersist: true }, ROOT);
        FS.syncfs(true, async function (err) {
            if (err) console.error("IndexedDB:", err);
            try {
                for (var zip of ZIPS) FS.writeFile("/" + zip, await download(zip));
            } catch (e) {
                setStatus("Error: " + e.message);
                return;
            }
            Module.arguments.push.apply(Module.arguments, emulatorArgs());
            setStatus("Starting Wine... (the first start takes a while)");
            Module.removeRunDependency("files");
            var refresh = document.getElementById("refresh");
            if (refresh) { refresh.disabled = false; refresh.onclick = refreshFiles; }
            refreshFiles();
        });
    }]
};

window.onerror = function (msg) { setStatus("Error: " + msg); };

function loadEmulator() {
    var script = document.createElement("script");
    script.src = "boxedwine.js";
    document.body.appendChild(script);
}

// The multi-threaded build needs SharedArrayBuffer, i.e. a cross-origin isolated page.
// coi-serviceworker.js provides that on hosts that can't send COOP/COEP headers.
if (location.protocol === "file:") {
    setStatus("Serve this folder over http(s); it does not work from file://");
} else if (!MULTI_THREADED || window.crossOriginIsolated) {
    sessionStorage.removeItem("coiRetry");
    loadEmulator();
} else if (!("serviceWorker" in navigator)) {
    setStatus("This browser can't run the multi-threaded build here (no service workers, e.g. private mode).");
} else {
    setStatus("Waiting for cross-origin isolation (the page reloads once)...");
    navigator.serviceWorker.ready.then(function () {
        // Reload if the page loaded before the service worker took control.
        var tries = Number(sessionStorage.getItem("coiRetry")) || 0;
        if (tries < 3) {
            sessionStorage.setItem("coiRetry", tries + 1);
            location.reload();
        } else {
            setStatus("Cross-origin isolation failed; reload the page or try another browser.");
        }
    });
}
