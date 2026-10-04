# Gemini GM812 IVC ROMs

Disassembly of the two EPROM images of the Gemini G812 Intelligent Video
Controller (IVC), taken from
<https://nascom.wordpress.com/gemini/hardware/g812-ivc/>.

References used (scanned PDFs, read by OCR and checked by eye where it mattered):

* [GM812 hardware manual](https://nascom.wordpress.com/wp-content/uploads/2017/06/gm812-ivc-hardware-manual.pdf)
* [GM812 software manual, issue 2, 14-11-82](https://nascom.wordpress.com/wp-content/uploads/2017/06/gm812-ivc-software-manual.pdf)

Both sources assemble back to **byte-for-byte identical** images.

## Files

| File | Description |
|------|-------------|
| `../Originals/IVC-MON-V20.HEX` / `.BIN` | Monitor program, V2.0, 4096 bytes (untouched) |
| `../Originals/IVC-GEN-V10.HEX` | Character generator, V1.0, 2048 bytes (untouched) |
| `IVC-MON-V20.asm` | Annotated Z80 source of the monitor |
| `../IVC-GEN/IVC-GEN-V10.asm` | Source of the character generator, see `../IVC-GEN` |
| `Makefile` | Builds the monitor |

(`../Originals/QM-MON-V21.HEX` belongs to the QM2000 CPU board, see `../QM-MON`.)

## Building

```sh
brew install z80asm            # macOS

make                           # IVC-MON-V20.bin, .lst, .sym
```

To compare a build with the original, run `cmp IVC-MON-V20.bin ../Originals/IVC-MON-V20.BIN`.

## The G812 in brief

The card has its own Z80A (4 MHz), a 6845 CRTC, 2K VDU RAM, two 2K character
generators, a 2K work RAM and a keyboard port. It talks to the host through
three I/O ports: B1h data, B2h status (bit 0 = write buffer full, bit 7 = read
buffer empty), B3h reset. Everything the host sends is interpreted by the
monitor ROM: printable characters go to the screen, control codes and `ESC`
sequences control it.

| Z80 address | Function |
|-------------|----------|
| 0000-0FFF | Monitor EPROM IC18 (2732; 0C00-0FFF unused = FFh) |
| 2000-27FF | VDU RAM |
| 4000-47FF | Lower character generator (EPROM IC20, codes 00-7F): **IVC-GEN** |
| 4800-4FFF | Upper character generator (RAM IC24, "PCG", codes 80-FF) |
| 6000 | Status port, read |
| 8000 | Keyboard port |
| A000 | Host data port |
| C000 | Control port, write (b0 display on, b1 crystal dot clock, b2 invert, b3 CRTC reset) |
| E000-E7FF | Work RAM |
| I/O 00h/01h | CRTC address / data |

Work RAM: E000-E03F input ring, E0C0 user format, E0CD (IY) variables,
E100 scratch, E200-E3FF function key table (512 bytes), E400-E7FF user program.

## IVC-MON-V20 (monitor)

Layout of the 3 KB that is in use:

| Address | Contents |
|---------|----------|
| 0000-0058 | Reset, RST 08h-30h service routines, host input ring |
| 0066 | NMI (once per frame): cursor registers, keyboard scan |
| 0097-0148 | Block load from host and synchronised block copy routines |
| 014F-01FC | Banner, init, main loop |
| 01E9-0421 | Character output, control codes, cursor movement, scrolling |
| 039F-0420 | ESC dispatcher and tables |
| 0421-0700 | ESC command handlers (cursor, formats, character set, block graphics) |
| 0701-07D2 | ESC `Z ? k K X P v` and the table-jump routine |
| 07D3-08FD | Keyboard scanner and function key expansion, `ESC f` |
| 08FE-0B2B | Messages, List/Edit function key editor |
| 0B2C-0BFF | Default function key table (GM827 keyboard) |

The RST routines match Appendix 1 of the software manual: RST 08h PUTSCR,
10h GETSCR, 18h SCAN, 20h GETCHR, 30h PUTCHR. The documented workspace
locations E0D6 (start of display), E0DC (cursor), E0E0 (width), E0E2 (height)
and the user program area E400-E7FF (called by `ESC U`, pre-loaded with a
`RET`) are as found in the code. Reading the code gave the remaining RAM names.

### Control codes and ESC commands cross-checked with the manual

Each handler was traced in the disassembly and compared with section 5 of the
software manual.

| Code | Manual | ROM handler | Result |
|------|--------|-------------|--------|
| 07 | Bell, port bit 4 set then cleared | `ctl_bell` toggles bit 4 twice | OK |
| 08 | Destructive backspace, no effect at home | `ctl_bs` | OK |
| 0A | Line feed, scrolls at the bottom | `ctl_lf` | OK |
| 0B | Delete line, scroll up | `del_line` | OK |
| 0D | Carriage return | `ctl_cr` | OK |
| 0E | Insert line | `ins_line` | OK |
| 16 / 17 | Delete / insert character in line | `del_char` / `ins_char` | OK |
| 1A | Home and clear (honours memory lock) | `cls` | OK |
| 1C-1F | Cursor left / right / up / down | `cur_left`, `cur_right`, `cur_up`, `cur_down` | OK |
| ESC 16 / 17 | Delete / insert character in screen | `esc_del_scr`, `esc_ins_scr` | OK |
| ESC % / * | Delete to end of screen / line | `esc_clr_eos`, `esc_clr_eol` | OK |
| ESC 1 / 2 / 3 | 80 wide / 48 wide / user format | `esc_fmt80/48/user` | OK |
| ESC = r c | Cursor address (offset 20h; bad values ignored) | `esc_goto` | OK |
| ESC ? | Row, column, character | `esc_where` | OK |
| ESC A / N | Alternate / normal c/gen default (MSB complemented) | `esc_alt_cg`, `esc_norm_cg` (XOR mask at iy+2) | OK |
| ESC B / V | Blank / unblank video | clears / sets control bit 0 | OK |
| ESC C | Define char, 16 rows, MSB of code selects lower c/gen | `esc_def_char` | OK |
| ESC c g | Load char set, g=0 upper | `esc_def_cset` | OK |
| ESC D / E | Cursor off / on | `esc_cur_off/on` (mask at iy+3) | OK |
| ESC F | 12 CRTC bytes + clock byte, applied by ESC 3 | `esc_def_fmt` stores 13 bytes | OK |
| ESC G | Block graphics in C0-FF | `esc_graphics` builds 4C00-4FFF | OK |
| ESC h / H | Copy lower to upper c/gen (H complemented) | `esc_cg_copy`, `esc_cg_inv` | OK |
| ESC I / J | Invert / normal video | clears / sets control bit 2 | OK, see note 2 |
| ESC K / k | Keyboard char / status (00 or FF) | `esc_kb_get`, `esc_kb_status` | OK |
| ESC L / U | Load / execute user program at E400 | `esc_load` (max 400h bytes), `USERPROG` | OK |
| ESC M / O | Memory lock on / off | `esc_lock_on/off` | OK |
| ESC P | Light pen row, column | `esc_lightpen` | OK |
| ESC R / S / T | Reset / set / test point; T returns 0, 1 or 2 (illegal) | `esc_preset/pset/ptest` | OK |
| ESC W | High speed write, `t`/`T` = transparent | `esc_hswrite` | OK |
| ESC X | Keyboard line input, CR if keyboard disabled | `esc_kb_line` | OK |
| ESC Y a b | CRTC registers 10 and 11 | `esc_cur_type` | OK |
| ESC Z | Return line, trailing blanks removed, CR | `esc_getline` | OK |
| ESC v | Version, 20h | `esc_version` | OK |
| ESC f ... | Define / `d` `D` reset / `?` list function keys | `esc_fkey` | OK, see note 4 |
| ESC ESC | Nested escape, depth 4 | `esc_esc` checks stack depth | OK |

### Differences between the ROM and the manual

1. **CRTC tables.** Appendix 2 lists register 4 (vertical total) as 1Eh for both
   formats and register 2 of the 48 wide format as 3Ch. The ROM holds **5Eh** in
   both tables for register 4 and **3Eh** for register 2 of the 48 wide format
   (`fmt80` at 057D, `fmt48` at 058A). 1Eh with 10 rasters + 2 adjust gives 312
   lines (50 Hz), whereas 5Eh would give 952. Everything else in both tables
   matches. This may be a typographical difference or a bit error in this
   EPROM image. Reading the chip again would settle it.
2. **Invert polarity.** The hardware manual says control port bit 2 high inverts
   the picture. The software powers up with bit 2 high and `ESC I` (invert)
   clears it, `ESC J` (normal) sets it. Either the hardware text has the
   polarity reversed or the video path adds an inversion.
3. **Messages.** The manual quotes "Function key undefined" and "IVC internal
   error - table overflow". The ROM text is "Key is undefined" and
   "IVC Internal error *** - programmable key buffer overflow".
4. **`ESC f` key codes.** The manual says 9Bh (shift/EDIT) is illegal in a
   definition. The ROM accepts it (it rejects 80h, 90h and codes above BDh).

### Other findings

* Byte 0006h selects the power-up format (00 = 80 wide) and 0007h is a zero
  byte used as a "never busy" flag. Neither is described in the manual (it
  only documents changing the default function keys).
* The default key table starts at 0B2Ch, immediately after the copyright text
  "(C) dci software 1982" whose last byte is shared with the first table entry
  (80h). This agrees with Appendix 4 ("80 1B 90 1B ...").
* The ROM jumps into the middle of two instructions: `esc_del_scr` enters
  `del_char` two bytes in (skipping its `LD HL,(line_end)`), and the carry
  branch in `esc_ptest` lands inside an `LD HL,nn`. Both are reproduced as
  `defb` plus a label.
* 0059-0065 are 13 unreferenced bytes that do not make sense as code.

## IVC-GEN-V10 (character generator)

* 128 characters x 16 bytes = 2048 bytes = the lower generator for codes
  00h-7Fh. Address in the Z80 map = 4000h + code*16 + row.
* One byte per raster row, row 0 at the top. **Bit 7 is the left-most dot**
  (the 74LS165 shifts out MSB first), a 1 is a lit dot.
* The standard screen uses 10 rasters (rows 0-9). In this ROM glyphs use rows
  1-7 (capitals, digits) plus descenders in rows 8-9. Row 0 and rows 10-15 are
  always zero.
* Only 20h (space) is blank. Codes 00h-1Fh, 7Eh and 7Fh hold graphic
  symbols, not control-code glyphs (control codes never reach the display).
* The upper 128 characters come from the RAM generator, which the host fills
  with `ESC C` (one character, 16 rows, code with MSB set for the lower
  generator) or `ESC c` (a whole 2048 byte set). `ESC G` fills C0h-FFh
  with 2x3 block graphics, `ESC h` / `ESC H` copy the lower set to the upper set
  (plain / complemented).

To change a glyph, edit its 16 `defb` lines in `IVC-GEN-V10.asm` and rebuild.
The run-time route is `ESC C` from a host program.
