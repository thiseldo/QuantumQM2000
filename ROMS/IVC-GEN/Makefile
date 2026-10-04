# Build the Gemini G812 IVC character generator ROM (IVC-GEN-V10) with z80asm
#   make          - assemble image, listing, labels
#   make diff     - list the bytes that differ from the original image
#                   (use after editing glyphs; needs ../Originals/IVC-GEN-V10.BIN)
#   make clean    - remove generated files

ASM      = z80asm
SRC      = IVC-GEN-V10.asm
ROM      = IVC-GEN-V10.bin
LST      = IVC-GEN-V10.lst
LABELS   = IVC-GEN-V10.sym
ORIGINAL = ../Originals/IVC-GEN-V10.BIN

all: $(ROM)

$(ROM) $(LST) $(LABELS): $(SRC)
	$(ASM) --list=$(LST) --label=$(LABELS) -o $(ROM) $(SRC)

# offset (decimal, 1-based), then original and new byte in octal
diff: $(ROM)
	cmp -l $(ORIGINAL) $(ROM) || true

clean:
	rm -f $(ROM) $(LST) $(LABELS)

.PHONY: all diff clean
