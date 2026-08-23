# epson-l3270-mac — driverless Epson L3270 printing from macOS

Prints PDFs and images to an **Epson L3270** over Wi-Fi using pure IPP +
PWG-raster — no Epson drivers, no CUPS queue, no sudo. Includes a native
Swift CLI, Python reference implementation, and a menu bar app with ink
monitoring.

```
l3270 document.pdf                 # Swift CLI — print on A4, color
l3270 photo.jpg --media 4x6        # photo size
l3270 doc.pdf --mono --copies 2    # grayscale, two copies
```

## Menu bar app (L3270.app)

The menu bar app discovers your printer, shows ink levels (via the Epson
Remote UI), and prints files without the vendor driver.

1. Build: `make swift-app` (or `cd swift && ./scripts/build-app.sh release`)
2. Install: copy `swift/.build/L3270.app` to `/Applications/`
3. Launch L3270 from the menu bar (printer icon)
4. Enter the admin password from the label on your printer (stored in Keychain)
5. Use **Print File…** or drag a PDF/image onto the ink panel

Low-ink notifications appear when any tank drops below 15%.

## How it works

The L3270 does not accept PDF. It is an AirPrint-class device that accepts
`image/pwg-raster`. This tool:

1. **Discovers** the printer via mDNS (`_ipp._tcp.local`)
2. **Renders** at 360 dpi with CoreGraphics (Swift) or pypdfium2/Pillow (Python)
3. **Encodes** PWG raster: 1796-byte headers + libcups PackBits compression
4. **Sends** IPP Print-Job via HTTPS (implicit TLS on port 631)
5. **Monitors ink** by scraping the embedded web UI on port 80 (Remote UI)

## Setup — Python (reference)

```
make setup
make test
make print-test
```

## Setup — Swift (primary)

Requires macOS 13+ and Xcode command-line tools.

```
make swift-test
make swift-build
make swift-run
make swift-app          # builds L3270.app
```

Or directly:

```
cd swift
swift test
swift run l3270 samples/test-page.pdf --dry-run /tmp/out.pwg
swift run L3270App      # menu bar app (dev)
./scripts/build-app.sh release
```

## CLI reference

```
usage: l3270 FILE [options]

  --media {a4,letter,legal,a5,a6,b5,4x6,5x7,8x10}
  --mono            grayscale
  --copies N
  --printer NAME    Bonjour name substring (default L3270)
  --host HOST       skip discovery
  --dry-run FILE    write PWG stream instead of printing
```

## Remote UI / ink levels

Login: `POST /PRESENTATION/PSWD` with the label password → session cookie
`EPSON_COOKIE_SESSION`. Ink bars are read from `<img … Ink_K/C/M/Y.PNG …
height="NN">` on the status page.

The app asks for your password once and stores it in the macOS Keychain.

## Repo layout

```
swift/
  Sources/L3270Core/   shared library (print + remote UI)
  Sources/L3270App/    menu bar app
  Sources/l3270/       CLI
  Tests/L3270Tests/    unit tests + HTML fixtures
epson_print/           Python reference implementation
samples/               test-page.pdf
```

## Native macOS printing (no tool)

Create an IPP Everywhere queue — CUPS generates PWG raster itself:

```
sudo lpadmin -p L3270 -E -v ipp://EPSONxxxx.local.:631/ipp/print -m everywhere
```

Do **not** install Epson's downloaded driver packages; they often cause blank
pages on recent macOS versions.
