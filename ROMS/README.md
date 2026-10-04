# ROMS

Disassemblies of the EPROM images used by the Quantum QM2000, which is built
from Gemini 80-BUS boards. Each sub-folder holds an annotated, re-assemblable
Z80 source, a Makefile and a README with the details. The sources assemble with
[z80asm](https://savannah.nongnu.org/projects/z80asm/) (`brew install z80asm`)
back to images that are byte-for-byte identical to the originals.

| Folder | Board | ROM | Size | What it is |
|--------|-------|-----|------|------------|
| [QM-MON](QM-MON/) | GM813 CPU board | `QM-MON-V21` | 2 KB | QM2000 monitor / boot ROM, V2.1 ("(C) dci software 22-07-82"), mapped at F000h |
| [IVC-MON](IVC-MON/) | GM812 IVC video board | `IVC-MON-V20` | 4 KB | Monitor of the video controller's own Z80: screen, cursor, `ESC` command set, keyboard and function keys, V2.0 |
| [IVC-GEN](IVC-GEN/) | GM812 IVC video board | `IVC-GEN-V10` | 2 KB | Character generator, V1.0: 128 glyphs of 16 raster rows |
| [Originals](Originals/) | | | | The untouched ROM dumps (Intel HEX and raw binary) |

## Sub-folders

### QM-MON
Source and notes for the QM2000 CPU board monitor. It is a small command-line
monitor (`B`oot, `C`opy, `E`xecute, `F`ill, `M`odify memory, `O`utput, `Q`uery
port, `T`ype memory) that also loads a boot sector from floppy disc and drives
the GM812 IVC for console I/O.

Files: `QM-Mon-V21.asm`, `Makefile`, `README.md`.

### IVC-MON
Fully annotated disassembly of the program that runs on the IVC's own Z80A.
It drives the 6845 CRTC and VDU RAM, accepts bytes from the host through the
three I/O ports, interprets the control codes and `ESC` sequences of the GM812
software manual, scans the keyboard and manages the programmable function
keys. The README cross-checks every command against the manual and lists the
few differences found.

Files: `IVC-MON-V20.asm`, `Makefile`, `README.md`.

### IVC-GEN
Editable source for the lower character generator EPROM (character codes
00h-7Fh). Every glyph is 16 `defb %bbbbbbbb` lines with a picture comment, so
characters can be changed and the image rebuilt. The upper 128 characters are
RAM on the card and are loaded by the host with `ESC C` / `ESC c`. The README
describes the layout and editing procedure, and the folder also supports a
`diff` target that lists changed bytes.

Files: `IVC-GEN-V10.asm`, `Makefile`, `README.md`.

### Originals
The three ROM images as dumped from genuine EPROMs extracted from the QM812 and QM813 boards. Filse are present as Intel HEX and raw binary, kept
unmodified so the sources can always be checked against them. See
[Originals/README.md](Originals/README.md) for sizes, format, checksums and the
HEX to binary conversion.

| Image | Content |
|-------|---------|
| `QM-MON-V21.HEX` / `.BIN` | QM2000 monitor, 2048 bytes |
| `IVC-MON-V20.HEX` / `.BIN` | IVC monitor, 4096 bytes |
| `IVC-GEN-V10.HEX` / `.BIN` | IVC character generator, 2048 bytes |

## Notes

* **Makefiles.** Each sub-folder has a `Makefile` with `make` (assemble to
  `.bin`, `.lst` and `.sym`) and `make clean`. There is no `verify` target. To
  compare a build with an original, run `cmp` against the `.BIN` in
  `Originals`. `IVC-GEN` also has `make diff`, which lists
  the bytes that differ from `../Originals/IVC-GEN-V10.BIN`, for checking
  glyph edits.
* **`.gitignore` and `*.hex`.** The repository `.gitignore` ignores `*.hex`.
  On a case-insensitive file system (macOS default) that also matches the
  `.HEX` originals, which then do not get committed. Use `git add -f`, or add
  `!ROMS/Originals/*.HEX` to `.gitignore`.
* **Generated files** (`*.bin`, `*.lst`, `*.sym`) are build output and are not
  stored here.

