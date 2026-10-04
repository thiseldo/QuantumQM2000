# Quantum QM2000 GM813 ROM disassembly

Disassembly of the QM2000 monitor / boot ROM, version 2.1 (`QM-MON-V21`).
The ROM identifies itself with the string `(C) dci software 22-07-82`.

The Z80 source in [QM-Mon-V21.asm](QM-Mon-V21.asm) assembles back to a
binary that is **byte-for-byte identical** to the original image.

## Files

| File | Description |
|------|-------------|
| `QM-MON-V21-ORIGINAL.HEX` | Original ROM image, Intel HEX (2 KB, record addresses start at 0000h) |
| `QM-MON-V21-ORIGINAL.BIN` | The same image as raw binary (2048 bytes) |
| `QM-Mon-V21.asm` | Disassembled, re-assemblable Z80 source |

## Assembling

The source uses the syntax understood by [z80asm](https://savannah.nongnu.org/projects/z80asm/)
(the one packaged by Homebrew and most Linux distributions).

```sh
# macOS
brew install z80asm

# assemble (also writes QM-MON-V21.lst and QM-MON-V21.sym)
make

# or by hand
z80asm -o QM-MON-V21.bin QM-Mon-V21.asm

# verify against the original image (prints nothing and returns 0 if identical)
cmp QM-MON-V21.bin QM-MON-V21-ORIGINAL.BIN
```

The source starts with `org 0f000h` and ends with `defs 0f800h-$,0ffh`,
so the output is always exactly 2048 bytes, padded with FFh like the original.

## How the disassembly was produced

1. **Convert HEX to binary.** The Intel HEX file contains 2 KB of data from
   address 0000h plus an extended-address record; it was converted to
   `QM-MON-V21-ORIGINAL.BIN`.
2. **Find the load address.** The image begins with a table of `jp` instructions
   (`C3 2E F0`, `C3 E5 F3`, ...), all targeting F0xx-F3xx. The ROM therefore
   runs at **F000h** and the disassembly uses `-g 0xF000`.
3. **Separate code from data.** A straight linear disassembly turns the text
   strings into nonsense instructions. A small recursive-descent tracer
   followed every `jp`, `call`, `jr`, `djnz` and `ret` starting from the
   vector table and the entry point (F02Eh). Bytes it never reached were
   inspected by hand:
   * F015h-F02Dh, F076h-F090h, F097h-F0AAh, F0B1h-F0E2h, F0FFh-F12Ah,
     F16Ch-F1A4h, F226h-F241h, F28Ch-F295h, F42Dh-F464h are ASCII text
     (with embedded terminal escape codes) and are emitted as `defb "..."`.
   * F215h-F217h is a 3-byte string (`ESC '*' NUL`).
   * F296h-F2A8h is a small hex-digit routine that is not called from anywhere
     (it is an unreferenced copy of the tail of `get_hex_digit`) and is kept as code.
   * F465h-F7FFh is FFh padding.
4. **Disassemble.** Using [z80dasm](https://www.tablix.org/~avian/blog/articles/z80dasm/)
   with a block-definition file describing the code/data split:

   ```sh
   brew install z80dasm
   z80dasm -a -l -g 0xF000 -b blocks.txt rom.bin -o out.asm
   ```

   (`-a` shows addresses in comments, `-l` generates labels.)
5. **Tidy up.** A script merged consecutive `defb` lines into readable
   strings, replaced one false label (the constant `0F0FEh` loaded into BC at
   F032h was mistaken for an address), appended the `defs` padding and a
   header comment.
6. **Name the routines.** Auto-generated labels (`lf3e8h`, `sub_f2a9h`, ...)
   were renamed for the ones whose purpose is clear. Remaining `lXXXXh`
   labels are local branch targets.
7. **Verify.** The result was assembled with `z80asm` and compared with
   `cmp` against the original binary.

## Hardware: ports and memory mapping

Port names and the memory-map description come from the comments in
`simon31mp.asm`, a later version of this monitor (see [diffs.txt](diffs.txt)).
They agree with what this ROM does. Only the ports used by V2.1 are marked in
the "Used by V2.1" column.

### I/O ports (GM811/GM813 CPU board and plug-in boards)

| Port | Name | Device | Used by V2.1 |
|------|------|--------|--------------|
| `B0h` | `KBD` | Keyboard (GM811 only) | no |
| `B1h` | `IVCDAT` | IVC (video/keyboard board) data, read/write. Console output and input | yes |
| `B2h` | `IVCSTA` | IVC status, read-only. Bit 0 set = busy, cannot accept a byte. Bit 7 set = no byte to read | yes |
| `B3h` | `IVCRST` | IVC reset. Reading it resets the IVC | yes (cold start) |
| `B4h`-`B7h` | `PIOADAT`, `PIOBDAT`, `PIOACTL`, `PIOBCTL` | Z80 PIO | no |
| `B8h`-`BFh` | `UARTDAT` .. `UARTMS` | 8250 UART (serial console in later ROMs) | no |
| `E0h` | `FDCCMD` / `FDCSTA` | GM829 floppy disc controller (FD1797 chip) command (write) / status (read) | yes |
| `E1h` | `FDCTRK` | FD1797 track register | no |
| `E2h` | `FDCSEC` | FD1797 sector register | yes (set to 0 for the boot sector) |
| `E3h` | `FDCDAT` | FD1797 data register | yes |
| `E4h` | `FDCDRV` | GM829 card drive-select port. Reading it is used as the data-request poll (`in a,(c)` / `jr z` loops until non-zero); the sign bit is tested while draining the sector | yes |
| `E5h` | `SCSCTL` | SCSI control lines (GM849 board only) | no |
| `E6h` | `SCSDAT` | SCSI data (GM849 board only) | no |
| `FEh` | `MMAP` | Memory mapper (GM813 only) | yes |
| `FFh` | `PMOD` | Page mode (GM813 only) | yes |

The 8250 UART registers are `B8h` data / divisor low, `B9h` interrupt enable /
divisor high, `BAh` interrupt ID, `BBh` line control, `BCh` modem control,
`BDh` line status and `BEh` modem status. V2.1 does not touch them.

### Memory mapper and ROM decoding

* After reset the ROM is decoded at address 0000h **and** throughout the whole
  address map. This is why the first instruction of the jump table is a `jp`
  to F0xxh: the CPU starts executing at 0000h but must move into the F000h
  copy of the ROM before the mapping changes.
* The first write to port `FFh` (`PMOD`) switches the ROM to be decoded only at
  F000h-FFFFh. V2.1 does this at F043h, after the mapper has been set up.
* The ROM can also be disabled completely by setting bit 3 of the UART modem
  control port `BCh`. V2.1 does not use this.
* Start-up loop (F032h-F041h): `ld bc,0F0FEh`, then `out (c),e` with
  `E` counting 0Fh down to 0 while `B` counts F0h down to 00h in steps of 10h,
  repeated 64 times. (This part is my interpretation.) Because `B` supplies address lines A15-A8 during an
  `out (c),e`, the mapper uses the top four address bits (A15-A12) to select one
  of sixteen 4 KB pages. This loop writes value `E` for each page, so logical
  page `B>>4` is set to physical page `E` (logical F000h = page 0Fh,
  logical 0000h = page 00h, and so on). The result is an identity (1:1) map.
  (The outer loop count of 40h repeats the same writes; its purpose is not clear.)
* `out (0FFh),11h` then sets the page-mode register.

### RAM use

* The stack is placed at 0100h (later ROMs use 00FEh and keep 00FEh-00FFh as a
  workspace).
* The boot sector is read to 0000h-007Fh and the ROM jumps to `BOOTGO` = 0002h
  if its first word is `4747h` ("GG"). The two signature bytes are therefore
  the first two bytes of a boot sector, and boot code starts at offset 2.
* Monitor commands use no fixed variables.

### Console

The console is the IVC board, a terminal driven with escape sequences.
`ESC E` is probably clear screen, `ESC A` / `ESC N` appear to switch
highlighting on/off, `ESC k` / `ESC K` are used for keyboard status / read
(the IVC is sent the escape and then returns a byte), and `ESC v` asks the IVC
for its version. The meaning of `ESC D`, `1Ah` and `1Eh` has not been confirmed
(SIMON uses `1Ah` as "home/clear screen"). `ESC *` is used to erase to the end of the line.

## Memory map of the ROM

| Address | Contents |
|---------|----------|
| F000h-F014h | Jump table (see below) |
| F015h-F02Dh | Copyright string |
| F02Eh | Cold start / boot code |
| F076h-F1A4h | Boot error messages and boot-retry logic |
| F1A5h-F225h | Floppy disk routines |
| F226h-F2A8h | Monitor entry, command dispatcher, messages |
| F2A9h-F3E4h | Monitor utilities and commands |
| F3E5h-F42Ch | Console I/O |
| F42Dh-F464h | Sign-on banner |
| F465h-F7FFh | Unused (FFh) |

### Jump table (entry points for other software)

| Address | Jumps to | Function |
|---------|----------|----------|
| F000h | `cold_start` | Restart / boot |
| F003h | `conin_echo` | Read a character (upper-cased) and echo it, returns in A |
| F006h | `conout` | Print character in A (CR is sent as CR LF) |
| F009h | `print_a` | Print A as two hex digits |
| F00Ch | `print_hl` | Print HL as four hex digits |
| F00Fh | `print_space` | Print a space |
| F012h | `print_cr` | Print CR LF |

## Start-up and boot sequence (F02Eh)

1. `cold_start` reads `IVCRST` (B3h) to reset the IVC, then loops 64 times
   writing 16 values through the memory mapper `MMAP` (BC = F0FEh down to
   00FEh), then writes 11h to the page-mode port `PMOD` (FFh) and sets
   `SP` to 0100h.
2. It sends `ESC v` repeatedly until the IVC answers (a 65536-count
   timeout loop on `IVCSTA`), then prints the sign-on banner
   `**** Quantum QM2000 ****`.
3. The `I` register is used as a "system already loaded" flag. If it is zero
   the ROM goes to `boot_retry` and tries to boot; if not, it reports
   `*READ ERROR* during System load`. `I` is cleared again on entering the monitor
   (`monitor_start`) and set to FFh here.
4. `boot_retry` waits for the drive to be ready (`wait_disk_ready`). If not
   ready it prompts `Insert Disk in drive A` and waits (`boot_prompt`).
5. The controller is restored/stepped (commands 5Bh and 0Bh via `fdc_command`),
   then `read_boot_sector` reads 128 bytes (`B = 80h`) from `FDCDAT` to address 0000h.
6. On a read error it prints `***READ ERROR***` with the stage
   (`while loading Boot sector` or `during System load`) and
   `- Press any key to repeat`.
7. If the first word of the sector is `4747h` it runs `jp 0002h`; otherwise it
   prints `***No QM2000 CP/M system on this Disk***` and waits for a key press
   (pressing key code 13h, Ctrl-S, at a prompt drops into the monitor instead).

## The "SImple MONitor"

Entered from the boot prompt by pressing the abort key (`check_abort`
→ `monitor_start`). It prints a `>` prompt, reads a single letter and
dispatches it. Arguments are hexadecimal, separated by spaces, and the
last one is terminated with Return. Any error prints `-What?`.

| Command | Syntax | Action |
|---------|--------|--------|
| `B` | `B` | Boot: restart at `cold_start` |
| `C` | `C src dst count` | Copy `count` bytes from `src` to `dst` (`ldir`) |
| `E` | `E addr` | Execute: jump to `addr` |
| `F` | `F start end value` | Fill memory from `start` with `value` for `end-start+1` bytes |
| `M` | `M addr` | Examine / modify memory (see below) |
| `O` | `O port value` | Output `value` to I/O `port` |
| `Q` | `Q port` | Query: read I/O `port` and print the result |
| `T` | `T addr lines` | Type: hex dump of `lines` lines of 16 bytes, with a `-` after the eighth byte |

`M` shows the address, a `-`, the current byte and waits for input:

* hex digits then space or Return: store the byte and show the next address
* Return alone: leave the byte unchanged and show the next address
* `-`: go back to the previous address
* any other key: leave the command and return to the `>` prompt

Written values are read back and compared; a mismatch (for example writing to ROM)
prints `-What?`.

## Routine reference

| Label | Address | Purpose |
|-------|---------|---------|
| `cold_start` | F02Eh | Hardware init and boot |
| `sign_on_msg` | F42Dh | Banner text |
| `boot_retry` | F13Ch | Check drive ready, then read the boot sector |
| `boot_prompt` | F12Bh | Prompt to insert a disk |
| `boot_error`, `system_error` | F091h, F0ABh | Choose the error message suffix |
| `show_read_error` | F0E3h | Print `***READ ERROR***` + suffix + retry text |
| `read_boot_sector` | F1A5h | Read 128 bytes from the floppy to 0000h |
| `wait_disk_ready` | F1D1h | Issue a force-interrupt and wait for the drive; returns flags |
| `check_abort_msg`, `check_abort` | F1F9h, F1FFh | Check the keyboard; the abort key enters the monitor |
| `fdc_command` | F218h | Send a command to the FD1797 (`FDCCMD`) and wait for its busy bit to clear |
| `monitor_start` | F242h | Print the banner, clear `I`, fall into the loop |
| `monitor_loop` | F24Dh | Prompt `>`, read a command letter and dispatch |
| `what_error` | F287h | Print `-What?` |
| `print_str` | F2A9h | Print the zero-terminated string at HL |
| `print_hl`, `print_a`, `print_nibble` | F2B2h, F2B7h, F2C0h | Hex output |
| `print_cr`, `print_space` | F2CBh, F2D0h | Output CR LF / space |
| `get_hex_digit` | F2D5h | Read a key, return 0-F in A with carry clear |
| `get_hex_word` | F2EBh | Read a hex number into HL; skips leading spaces; carry set on error |
| `get_arg` | F310h | Read an argument that must end with a space |
| `get_last_arg` | F31Ch | Read an argument that must end with Return |
| `cmd_copy` .. `cmd_dump` | F326h-F3B9h | The monitor commands |
| `conin_echo` | F3E5h | Read a character, echo it |
| `conout` | F3E8h | Print A, turning CR into CR LF |
| `conout_raw` | F3F7h | Wait for the IVC to be ready (`IVCSTA`), then send A on `IVCDAT` |
| `kbd_status` | F401h | Send `ESC k` and read the reply (zero if no key waiting) |
| `kbd_get` | F40Fh | Send `ESC K`, read the key and fold lower case to upper case |
| `uart_read` | F425h | Wait for a character from the IVC (`IVCSTA` / `IVCDAT`) |

## Notes

* Behaviour descriptions were derived by reading the code, not by running it on
  the hardware, so port functions and the `I` register usage are best-effort interpretations.
* Auto-generated `lXXXXh` labels have the address in the name, so they remain
  valid even if the surrounding code is edited.
