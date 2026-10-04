# IVC-GEN-V10: Gemini G812 character generator ROM

Editable Z80 assembler source for the lower character generator EPROM (IC20)
of the Gemini GM812 Intelligent Video Controller. It assembles back to a
2048 byte image that is **byte-for-byte identical** to
`IVC-GEN-V10.BIN`, the raw form of `../Originals/IVC-GEN-V10.HEX`.
The monitor ROM is described in [../IVC-MON/README.md](../IVC-MON/README.md).

## Files

| File | Description |
|------|-------------|
| `../Originals/IVC-GEN-V10.HEX` / `.BIN` | Original image (untouched) |
| `IVC-GEN-V10.asm` | Source: 128 glyphs, 16 `defb %bbbbbbbb` lines each |
| `Makefile` | Build and diff targets |

## Building

```sh
brew install z80asm                  # macOS

make                                 # IVC-GEN-V10.bin, .lst, .sym
make diff                            # after editing: which bytes changed
```

or by hand: `z80asm -o IVC-GEN-V10.bin IVC-GEN-V10.asm`.

`diff` compares the build with `../Originals/IVC-GEN-V10.BIN` and lists every
changed byte as `offset original new` (offset is 1-based, the values are
octal). It prints nothing for an unmodified source.

## ROM layout

* 128 characters x 16 bytes = 2048 bytes. This is the lower character
  generator and serves character codes 00h-7Fh. Codes 80h-FFh come from the
  upper generator (RAM, the "PCG").
* The IVC's Z80 sees both generators as a 4 KB block at 4000h:
  the ROM is 4000h-47FFh, the PCG 4800h-4FFFh.
  Address of a glyph row = `4000h + code*16 + row`, which is also the file
  offset of the byte in the `.bin`.
* The CRTC supplies the row number on the four low address lines and the VDU
  RAM supplies the character code on the next eight.
* One byte per raster row, row 0 at the top. **Bit 7 is the left-most dot**
  and 1 is a lit dot.
* The standard screen formats use 10 rasters per character (rows 0-9). In this
  ROM the glyphs use rows 1-7 (capitals, digits) and rows 8-9 for descenders.
  Row 0 and rows 10-15 are always 0.
* Only 20h (space) is completely blank. Codes 00h-1Fh, 7Eh and 7Fh hold
  graphic symbols. Control codes are handled by the IVC and never displayed.

## Editing a glyph

Each glyph is a labelled block, for example `A`:

```
; ---- 41h  A ----
chr_41:
	defb %00000000	; row  0  ........
	defb %00011100	; row  1  ...###..
	defb %00100010	; row  2  ..#...#.
	...
```

1. Find the block by label (`chr_XX`, XX = hex code).
2. Change the binary literals. The comment is only a picture of the same
   bits (`#` = dot) and is not used by the assembler, so update it by hand
   if you want it to stay correct.
3. Keep exactly 16 `defb` lines per glyph. An overflow past 2048 bytes
   makes the build fail (guard at the end of the file), but a missing row
   would silently shift every later glyph, so check with
   `make diff` that only the bytes you meant to change differ.
4. Rebuild and burn `IVC-GEN-V10.bin` into a 2716 for IC20.

## Changing characters at run time instead

The upper generator is RAM, so no EPROM is needed for characters 80h-FFh. The
host can send them over the normal IVC data port:

* `ESC C code r0..r15` defines one character (all 16 rows must be sent; a code
  with the MSB set loads the lower generator if that is also RAM).
* `ESC c g <2048 bytes>` loads a whole set (g = 0 upper, non-zero lower).
* `ESC h` / `ESC H` copy the lower set (plain / complemented) into the upper
  set, after which single characters can be modified and `ESC A` makes the
  upper set the default.
* `ESC G` builds the 2x3 block graphics in C0h-FFh.

The row format of `ESC C` is the same as in this file.
