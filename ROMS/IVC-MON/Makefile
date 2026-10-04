# Build the Gemini G812 IVC monitor ROM (IVC-MON-V20) with z80asm
#   make          - assemble image, listing, labels
#   make clean    - remove generated files

SRC = IVC-MON-V20.asm
ROM = IVC-MON-V20.bin
LST = IVC-MON-V20.lst
LABELS = IVC-MON-V20.sym

all: $(ROM)

$(ROM) $(LST) $(LABELS): $(SRC)
	z80asm --list=$(LST) --label=$(LABELS) -o $(ROM) $(SRC)

clean:
	rm -f $(ROM) $(LST) $(LABELS)

.PHONY: all clean
