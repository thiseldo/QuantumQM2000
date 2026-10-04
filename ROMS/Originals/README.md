# Originals

The ROM images as received. They are the reference for the disassemblies in the
sibling folders and must not be edited. Each image is supplied twice, as Intel
HEX and as raw binary, and the two forms contain identical data.

| Image | Size | Board / use | Disassembly |
|-------|------|-------------|-------------|
| `QM-MON-V21.HEX` / `.BIN` | 2048 bytes | QM2000 GM813 CPU board: monitor / boot ROM V2.1, mapped at F000h | [../QM-MON](../QM-MON/) |
| `IVC-MON-V20.HEX` / `.BIN` | 4096 bytes | GM812 IVC video board: monitor program V2.0 (2732, IC18), runs from 0000h | [../IVC-MON](../IVC-MON/) |
| `IVC-GEN-V10.HEX` / `.BIN` | 2048 bytes | GM812 IVC video board: lower character generator V1.0 (2716, IC20), 128 glyphs x 16 rows | [../IVC-GEN](../IVC-GEN/) |

## Files

| File | Bytes | Format |
|------|------:|--------|
| `IVC-GEN-V10.HEX` | 5790 | Intel HEX |
| `IVC-GEN-V10.BIN` | 2048 | raw binary |
| `IVC-MON-V20.HEX` | 11550 | Intel HEX |
| `IVC-MON-V20.BIN` | 4096 | raw binary |
| `QM-MON-V21.HEX` | 5790 | Intel HEX |
| `QM-MON-V21.BIN` | 2048 | raw binary |

## Format

* Each HEX file starts with an extended linear address record
  (`:020000040000FA`), then 16-byte data records addressed from 0000h with no
  gaps, and ends with `:00000001FF`. Unused space is filled with FFh.
* The `.BIN` files are the data records in address order, starting at offset 0.
  The HEX files carry no load address, so the real mapping comes from the
  code (QM-MON at F000h, IVC-MON and IVC-GEN as described in their READMEs).

## Checksums (raw binary, MD5)

| Image | MD5 |
|-------|-----|
| `IVC-GEN-V10.BIN` | `7b67e595768b237a3f59f19f6f49b75a` |
| `IVC-MON-V20.BIN` | `1466970d92a2606cf786ed5c33c49cda` |
| `QM-MON-V21.BIN` | `33a198776bc14948ba72e639a903a0dd` |

Check with `md5 -q *.BIN` (macOS) or `md5sum *.BIN` (Linux).

## Converting HEX to binary

```sh
objcopy -I ihex -O binary IVC-MON-V20.HEX IVC-MON-V20.BIN     # GNU binutils
srec_cat IVC-MON-V20.HEX -intel -o IVC-MON-V20.BIN -binary    # SRecord
```

