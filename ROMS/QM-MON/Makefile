# Build the QM2000 monitor ROM (QM-MON-V21) with z80asm
#   make        - assemble ROM image and listing
#   make clean  - remove generated files

ASM      = z80asm
SRC      = QM-Mon-V21.asm
ROM      = QM-MON-V21.bin
LST      = QM-MON-V21.lst
LABELS   = QM-MON-V21.sym

all: $(ROM) $(LST)

# one assembler run produces the image, the listing and the label file
$(ROM) $(LST) $(LABELS): $(SRC)
	$(ASM) --list=$(LST) --label=$(LABELS) -o $(ROM) $(SRC)

clean:
	rm -f $(ROM) $(LST) $(LABELS)

.PHONY: all clean
