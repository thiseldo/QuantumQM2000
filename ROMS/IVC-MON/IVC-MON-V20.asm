; Gemini GM812 IVC (Intelligent Video Controller) monitor ROM  IVC-MON V2.0
; Disassembled from Originals/IVC-MON-V20.BIN / .HEX  (4096 bytes)
;
; The G812 has its own Z80A (4 MHz) that drives a 6845 CRTC, the VDU RAM,
; the character generators, an ASCII keyboard port and the host interface.
; The host talks to it through three I/O ports (data B1h, status B2h, reset
; B3h) using the ESC command set of the GM812 software manual.
;
; Z80 memory map (hardware manual 1.3):
;   0000-0FFF  this program (2732; 0C00-0FFF is unused, FFh)
;   2000-27FF  VDU RAM         4000-47FF  lower c/gen (EPROM, see IVC-GEN-V10)
;   4800-4FFF  upper c/gen RAM (PCG)      6000  status port (read)
;   8000       keyboard port   A000       data port to/from host
;   C000       status port (write)        E000-E7FF  Z80 RAM
; Z80 I/O:  00h = CRTC address register, 01h = CRTC data register
;
; Z80 RAM use:
;   E000-E03F  64 byte input ring (host bytes, and keyboard characters)
;   E0C0-E0CC  user screen format (ESC F)      E0CD  flag/variable block (IY)
;   E100-E10F  CRTC register staging           E100-E1FF/E200  scratch & fn keys
;   E200-E3FF  function key table (up to E400) E400-E7FF  user program (ESC L)
;   E080       top of stack
;
; Register conventions: IY = E0CDh throughout.  The alternate register set is
; reserved for the host input ring:  BC' = read ptr, DE' = write ptr,
; HL' = 6000h (status port).  RST 08h..30h are the fast service routines:
;   RST 08h  vdu_write   store A at (DE) in VDU RAM (sync'd to H sync)
;   RST 10h  vdu_read    A = (DE) from VDU RAM
;   RST 18h  poll_host   move a waiting host byte into the input ring
;   RST 20h  getc        A = next byte from the host (or keyboard)
;   RST 30h  putc        send A to the host
;
; Screen layout: the screen occupies the top of VDU RAM ending at 2800h
; (scr_top = 2800h - cols*rows).  cursor/line_start/line_end/scr_top/
; lock_top are absolute VDU RAM addresses.
;
; Assemble with z80asm:   z80asm -o IVC-MON-V20.bin IVC-MON-V20.asm
;   verify with:          cmp IVC-MON-V20.bin Originals/IVC-MON-V20.BIN
;

; ---- Hardware ----
CRTC_ADR:	equ 000h	; 6845 address register (I/O)
CRTC_DAT:	equ 001h	; 6845 data register (I/O)
VDURAM:		equ 02000h	; VDU RAM (2K)
VDUEND:		equ 02800h
CGLOW:		equ 04000h	; lower character generator (codes 00-7F)
CGHIGH:		equ 04800h	; upper character generator = PCG RAM (80-FF)
STATUS_R:	equ 06000h	; b0 host wrote, b1 VSYNC, b2 HSYNC, b3 display enable,
				; b4 light pen, b5 link 2, b6 link 3, b7 host read
KBDPORT:	equ 08000h	; keyboard (b7 = strobe, b0-b6 = ASCII)
DATAPORT:	equ 0a000h	; data port to/from host
STATUS_W:	equ 0c000h	; b0 display on, b1 crystal dot clock, b2 invert, b3 CRTC reset

; ---- Z80 RAM ----
inbuf:		equ 0e000h	; input ring (64 bytes)
STACK:		equ 0e080h
user_fmt:	equ 0e0c0h	; 13 byte user screen format
iyflags:	equ 0e0cdh	; IY points here
V_MODE:		equ 0		; (iy+0) b0 = keyboard line input, b1 = invert copy
ctrl_shadow:	equ 0e0ceh	; (iy+1) copy of STATUS_W
V_CGXOR:	equ 2		; (iy+2) XOR mask for displayed chars (80h = alternate c/gen)
V_CURMASK:	equ 3		; (iy+3) cursor mask (FFh on, 00h off)
cur_mask:	equ 0e0d0h
V_KBDLAST:	equ 4		; (iy+4) last keyboard port value
kbd_last:	equ 0e0d1h
kbd_wr:		equ 0e0d2h	; keyboard ring write pointer
kbd_rd:		equ 0e0d4h	; keyboard ring read pointer
V_KBRDLO:	equ 7		; (iy+7) = low byte of kbd_rd
scr_top:	equ 0e0d6h	; address of the first screen position
lock_top:	equ 0e0d8h	; top of the scrolling area (ESC M memory lock)
line_start:	equ 0e0dah	; start of the cursor's line
cursor:		equ 0e0dch	; cursor address
line_end:	equ 0e0deh	; start of the next line
cols:		equ 0e0e0h	; characters per line  ((iy+13h))
V_COLS:		equ 013h
rows:		equ 0e0e2h	; lines on the screen  ((iy+15h))
V_ROWS:		equ 015h
kflags:		equ 0e0e4h	; function key flags ((iy+17h)); b0 ESC seen, b6 hot key,
V_KFLAGS:	equ 017h	; b7 function keys returned raw
fkeylen:	equ 0e0e5h	; length of the function key table (excl. FFh)
fkeyptr:	equ 0e0e7h	; next byte of the fn key string being returned, 0 = none
fmtbuf:		equ 0e100h	; CRTC register staging / scratch
FKEYBUF:	equ 0e200h	; function key table: key code, string bytes, ... FFh
FKEYEND:	equ 0e400h
USERPROG:	equ 0e400h	; ESC L loads here, ESC U calls it (initially a RET)

	org 0000h

; ---- Reset: the Z80 starts here ----
reset:
	ld sp,STACK		;0000
	jp init			;0003

; ---- ROM configuration bytes ----
; 0006: default screen format at reset, 00 = 80 wide, non-zero = 48 wide
;       (read by init, see 'Changing default settings' in the software manual)
; 0007: always 00 (used as a never-busy flag by load_to_ram)
cfg_format:
	defb 000h	;0006 default format: 0 = 80 wide
zero_byte:
	defb 000h	;0007 always zero

; ---- RST 08h: vdu_write: store A at (DE) in VDU RAM ----
; Waits for the start of horizontal sync (HL' = 6000h status port) so the
; Z80 access cannot disturb the display (no 'snow').  Shares code with RST 10h.
rst_vdu_write:
	scf			;0008
	jr vdu_sync		;0009
	defb 0ffh,0ffh,0ffh	;000b unused

; (entered with carry set from vdu_sync2)
vdu_store:
	ld (de),a		;000e
	ret			;000f

; ---- RST 10h: vdu_read: A = (DE) from VDU RAM, synchronised to H sync ----
rst_vdu_read:
	xor a			;0010
vdu_sync:
	exx			;0011
l0012:
	bit 2,(hl)		;0012
	jr nz,l0012		;0014
	jr vdu_sync2		;0016

; ---- RST 18h: poll the host.  If the host has written a byte (status
; bit 0) it is moved into the 64 byte input ring at E000h ----
; Shadow registers hold the ring state:  BC' = read ptr, DE' = write ptr,
; HL' = 6000h (status port).
rst_poll_host:
	exx			;0018
	bit 0,(hl)		;0019
	exx			;001b
	ret z			;001c
	jp host_take		;001d

; ---- RST 20h: getc: A = next byte sent by the host (waits for one) ----
; If the input ring is empty the host is polled; when the keyboard
; line-input mode (ESC X) is active the byte comes from kbd_getc instead.
rst_getc:
	exx			;0020
	ld a,c			;0021
	cp e			;0022
	exx			;0023
	jr z,getc_wait		;0024
	rst 18h			;0026
	exx			;0027
	ld a,(bc)		;0028
	inc c			;0029
	res 6,c			;002a
	exx			;002c
	ret			;002d
	defb 0ffh,0ffh	;002e unused

; ---- RST 30h: putc: send A to the host via the data port at A000h ----
; Waits until status bit 7 (host has read the last byte) is set.
rst_putc:
	exx			;0030
l0031:
	bit 0,(hl)		;0031
	jr nz,l0039		;0033
	bit 7,(hl)		;0035
	jr z,l0031		;0037
l0039:
	exx			;0039
	ld (DATAPORT),a		;003a
	ret			;003d
vdu_sync2:
	bit 2,(hl)		;003e
	jr z,vdu_sync2		;0040
	exx			;0042
	jp c,vdu_store		;0043
	ld a,(de)		;0046
	ret			;0047
host_take:
	exx			;0048

; store the byte just written by the host into the ring (drop it if full)
host_buffer:
	ld a,e			;0049
	inc a			;004a
	and 03fh		;004b
	cp c			;004d
	jr z,l0057		;004e
	ld a,(DATAPORT)		;0050
	ld (de),a		;0053
	inc e			;0054
	res 6,e			;0055
l0057:
	exx			;0057
	ret			;0058
; 0059-0065: 13 bytes that do not form a sensible routine (not referenced).
; Looks like left-over patch bytes; kept verbatim.
	defb 03dh,0c9h,03eh,0ffh,032h,013h,03dh,0c3h	;0059
	defb 03bh,02bh,0afh,032h,013h	;0061

; ---- NMI (vertical sync, LK4 = V sync): once per frame ----
; Copies the cursor address to CRTC regs 15/14 and scans the keyboard
; (kbd_scan) when the keyboard is enabled (link 3).
nmi:
	push af			;0066
	ld a,00fh		;0067
	out (CRTC_ADR),a		;0069
	ld a,(cursor)		;006b
	out (CRTC_DAT),a		;006e
	ld a,00eh		;0070
	out (CRTC_ADR),a		;0072
	ld a,(cursor+1)		;0074
	and (iy+V_CURMASK)		;0077
	out (CRTC_DAT),a		;007a
	ld a,(STATUS_R)		;007c
	bit 6,a			;007f
	jp z,kbd_scan		;0081
	pop af			;0084
	ret			;0085

; ring empty: keyboard mode, or wait for the host to write a byte
getc_wait:
	bit 0,(iy+V_MODE)		;0086
	jp nz,kbd_getc		;008a
	exx			;008d
l008e:
	bit 0,(hl)		;008e
	jr z,l008e		;0090
	exx			;0092
	ld a,(DATAPORT)		;0093
	ret			;0096

; ---- load_to_vdu / load_to_ram: store BC bytes from the host at (DE) ----
; HL selects the busy flag tested before each store:  6000h = VDU
; display-enable (status bit 3), 0007h = a zero ROM byte (never busy).
; Bytes already in the input ring are used first.
load_to_vdu:
	ld hl,STATUS_R		;0097
	jr l009f		;009a
load_to_ram:
	ld hl,zero_byte		;009c
l009f:
	exx			;009f
	ld a,c			;00a0
	cp e			;00a1
	jr z,l00b6		;00a2
	ld a,(bc)		;00a4
	inc c			;00a5
	res 6,c			;00a6
	exx			;00a8
l00a9:
	bit 3,(hl)		;00a9
	jr nz,l00a9		;00ab
	ld (de),a		;00ad
	inc de			;00ae
	dec bc			;00af
	ld a,b			;00b0
	or c			;00b1
	jr nz,l009f		;00b2
	ret			;00b4
l00b5:
	exx			;00b5
l00b6:
	bit 0,(hl)		;00b6
	jr z,l00b6		;00b8
	ld a,(DATAPORT)		;00ba
	exx			;00bd
l00be:
	bit 3,(hl)		;00be
	jr nz,l00be		;00c0
	ld (de),a		;00c2
	inc de			;00c3
	dec bc			;00c4
	ld a,b			;00c5
	or c			;00c6
	jp nz,l00b5		;00c7
	ret			;00ca

; ---- fill_space: fill BC bytes at DE with spaces ----
; writes one space then propagates it with copy_fwd (HL = DE, DE = DE+1)
fill_space:
	ld a,020h		;00cb
	rst 8			;00cd
	dec bc			;00ce
	ld a,b			;00cf
	or c			;00d0
	ret z			;00d1
	ld h,d			;00d2
	ld l,e			;00d3
	inc de			;00d4

; ---- copy_fwd: LDIR-like copy of BC bytes HL -> DE in VDU RAM ----
; Copies in bursts synchronised to the display (status bit 3) and polls the
; host while waiting.  Seven LDIs per display-enable window.
copy_fwd:
	exx			;00d5
l00d6:
	ld a,(hl)		;00d6
	and 00fh		;00d7
	jr z,l00d6		;00d9
	bit 3,a			;00db
	jr nz,l010c		;00dd
	bit 0,a			;00df
	jr z,l00e8		;00e1
	call host_buffer	;00e3
	jr copy_fwd		;00e6
l00e8:
	bit 3,(hl)		;00e8
	jr nz,l010c		;00ea
	exx			;00ec
	ldi			;00ed
	ret po			;00ef
	ldi			;00f0
	ret po			;00f2
	ldi			;00f3
	ret po			;00f5
	ldi			;00f6
	ret po			;00f8
	ldi			;00f9
	ret po			;00fb
	ldi			;00fc
	ret po			;00fe
l00ff:
	ldi			;00ff
	ret po			;0101
	ldi			;0102
	ret po			;0104
	rrca			;0105
	call c,host_take	;0106
	jp copy_fwd		;0109
l010c:
	bit 3,(hl)		;010c
	jr nz,l010c		;010e
	exx			;0110
	jp l00ff		;0111

; ---- copy_bwd: same as copy_fwd but backwards (LDDR-like) ----
copy_bwd:
	exx			;0114
l0115:
	ld a,(hl)		;0115
	and 00fh		;0116
	jr z,l0115		;0118
	bit 3,a			;011a
	jr nz,l0148		;011c
	bit 0,a			;011e
	jr z,l0127		;0120
	call host_buffer	;0122
	jr copy_bwd		;0125
l0127:
	nop			;0127
	bit 3,(hl)		;0128
	jr nz,l0148		;012a
	exx			;012c
	ldd			;012d
	ret po			;012f
	ldd			;0130
	ret po			;0132
	ldd			;0133
	ret po			;0135
	ldd			;0136
	ret po			;0138
	ldd			;0139
	ret po			;013b
	ldd			;013c
	ret po			;013e
l013f:
	ldd			;013f
	ret po			;0141
	ldd			;0142
	ret po			;0144
	jp copy_bwd		;0145
l0148:
	bit 3,(hl)		;0148
	jr nz,l0148		;014a
	exx			;014c
	jr l013f		;014d

; The banner is pre-loaded into the input ring so it is displayed like text
; sent by the host.
banner:
	defb "   IVC Monitor V2.0 - 1982",00dh,00ah	;014f

; ---- Initialisation (RAM clear, banner, CRTC set-up) ----
init:
	ld a,(DATAPORT)		;016b
	ld hl,iyflags		;016e
	ld b,01ch		;0171
	xor a			;0173
l0174:
	ld (hl),a		;0174
	inc hl			;0175
	djnz l0174		;0176
	ld iy,iyflags		;0178
	ld (STATUS_W),a		;017c
	dec a			;017f
	ld (cur_mask),a		;0180
	ld (ctrl_shadow),a		;0183
	ld a,0c9h		;0186
	ld (USERPROG),a		;0188
	ld a,(KBDPORT)		;018b
	ld (kbd_last),a		;018e
	ld hl,STACK		;0191
	ld (kbd_wr),hl		;0194
	ld (kbd_rd),hl		;0197
	ld bc,0001ch		;019a
	ld de,inbuf		;019d
	ld hl,banner		;01a0
	ldir			;01a3
	ld bc,inbuf		;01a5
	ld de,inbuf+1ch		;01a8
	ld hl,STATUS_R		;01ab
	exx			;01ae
	ld bc,kbd_pop_af	;01af
	ld de,02001h		;01b2
	ld hl,VDURAM		;01b5
	ld (hl),020h		;01b8
	ldir			;01ba
	ld hl,fmt80		;01bc
	ld a,(cfg_format)	;01bf
	or a			;01c2
	jr z,l01c8		;01c3
	ld hl,fmt48		;01c5
l01c8:
	ld bc,0000dh		;01c8
	ld de,user_fmt		;01cb
	ldir			;01ce
	call esc_fmt_user	;01d0
	call esc_cg_inv		;01d3
	call fkey_defaults	;01d6

; ---- Main loop: get a byte from the host (or hot key) and display it ----
main_loop:
	ld sp,STACK		;01d9
	bit 7,(iy+V_KFLAGS)		;01dc
	call nz,fkey_listedit	;01e0
	rst 20h			;01e3
	call put_char		;01e4
	jr main_loop		;01e7

; ---- put_char: display A at the cursor and advance (control codes < 20h
; are dispatched through ctl_jumps) ----
; Wraps to the next line / scrolls at the end of the screen.
put_char:
	ld de,(cursor)		;01e9
	cp 020h			;01ed
	jr c,ctl_char		;01ef
	xor (iy+V_CGXOR)		;01f1
	rst 8			;01f4
	call cur_right		;01f5
	ret nz			;01f8
	ld de,(line_start)		;01f9
put_char_wrap:
	push de			;01fd
	ld de,(lock_top)		;01fe
	ld hl,(line_start)		;0202
	or a			;0205
	sbc hl,de		;0206
	ld b,h			;0208
	ld c,l			;0209
	ld hl,(cols)		;020a
	add hl,de		;020d
	call nz,copy_fwd	;020e
	ld bc,(cols)		;0211
	ld de,(line_start)		;0215
	call fill_space		;0219
	pop de			;021c
	ld (cursor),de		;021d
	ret			;0221

; control character: look up A in ctl_codes and jump through ctl_jumps
ctl_char:
	ld bc,vdu_store		;0222
	ld hl,ctl_jumps		;0225
	jp table_jump		;0228

; ---- Control code table:  codes, then jump table in the same order ----
; 07 BEL, 08 BS, 0A LF, 0B VT delete line, 0D CR, 0E insert line, 1A clear
; screen, 1B ESC, 16 delete char, 17 insert char, 1C left, 1D right, 1E up,
; 1F down
ctl_codes:
	defb 007h,008h,00ah,00bh,00dh,00eh,01ah,01bh,016h,017h,01ch,01dh,01eh,01fh	;022b
ctl_jumps:
	defw ctl_bell	;0239 code 07h
	defw ctl_bs	;023b code 08h
	defw ctl_lf	;023d code 0Ah
	defw del_line	;023f code 0Bh
	defw ctl_cr	;0241 code 0Dh
	defw ins_line	;0243 code 0Eh
	defw cls	;0245 code 1Ah
	defw esc_cmd	;0247 code 1Bh
	defw del_char	;0249 code 16h
	defw ins_char	;024b code 17h
	defw cur_left	;024d code 1Ch
	defw cur_right	;024f code 1Dh
	defw cur_up	;0251 code 1Eh
	defw cur_down	;0253 code 1Fh

; ---- cursor movement.  DE = cursor address, HL/BC scratch.  Scrolling
; and wrap logic uses line_start/line_end/scr_top/lock_top ----
cur_right:
	ld hl,VDUEND-1		;0255
	or a			;0258
	sbc hl,de		;0259
	ret z			;025b
	inc de			;025c
	ld (cursor),de		;025d
	ld hl,(line_end)		;0261
	sbc hl,de		;0264
	ret nz			;0266
	ld (line_start),de		;0267
	ld hl,(cols)		;026b
	adc hl,de		;026e
	ld (line_end),hl		;0270
	ret			;0273
cur_left:
	ld hl,(lock_top)		;0274
	or a			;0277
	sbc hl,de		;0278
	ret z			;027a
	dec de			;027b
	ld (cursor),de		;027c
	ld hl,(line_start)		;0280
	sbc hl,de		;0283
	ret nz			;0285
	ld de,(cols)		;0286
	ld hl,(line_start)		;028a
	ld (line_end),hl		;028d
	sbc hl,de		;0290
	ld (line_start),hl		;0292
	ld de,(cursor)		;0295
	ret			;0299
cur_up:
	ld hl,(cols)		;029a
	push de			;029d
	or a			;029e
	ex de,hl		;029f
	sbc hl,de		;02a0
	ex de,hl		;02a2
	ld hl,(lock_top)		;02a3
	scf			;02a6
	sbc hl,de		;02a7
	pop hl			;02a9
	ex de,hl		;02aa
	ccf			;02ab
	ret c			;02ac
	ld (cursor),hl		;02ad
	ld hl,(line_start)		;02b0
	ld (line_end),hl		;02b3
	ld de,(cols)		;02b6
	sbc hl,de		;02ba
	ld (line_start),hl		;02bc
	ld de,(cursor)		;02bf
	ret			;02c3
cur_down:
	ld hl,(cols)		;02c4
	add hl,de		;02c7
	push de			;02c8
	ex de,hl		;02c9
	ld hl,VDUEND-1		;02ca
	or a			;02cd
	sbc hl,de		;02ce
	ex de,hl		;02d0
	pop de			;02d1
	ret c			;02d2
	ld (cursor),hl		;02d3
	ld hl,(line_end)		;02d6
	ld de,(cols)		;02d9
	ld (line_start),hl		;02dd
	add hl,de		;02e0
	ld (line_end),hl		;02e1
	ld de,(cursor)		;02e4
	ret			;02e8

; BEL: toggle bit 4 of the control port twice (a beep/click output; the
; hardware manual lists bits 4-7 as unused)
ctl_bell:
	ld a,(ctrl_shadow)		;02e9
	xor 010h		;02ec
	ld (STATUS_W),a		;02ee
	xor 010h		;02f1
	ld (STATUS_W),a		;02f3
	ret			;02f6
ctl_bs:
	call cur_left		;02f7
	ret z			;02fa
	ld a,020h		;02fb
	rst 8			;02fd
	ret			;02fe
ctl_cr:
	ld hl,(line_start)		;02ff
	ld (cursor),hl		;0302
	ret			;0305
ctl_lf:
	call cur_down		;0306
	jp c,put_char_wrap	;0309
	ret			;030c

; clear screen: blank from lock_top to end, home cursor
cls:
	ld de,(lock_top)		;030d
	ld hl,VDUEND		;0311
	or a			;0314
	sbc hl,de		;0315
	ld b,h			;0317
	ld c,l			;0318
	call fill_space		;0319
	ld hl,(lock_top)		;031c
	ld (line_start),hl		;031f
	ld (cursor),hl		;0322
	ex de,hl		;0325
	ld hl,(cols)		;0326
	add hl,de		;0329
	ld (line_end),hl		;032a
	ret			;032d
ins_char:
	ld hl,(line_end)		;032e
l0331:
	push hl			;0331
	scf			;0332
	sbc hl,de		;0333
	ld c,l			;0335
	ld b,h			;0336
	pop hl			;0337
	ret z			;0338
	dec hl			;0339
	ld d,h			;033a
	ld e,l			;033b
	dec hl			;033c
	call copy_bwd		;033d
	ld a,020h		;0340
	rst 8			;0342
	ret			;0343
del_char:
	defb 02ah		;0344 opcode of LD HL,(line_end); esc_del_scr jumps to the next byte to skip it
del_char_skip:
	sbc a,0e0h		;0345 (operand bytes of the skipped LD, harmless)
	scf			;0347
	sbc hl,de		;0348
	ld b,h			;034a
	ld c,l			;034b
	push de			;034c
	ld h,d			;034d
	ld l,e			;034e
	inc hl			;034f
	call nz,copy_fwd	;0350
	ld a,020h		;0353
	ld (de),a		;0355
	pop de			;0356
	ret			;0357
del_line:
	ld de,(line_end)		;0358
	ld hl,VDUEND		;035c
	or a			;035f
	sbc hl,de		;0360
	ld b,h			;0362
	ld c,l			;0363
	ld de,(line_start)		;0364
	ld hl,(line_end)		;0368
	call nz,copy_fwd	;036b
	ld bc,(cols)		;036e
	call fill_space		;0372
	ret			;0375
ins_line:
	ld hl,VDUEND		;0376
	ld de,(line_end)		;0379
	or a			;037d
	sbc hl,de		;037e
	ld b,h			;0380
	ld c,l			;0381
	ld hl,VDUEND-1		;0382
	ld de,(cols)		;0385
	push af			;0389
	sbc hl,de		;038a
	pop af			;038c
	ld de,VDUEND-1		;038d
	call nz,copy_bwd	;0390
	ld bc,(cols)		;0393
	ld de,(line_start)		;0397
	call fill_space		;039b
	ret			;039e

; ---- ESC: fetch the next byte and dispatch through esc_codes/esc_jumps ----
esc_cmd:
	rst 20h			;039f
	ld bc,00028h		;03a0
	ld hl,esc_jumps		;03a3
	jp table_jump		;03a6

; ---- ESC command table (40 codes) then the 40 handler addresses ----
; ESC = goto, * clear to EOL, % clear to EOS, M/O memory lock on/off,
; A/N alternate/normal c/gen, L load user prog, U run user prog,
; C define char, c define char set, F define format, B/V blank/unblank,
; D/E cursor off/on, G block graphics, h/H copy c/gen (H inverted),
; I/J screen invert/normal, k/K keyboard status/char, X line input,
; P light pen, R/S/T reset/set/test point, W high speed write,
; Y cursor type, Z return line, 1/2/3 screen format, ? where,
; ESC ESC, ESC ^V, ESC ^W screen delete/insert char, v version, f fn keys
esc_codes:
	defb "=","*","%","M","O","A","N","L","U","C","c","F","B","V","D","E","G","h","H","I","J","k","K","X","P","R","S","T","W","Y","Z","1","2","3","?",01bh,016h,017h,"v","f"	;03a9
esc_jumps:
	defw esc_goto	;03d1 ESC =
	defw esc_clr_eol	;03d3 ESC *
	defw esc_clr_eos	;03d5 ESC %
	defw esc_lock_on	;03d7 ESC M
	defw esc_lock_off	;03d9 ESC O
	defw esc_alt_cg	;03db ESC A
	defw esc_norm_cg	;03dd ESC N
	defw esc_load	;03df ESC L
	defw 0e400h	;03e1 ESC U
	defw esc_def_char	;03e3 ESC C
	defw esc_def_cset	;03e5 ESC c
	defw esc_def_fmt	;03e7 ESC F
	defw esc_blank	;03e9 ESC B
	defw esc_unblank	;03eb ESC V
	defw esc_cur_off	;03ed ESC D
	defw esc_cur_on	;03ef ESC E
	defw esc_graphics	;03f1 ESC G
	defw esc_cg_copy	;03f3 ESC h
	defw esc_cg_inv	;03f5 ESC H
	defw esc_inverse	;03f7 ESC I
	defw esc_normal	;03f9 ESC J
	defw esc_kb_status	;03fb ESC k
	defw esc_kb_get	;03fd ESC K
	defw esc_kb_line	;03ff ESC X
	defw esc_lightpen	;0401 ESC P
	defw esc_preset	;0403 ESC R
	defw esc_pset	;0405 ESC S
	defw esc_ptest	;0407 ESC T
	defw esc_hswrite	;0409 ESC W
	defw esc_cur_type	;040b ESC Y
	defw esc_getline	;040d ESC Z
	defw esc_fmt80	;040f ESC 1
	defw esc_fmt48	;0411 ESC 2
	defw esc_fmt_user	;0413 ESC 3
	defw esc_where	;0415 ESC ?
	defw esc_esc	;0417 ESC 1Bh
	defw esc_del_scr	;0419 ESC 16h
	defw esc_ins_scr	;041b ESC 17h
	defw esc_version	;041d ESC v
	defw esc_fkey	;041f ESC f
esc_ins_scr:
	ld hl,VDUEND		;0421
	jp l0331		;0424
esc_del_scr:
	ld hl,VDUEND		;0427
	jp del_char_skip	;042a

; ESC ESC: if the stack is already deep (nested escape) restart ESC handling
esc_esc:
	ld hl,STACK-1fh		;042d
	or a			;0430
	sbc hl,sp		;0431
	call c,esc_cmd		;0433
	ld de,(cursor)		;0436
	jp esc_cmd		;043a

; get two coordinate bytes (each minus 20h); ESC inside restarts the ESC
; command.  Out: B = first (row), C = second (column), carry = error
get_xy:
	call get_coord		;043d
	push af			;0440
	call get_coord		;0441
	pop bc			;0444
	bit 0,c			;0445
	ld c,a			;0447
	ret c			;0448
	scf			;0449
	ret nz			;044a
	ccf			;044b
	ret			;044c
l044d:
	call esc_cmd		;044d
get_coord:
	rst 20h			;0450
	cp 01bh			;0451
	jr z,l044d		;0453
	sub 020h		;0455
	ret			;0457

; ESC = row col: cursor addressing.  Rows count from the screen top.
esc_goto:
	call get_xy		;0458
	ret c			;045b
	ld a,(cols)		;045c
	neg			;045f
	ld e,a			;0461
	ld d,0ffh		;0462
	ld hl,VDUEND		;0464
	ld a,b			;0467
	cp (iy+V_ROWS)		;0468
	ret nc			;046b
	neg			;046c
	add a,(iy+V_ROWS)		;046e
	ld b,a			;0471
l0472:
	add hl,de		;0472
	djnz l0472		;0473
	ld (line_start),hl		;0475
	ex de,hl		;0478
	ld hl,(cols)		;0479
	add hl,de		;047c
	ld (line_end),hl		;047d
	ex de,hl		;0480
	ld de,reset		;0481
	ld a,c			;0484
	cp (iy+V_COLS)		;0485
	ret nc			;0488
	ld e,a			;0489
	add hl,de		;048a
	ld (cursor),hl		;048b
	ret			;048e

; (iy+3) is the cursor mask ANDed with the cursor address by the NMI handler
esc_cur_on:
	ld (iy+V_CURMASK),0ffh	;048f
	ret			;0493
esc_cur_off:
	ld (iy+V_CURMASK),000h	;0494
	ret			;0498

; ESC Y b c: set CRTC registers 10 and 11 (cursor start/end) during vsync
esc_cur_type:
	rst 20h			;0499
	ld b,a			;049a
	rst 20h			;049b
	ld c,a			;049c
	call wait_vsync		;049d
	ld a,00ah		;04a0
	out (CRTC_ADR),a		;04a2
	ld a,b			;04a4
	out (CRTC_DAT),a		;04a5
	ld a,00bh		;04a7
	out (CRTC_ADR),a		;04a9
	ld a,c			;04ab
	out (CRTC_DAT),a		;04ac
	ret			;04ae
esc_clr_eos:
	ld hl,VDUEND		;04af
	jr clr_to_hl		;04b2
esc_clr_eol:
	ld hl,(line_end)		;04b4
clr_to_hl:
	or a			;04b7
	sbc hl,de		;04b8
	ld b,h			;04ba
	ld c,l			;04bb
	call fill_space		;04bc
	ret			;04bf
esc_lock_on:
	ld hl,(line_start)		;04c0
	ld (lock_top),hl		;04c3
	ret			;04c6
esc_lock_off:
	ld hl,(scr_top)		;04c7
	ld (lock_top),hl		;04ca
	ret			;04cd
esc_alt_cg:
	ld (iy+V_CGXOR),080h	;04ce
	ret			;04d2
esc_norm_cg:
	ld (iy+V_CGXOR),000h	;04d3
	ret			;04d7
esc_blank:
	call wait_vsync		;04d8
	ld bc,00e00h		;04db
	jr set_ctrl		;04de
esc_unblank:
	call wait_vsync		;04e0
	ld bc,00e01h		;04e3
	jr set_ctrl		;04e6

; ESC I / ESC J: clear / set bit 2 of the control port.  Note: the hardware
; manual says bit 2 HIGH inverts the picture, but this software powers up
; with bit 2 high and treats it as the normal state.
esc_inverse:
	ld bc,00b00h		;04e8
	jr set_ctrl		;04eb
esc_normal:
	ld bc,00b04h		;04ed

; write-status shadow: ctrl = (ctrl AND B) OR C, then output to C000h
set_ctrl:
	ld a,(ctrl_shadow)		;04f0
	and b			;04f3
	or c			;04f4
	ld (ctrl_shadow),a		;04f5
	ld (STATUS_W),a		;04f8
	ret			;04fb

; ESC F: store 13 bytes (CRTC regs 0-11 + dot clock) in user_fmt
esc_def_fmt:
	ld hl,user_fmt		;04fc
	ld b,00dh		;04ff
l0501:
	rst 20h			;0501
	ld (hl),a		;0502
	inc hl			;0503
	djnz l0501		;0504
	ret			;0506
esc_fmt80:
	ld hl,fmt80		;0507
	jr set_format		;050a
esc_fmt48:
	ld hl,fmt48		;050c
	jr set_format		;050f

; ESC 3 / init: program the CRTC from user_fmt (E0C0h)
esc_fmt_user:
	ld hl,user_fmt		;0511

; HL -> 12 CRTC register values + clock select byte.  Copies to fmtbuf, sets
; cols/rows, screen address and programs CRTC regs 0-15 (OUTI loop).
set_format:
	ld bc,0000ch		;0514
	ld de,fmtbuf		;0517
	ldir			;051a
	ld a,(hl)		;051c
	and 002h		;051d
	ld e,a			;051f
	ld a,(ctrl_shadow)		;0520
	and 00dh		;0523
	or e			;0525
	ld (ctrl_shadow),a		;0526
	ld a,(fmtbuf+1)		;0529
	ld (cols),a		;052c
	ld d,000h		;052f
	ld e,a			;0531
	ld a,(fmtbuf+6)		;0532
	ld (rows),a		;0535
	ld b,a			;0538
	ld hl,reset		;0539
l053c:
	add hl,de		;053c
	djnz l053c		;053d
	ex de,hl		;053f
	ld hl,VDUEND		;0540
	sbc hl,de		;0543
	ld (cursor),hl		;0545
	ld (lock_top),hl		;0548
	ld (scr_top),hl		;054b
	ld (line_start),hl		;054e
	ld d,h			;0551
	ld e,l			;0552
	ld h,l			;0553
	ld l,d			;0554
	ld (fmtbuf+12),hl		;0555
	ld (fmtbuf+14),hl		;0558
	ld hl,(cols)		;055b
	add hl,de		;055e
	ld (line_end),hl		;055f
	xor a			;0562
	ld (STATUS_W),a		;0563
	ld b,010h		;0566
	ld c,001h		;0568
	ld a,000h		;056a
	ld hl,fmtbuf		;056c
l056f:
	out (CRTC_ADR),a		;056f
	inc a			;0571
	outi			;0572
	jr nz,l056f		;0574
	ld a,(ctrl_shadow)		;0576
	ld (STATUS_W),a		;0579
	ret			;057c

; ---- CRTC register tables: R0..R11 then a byte (bit 1 = crystal dot clock) ----
; 80 column format (crystal clock)
fmt80:
	defb 07fh,050h,063h,07fh,01eh,002h,019h,01bh,0a0h,009h,048h,008h,00fh	;057d

; 48 column format (variable clock)
fmt48:
	defb 04ch,030h,03ch,079h,01eh,002h,019h,01bh,0a0h,009h,048h,008h,000h	;058a

; ESC C code r0..r15: define one character in the c/gen at 4000h/4800h
; (msb of the code set = lower generator)
esc_def_char:
	rst 20h			;0597
	xor 080h		;0598
	ld l,a			;059a
	ld h,000h		;059b
	add hl,hl		;059d
	add hl,hl		;059e
	add hl,hl		;059f
	add hl,hl		;05a0
	ld de,CGLOW		;05a1
	add hl,de		;05a4
	ex de,hl		;05a5
	ld b,010h		;05a6
l05a8:
	rst 20h			;05a8
	rst 8			;05a9
	inc de			;05aa
	djnz l05a8		;05ab
	ret			;05ad

; ESC c g <2048 bytes>: load a complete character set (g=0: upper 4800h,
; non-zero: lower 4000h)
esc_def_cset:
	rst 20h			;05ae
	ld de,CGLOW		;05af
	or a			;05b2
	jr nz,l05b8		;05b3
	ld de,CGHIGH		;05b5
l05b8:
	ld bc,kbd_exit		;05b8
	jp load_loop		;05bb

; ESC h: copy lower c/gen to upper;  ESC H (esc_cg_inv): copy complemented
esc_cg_copy:
	res 1,(iy+V_MODE)		;05be
	jr cg_copy		;05c2
esc_cg_inv:
	set 1,(iy+V_MODE)		;05c4
cg_copy:
	ld de,CGHIGH		;05c8
	ld hl,CGLOW		;05cb
	push de			;05ce
l05cf:
	ld de,fmtbuf		;05cf
	ld bc,00100h		;05d2
	call copy_fwd		;05d5
	pop de			;05d8
	push hl			;05d9
	bit 1,(iy+V_MODE)		;05da
	jr z,l05e9		;05de
	ld hl,FKEYBUF		;05e0
l05e3:
	dec hl			;05e3
	ld a,(hl)		;05e4
	cpl			;05e5
	ld (hl),a		;05e6
	djnz l05e3		;05e7
l05e9:
	ld hl,fmtbuf		;05e9
	ld bc,00100h		;05ec
	call copy_fwd		;05ef
	pop hl			;05f2
	push de			;05f3
	ld a,h			;05f4
	cp 048h			;05f5
	jr nz,l05cf		;05f7
	pop hl			;05f9
	ret			;05fa

; ESC G: build the block graphic characters C0h-FFh in the PCG (4C00h-4FFFh)
esc_graphics:
	ld de,04c00h		;05fb
l05fe:
	ld hl,fmtbuf		;05fe
	ld a,e			;0601
	call gfx_nibble		;0602
	ld a,d			;0605
	rrca			;0606
	ld c,a			;0607
	ld a,e			;0608
	rra			;0609
	call gfx_nibble		;060a
	inc hl			;060d
	ld a,e			;060e
	rra			;060f
	rr c			;0610
	rra			;0612
	call gfx_nibble		;0613
	ld hl,fmtbuf		;0616
	ld bc,rst_vdu_read	;0619
	call copy_fwd		;061c
	ld a,d			;061f
	cp 050h			;0620
	jr nz,l05fe		;0622
	ret			;0624
gfx_nibble:
	ld b,003h		;0625
	and 090h		;0627
	jr z,l0635		;0629
	rl a			;062b
	jr z,l0631		;062d
	ld a,0f0h		;062f
l0631:
	jr nc,l0635		;0631
	or 00fh			;0633
l0635:
	ld (hl),a		;0635
	inc hl			;0636
	djnz l0635		;0637
	ld (hl),a		;0639
	ret			;063a

; ESC S/R/T x y: set / reset / test a block graphic point (2x3 per cell).
; ESC T returns 00h (reset), 01h (set) or 02h (illegal coordinates).
esc_pset:
	call gfx_locate		;063b
	ret c			;063e
	or c			;063f
	rst 8			;0640
	ret			;0641
esc_preset:
	call gfx_locate		;0642
	ret c			;0645
	and b			;0646
	rst 8			;0647
	ret			;0648
esc_ptest:
	call gfx_locate		;0649
	jr c,ptest_off		;064c
	and c			;064e
	jr z,l0656		;064f
	ld a,001h		;0651
	defb 021h		;0653 opcode of LD HL,nn; the JR C above jumps to the next byte
ptest_off:
	ld a,002h		;0654 (operand bytes of the LD HL: A = 2 = illegal coordinates)
l0656:
	rst 30h			;0656
	ret			;0657

; locate the character cell and pixel mask for point x,y
gfx_locate:
	call get_xy		;0658
	ret c			;065b
	ld a,b			;065c
	ld b,c			;065d
	rra			;065e
	ld c,007h		;065f
	jr nc,l0665		;0661
	ld c,038h		;0663
l0665:
	ld l,a			;0665
	ld a,(rows)		;0666
	inc a			;0669
	ld h,a			;066a
	ld a,b			;066b
	ld b,003h		;066c
l066e:
	dec h			;066e
	sub b			;066f
	jr nc,l066e		;0670
	add a,004h		;0672
	ld b,a			;0674
	ld a,084h		;0675
l0677:
	rlca			;0677
	djnz l0677		;0678
	and c			;067a
	ld c,a			;067b
	ld a,h			;067c
	or a			;067d
	scf			;067e
	ret z			;067f
	ret m			;0680
	ld a,(cols)		;0681
	dec a			;0684
	cp l			;0685
	ret c			;0686
	ld a,l			;0687
	ld b,h			;0688
	ld de,(cols)		;0689
	ld hl,VDUEND		;068d
l0690:
	sbc hl,de		;0690
	djnz l0690		;0692
	ld e,a			;0694
	add hl,de		;0695
	ex de,hl		;0696
	ld a,c			;0697
	cpl			;0698
	ld b,a			;0699
	rst 10h			;069a
	cp 0c0h			;069b
	ret nc			;069d
	ld a,0c0h		;069e
	or a			;06a0
	ret			;06a1

; ESC L len(16 bit) data: load a user program into E400h (max 400h bytes)
esc_load:
	rst 20h			;06a2
	ld c,a			;06a3
	rst 20h			;06a4
	ld b,a			;06a5
	ld hl,00400h		;06a6
	or a			;06a9
	sbc hl,bc		;06aa
	jr nc,l06b1		;06ac
	ld bc,00400h		;06ae
l06b1:
	ld de,USERPROG		;06b1
	jp load_to_ram		;06b4

; ESC W lo hi cl ch mm: high speed write of cl:ch bytes at screen offset hi:lo.
; mm = 't' or 'T': transparent (synchronised to blanking); anything else:
; direct (fast, may disturb the display).  No control code processing.
esc_hswrite:
	rst 20h			;06b7
	ld e,a			;06b8
	rst 20h			;06b9
	ld d,a			;06ba
	ld hl,(scr_top)		;06bb
	add hl,de		;06be
	ex de,hl		;06bf
	ld h,d			;06c0
	ld l,e			;06c1
	call chk_vdu_addr	;06c2
	jr nc,l06cb		;06c5
	ld de,(scr_top)		;06c7
l06cb:
	rst 20h			;06cb
	ld c,a			;06cc
	rst 20h			;06cd
	ld b,a			;06ce
	cp 009h			;06cf
	jr nc,l06dd		;06d1
	or c			;06d3
	jr z,l06dd		;06d4
	add hl,bc		;06d6
	dec hl			;06d7
	call chk_vdu_addr	;06d8
	jr nc,l06e5		;06db
l06dd:
	ld hl,VDUEND		;06dd
	or a			;06e0
	sbc hl,de		;06e1
	ld b,h			;06e3
	ld c,l			;06e4
l06e5:
	rst 20h			;06e5
	cp 074h			;06e6
	jp z,load_to_vdu	;06e8
	cp 054h			;06eb
	jp nz,load_to_ram	;06ed
load_loop:
	rst 20h			;06f0
	rst 8			;06f1
	inc de			;06f2
	dec bc			;06f3
	ld a,b			;06f4
	or c			;06f5
	jr nz,load_loop		;06f6
	ret			;06f8
chk_vdu_addr:
	ld a,h			;06f9
	cp 020h			;06fa
	ret c			;06fc
	cp 028h			;06fd
	ccf			;06ff
	ret			;0700

; ESC Z: send the current line to the host (trailing spaces removed, CR)
esc_getline:
	ld bc,(cols)		;0701
	ld de,fmtbuf		;0705
	ld hl,(line_start)		;0708
	call copy_fwd		;070b
	ex de,hl		;070e
	ld a,(cols)		;070f
	ld b,a			;0712
	ld a,020h		;0713
l0715:
	dec hl			;0715
	cp (hl)			;0716
	jr nz,l071c		;0717
	djnz l0715		;0719
	dec hl			;071b
l071c:
	inc hl			;071c
	ld (hl),00dh		;071d
	ld hl,fmtbuf		;071f
l0722:
	ld a,(hl)		;0722
	inc hl			;0723
	rst 30h			;0724
	cp 00dh			;0725
	jr nz,l0722		;0727
	ret			;0729

; ESC ?: send cursor row, column and the character under the cursor
esc_where:
	call send_rowcol	;072a
	ld de,(cursor)		;072d
	rst 10h			;0731
	rst 30h			;0732
	ret			;0733

; ESC k: FFh if a key is waiting, else 00h
esc_kb_status:
	ld a,(kbd_wr)		;0734
	xor (iy+V_KBRDLO)		;0737
	add a,0ffh		;073a
	sbc a,a			;073c
	rst 30h			;073d
	ret			;073e

; ESC K: send next keyboard character (0 if keyboard disabled, link 3)
esc_kb_get:
	ld a,(STATUS_R)		;073f
	bit 6,a			;0742
	ld a,000h		;0744
	call z,kbd_getc		;0746
l0749:
	rst 30h			;0749
	ret			;074a

; ESC X: keyboard line input: echo keys until CR, then send the line
esc_kb_line:
	exx			;074b
	bit 6,(hl)		;074c
	exx			;074e
	ld a,00dh		;074f
	jr nz,l0749		;0751
	bit 0,(iy+V_MODE)		;0753
	ret nz			;0757
	set 0,(iy+V_MODE)		;0758
l075c:
	rst 20h			;075c
	push af			;075d
	call put_char		;075e
	pop af			;0761
	cp 00dh			;0762
	jr nz,l075c		;0764
	res 0,(iy+V_MODE)		;0766
	jp esc_getline		;076a

; ESC P: wait (HALT/NMI) for the light pen strobe, send its position
esc_lightpen:
	exx			;076d
l076e:
	halt			;076e
	bit 0,(hl)		;076f
	jr nz,l07b2		;0771
	bit 4,(hl)		;0773
	jr nz,l076e		;0775
	halt			;0777
	bit 4,(hl)		;0778
	jr nz,l076e		;077a
	exx			;077c
	ld a,010h		;077d
	ld c,001h		;077f
	out (CRTC_ADR),a		;0781
	in d,(c)		;0783
	inc a			;0785
	out (CRTC_ADR),a		;0786
	in e,(c)		;0788
	dec de			;078a
	dec de			;078b
	dec de			;078c
	ld hl,(scr_top)		;078d
	or a			;0790
	dec hl			;0791
	sbc hl,de		;0792
	jr nc,esc_lightpen	;0794
	ld a,027h		;0796
	cp d			;0798
	jr c,esc_lightpen	;0799

; send (row, column) of the address in DE relative to the screen top
send_rowcol:
	ld hl,(scr_top)		;079b
	ex de,hl		;079e
	or a			;079f
	sbc hl,de		;07a0
	ld de,(cols)		;07a2
	ld a,0ffh		;07a6
l07a8:
	inc a			;07a8
	sbc hl,de		;07a9
	jr nc,l07a8		;07ab
	rst 30h			;07ad
	add hl,de		;07ae
	ld a,l			;07af
	rst 30h			;07b0
	ret			;07b1
l07b2:
	exx			;07b2
	ret			;07b3

; ESC v: version number 20h = 2.0
esc_version:
	ld a,020h		;07b4
	rst 30h			;07b6
	ret			;07b7

; ---- table_jump: HL = end of a code table, BC = entry count ----
; Searches A backwards in the table (CPDR); if found, jumps through the
; word table that follows it, else returns.
table_jump:
	push hl			;07b8
	dec hl			;07b9
	cpdr			;07ba
	pop hl			;07bc
	ret nz			;07bd
	add hl,bc		;07be
	add hl,bc		;07bf
	ld a,(hl)		;07c0
	inc hl			;07c1
	ld h,(hl)		;07c2
	ld l,a			;07c3
	jp (hl)			;07c4

; wait for a vertical sync pulse (status bit 1), polling the host
wait_vsync:
	ld hl,STATUS_R		;07c5
l07c8:
	rst 18h			;07c8
	bit 1,(hl)		;07c9
	jr z,l07c8		;07cb
l07cd:
	rst 18h			;07cd
	bit 1,(hl)		;07ce
	jr nz,l07cd		;07d0
	ret			;07d2

; ---- Keyboard scan (called from the NMI): port 8000h, bit 7 = strobe ----
kbd_scan:
	ld a,(KBDPORT)		;07d3
	xor (iy+V_KBDLAST)		;07d6
	jr z,l07e4		;07d9
	xor (iy+V_KBDLAST)		;07db
	ld (kbd_last),a		;07de
	jp m,kbd_new_key	;07e1
l07e4:
	pop af			;07e4
	ret			;07e5

; new key (bit 7 = strobe): ESC needs special handling (kbd_esc_chk); with
; kflags bit 0 set the key is looked up as a function key (kbd_fkey_chk)
kbd_new_key:
	push hl			;07e6
	ld hl,kflags		;07e7
	bit 0,(hl)		;07ea
	jr nz,kbd_fkey_chk	;07ec
	and 07fh		;07ee
	cp 01bh			;07f0
	jr z,kbd_esc_chk	;07f2
kbd_put:
	ld hl,(kbd_wr)		;07f4
	ld (hl),a		;07f7
	inc hl			;07f8
	res 6,l			;07f9
	ld (kbd_wr),hl		;07fb
kbd_pop_hl:
	pop hl			;07fe
kbd_pop_af:
	pop af			;07ff
kbd_exit:
	ret			;0800

; keyboard sent ESC: with link 2 made (status bit 5 low, ASCII keyboard) it is
; stored as an ordinary character; otherwise (GM827) kflags bit 0 is set so
; that the next code is looked at as a function key code
kbd_esc_chk:
	ld a,(STATUS_R)		;0801
	bit 5,a			;0804
	ld a,01bh		;0806
	jr z,kbd_put		;0808
	set 0,(hl)		;080a
	jr kbd_pop_hl		;080c

; byte following ESC from the GM827: a table code is stored as is; 9Bh
; (shift/EDIT) sets kflags bits 7 and 6 = start List/Edit
kbd_fkey_chk:
	res 0,(hl)		;080e
	bit 7,(hl)		;0810
	jr nz,kbd_put		;0812
	push bc			;0814
	push hl			;0815
	call fkey_find		;0816
	pop hl			;0819
	pop bc			;081a
	jr z,kbd_put		;081b
	cp 09bh			;081d
	jr nz,kbd_pop_hl	;081f
	set 7,(hl)		;0821
	set 6,(hl)		;0823
	jr kbd_pop_hl		;0825

; ---- kbd_getc: fetch the next character from the keyboard buffer ----
; The keyboard buffer is a 64 byte ring at E000h-E03Fh (shared layout with
; the host input ring).  kbd_wr (E0D2h) is the write pointer, kbd_rd
; (E0D4h) the read pointer.  Blocks until a character is available.
; Function key codes (>= 80h) are expanded into their programmed strings.
kbd_getc:
	push hl			;0827
	push bc			;0828
	ld hl,(kbd_rd)		;0829
kbd_wait:
	ld a,(kflags)		;082c
	bit 6,a			;082f
	call nz,kbd_hotkey	;0831
	ld a,(kbd_wr)		;0834
	sub l			;0837
	jr z,kbd_wait		;0838
	ld a,(hl)		;083a
	bit 7,a			;083b
	jr nz,kbd_fnkey		;083d
kbd_advance:
	inc l			;083f
	res 6,l			;0840
	ld (kbd_rd),hl		;0842
	pop bc			;0845
	pop hl			;0846
	ret			;0847

; List/Edit hot key was pressed (kflags bit 6): run the interactive editor
kbd_hotkey:
	push de			;0848
	call fkey_listedit	;0849
	pop de			;084c
	ld hl,(kbd_rd)		;084d
	ret			;0850

; Buffer entry >= 80h.  80h and 90h are not real function keys (ESC
; stand-ins in the table) and, like all keys when kflags bit 7 is set, are
; returned as ordinary characters.
kbd_fnkey:
	call fkey_test		;0851
	jr z,kbd_expand		;0854
	ld a,(kflags)		;0856
	rlca			;0859
	ld a,(hl)		;085a
	jr c,kbd_advance	;085b

; Expand function key A.  fkeyptr = 0 means 'start of string', otherwise
; it points at the next byte to return.  The code is removed from the ring
; only when the last byte of its string has been delivered.
kbd_expand:
	ld b,a			;085d
	ld hl,(fkeyptr)		;085e
	ld a,h			;0861
	or l			;0862
	ld a,b			;0863
	call z,fkey_find	;0864
	ld a,(hl)		;0867
	inc hl			;0868
	bit 7,(hl)		;0869
	jr z,kbd_expand_ret	;086b
	ld hl,(kbd_rd)		;086d
	inc hl			;0870
	res 6,l			;0871
	ld (kbd_rd),hl		;0873
	ld hl,reset		;0876
kbd_expand_ret:
	ld (fkeyptr),hl		;0879
	pop bc			;087c
	pop hl			;087d
	ret			;087e

; ---- ESC f d / ESC f D: restore the default function key table ----
fkey_defaults:
	ld hl,fkey_default_tbl	;087f
	ld de,FKEYBUF		;0882
fkey_defaults_lp:
	ld a,(hl)		;0885
	ldi			;0886
	inc a			;0888
	jr nz,fkey_defaults_lp	;0889
	jp fkey_setlen		;088b

; ---- ESC f ... : define / list function keys (host command) ----
;   ESC f d|D          restore the defaults
;   ESC f ?            send the table to the host
;   ESC f <key> <str> [<key> <str> ...]   define keys
esc_fkey:
	rst 20h			;088e
	cp 064h			;088f
	jr z,fkey_defaults	;0891
	cp 044h			;0893
	jr z,fkey_defaults	;0895
	cp 03fh			;0897
	jr z,fkey_list		;0899
fkey_def_loop:
	call fkey_test		;089b
	ret z			;089e
	cp 0beh			;089f
	ret nc			;08a1
	push af			;08a2
	call fkey_delete	;08a3
	pop af			;08a6
	ld hl,(fkeylen)		;08a7
	ld bc,FKEYBUF		;08aa
	add hl,bc		;08ad

; append byte A at (HL), keep the table terminated with FFh; overflow at E400h
fkey_store:
	ld (hl),a		;08ae
	inc hl			;08af
	ld (hl),0ffh		;08b0
	inc hl			;08b2
	ld a,h			;08b3
	dec hl			;08b4
	cp 0e4h			;08b5
	jp z,fkey_overflow	;08b7
	rst 20h			;08ba
	bit 7,a			;08bb
	jr z,fkey_store		;08bd
	push af			;08bf
	call fkey_setlen	;08c0
	pop af			;08c3
	jr fkey_def_loop	;08c4

; send the user visible part of the table (skipping the 80h/90h entries)
fkey_list:
	ld hl,FKEYBUF+4		;08c6
fkey_list_lp:
	ld a,(hl)		;08c9
	inc hl			;08ca
	rst 30h			;08cb
	cp 0ffh			;08cc
	jr nz,fkey_list_lp	;08ce
	ret			;08d0

; ---- fkey_find: look for A in the table.  Z if found, HL just after ----
fkey_find:
	ld hl,FKEYBUF		;08d1
	ld bc,(fkeylen)		;08d4
	cpir			;08d8
	ret			;08da

; ---- fkey_test: NZ if A is a function key (81h-8Fh, 91h-FFh) ----
fkey_test:
	cp 080h			;08db
	ret z			;08dd
	cp 090h			;08de
	ret z			;08e0
	bit 7,a			;08e1
	ret			;08e3

; ---- fkey_delete: remove the definition of key A (if any) ----
fkey_delete:
	call fkey_test		;08e4
	ret z			;08e7
	call fkey_find		;08e8
	ret nz			;08eb
	dec hl			;08ec
	ld d,h			;08ed
	ld e,l			;08ee
fkey_del_scan:
	inc hl			;08ef
	bit 7,(hl)		;08f0
	jr z,fkey_del_scan	;08f2
fkey_del_copy:
	ld a,(hl)		;08f4
	ldi			;08f5
	inc a			;08f7
	jr nz,fkey_del_copy	;08f8
	dec de			;08fa
	jp fkey_setlen		;08fb

; ---- Messages (text ends with a byte with bit 7 set, normally 80h) ----
msg_overflow:
	defb " *** IVC Internal error *** -  programmable key buffer overflow",080h	;08fe

; ---- print_crlf_str: CR/LF, then the string at HL, then CR/LF ----
; ---- print_str     : the string at HL, then CR/LF ----
; Strings end with a byte with bit 7 set.  Output goes through put_char.
print_crlf_str:
	call print_crlf		;093e
print_str:
	ld a,(hl)		;0941
	inc hl			;0942
	bit 7,a			;0943
	jr nz,print_crlf	;0945
	push hl			;0947
	call print_char		;0948
	pop hl			;094b
	jr print_str		;094c

; print CR, LF (HL preserved)
print_crlf:
	push hl			;094e
	ld a,00dh		;094f
	call put_char		;0951
	ld a,00ah		;0954
	call put_char		;0956
	pop hl			;0959
	ret			;095a

; print A; control characters are shown as ^X
print_char:
	cp 020h			;095b
	jr nc,print_char_pr	;095d
	push af			;095f
	ld a,05eh		;0960
	call put_char		;0962
	pop af			;0965
	add a,040h		;0966
print_char_pr:
	call put_char		;0968
	ret			;096b
msg_listedit:
	defb "*** List/Edit a Function key ***",080h	;096c
msg_undefined:
	defb "*** Key is undefined ***",080h	;098d
msg_notfkey:
	defb "*** Not a function Key ***",080h	;09a6

; ---- List/Edit a function key (interactive, started by the hot key 9Bh) ----
; Press a function key to list its definition.  Press the hot key again to
; define a key: press the key, type the string, end it with any function key.
fkey_listedit:
	res 6,(iy+V_KFLAGS)		;09c1
	ld hl,msg_listedit	;09c5
	call print_crlf_str	;09c8
	call kbd_getc		;09cb
	call fkey_test		;09ce
le_show:
	ld hl,msg_notfkey	;09d1
	jr z,le_report		;09d4
	cp 09bh			;09d6
	jr z,le_define		;09d8
	call fkey_find		;09da
	jr z,le_report		;09dd
	ld hl,msg_undefined	;09df
le_report:
	call print_str		;09e2
	ld hl,msg_complete	;09e5
	call print_str		;09e8
	ld a,(kflags)		;09eb
	and 001h		;09ee
	ld (kflags),a		;09f0
	ret			;09f3
le_define:
	ld hl,msg_press		;09f4
	call print_crlf_str	;09f7
	call print_str		;09fa
	call kbd_getc		;09fd
le_getkey:
	call fkey_test		;0a00
	jr z,le_show		;0a03
	push af			;0a05
	call fkey_delete	;0a06
	pop af			;0a09
	ld hl,(fkeylen)		;0a0a
	ld bc,FKEYBUF		;0a0d
	add hl,bc		;0a10
le_store:
	ld (hl),a		;0a11
	inc hl			;0a12
	ld (hl),0ffh		;0a13
	inc hl			;0a15
	ld a,h			;0a16
	dec hl			;0a17
	cp 0e4h			;0a18
	jr z,fkey_overflow	;0a1a
	call kbd_getc		;0a1c
	call fkey_test		;0a1f
	jr nz,le_finish		;0a22
	bit 7,a			;0a24
	jr z,le_echo		;0a26
	ld a,01bh		;0a28
le_echo:
	push hl			;0a2a
	push bc			;0a2b
	push af			;0a2c
	call print_char		;0a2d
	pop af			;0a30
	pop bc			;0a31
	pop hl			;0a32
	jr le_store		;0a33
fkey_overflow:
	push hl			;0a35
	push bc			;0a36
	ld hl,msg_overflow	;0a37
	call print_crlf_str	;0a3a
	pop bc			;0a3d
	pop hl			;0a3e
le_finish:
	ld a,(kflags)		;0a3f
	and 001h		;0a42
	ld (kflags),a		;0a44
	dec hl			;0a47
	bit 7,(hl)		;0a48
	jr z,le_done		;0a4a
	ld (hl),0ffh		;0a4c
le_done:
	ld hl,msg_newdef	;0a4e
	call print_crlf_str	;0a51
	call print_str		;0a54

; ---- fkey_setlen: fkeylen = number of bytes before the FFh terminator ----
fkey_setlen:
	ld bc,00200h		;0a57
	ld hl,FKEYBUF		;0a5a
	ld a,0ffh		;0a5d
	cpir			;0a5f
	ld hl,001ffh		;0a61
	or a			;0a64
	sbc hl,bc		;0a65
	ld (fkeylen),hl		;0a67
	ret			;0a6a
msg_press:
	defb "*** Press the function Key to be defined, then type in a string ***",080h	;0a6b
msg_followed:
	defb "***      followed by any function key ***",080h	;0aaf
msg_newdef:
	defb "*** New definition entered ***",080h	;0ad9
msg_complete:
	defb "***   List/Edit complete   ***",080h	;0af8

msg_copyright:
	defb "(C) dci software 1982"	;0b17
; (no terminator of its own: the next byte, 80h, is the first table entry)

; ---- Default function key table (copied to FKEYBUF by fkey_defaults) ----
; Format: key code (>= 80h), string bytes (< 80h), ..., FFh.
; 80h/90h = ESC stand-ins, 8Bh-8Fh/9Ch-9Fh = cursor keys, A0h-AEh/B0h-BDh/AFh =
; keypad (plain / shifted), 81h-8Ah / 91h-9Ah = function keys.
fkey_default_tbl:
	defb 080h,01bh	;0b2c
	defb 090h,01bh	;0b2e
	defb 08bh,000h	;0b30
	defb 08ch,01ch	;0b32
	defb 08dh,01dh	;0b34
	defb 08eh,01eh	;0b36
	defb 08fh,01fh	;0b38
	defb 09ch,016h	;0b3a
	defb 09dh,017h	;0b3c
	defb 09eh,00bh	;0b3e
	defb 09fh,00eh	;0b40
	defb 0a0h,"7"	;0b42
	defb 0a1h,"8"	;0b44
	defb 0a2h,"9"	;0b46
	defb 0a3h,"+"	;0b48
	defb 0a4h,"4"	;0b4a
	defb 0a5h,"5"	;0b4c
	defb 0a6h,"6"	;0b4e
	defb 0a7h,"-"	;0b50
	defb 0a8h,"1"	;0b52
	defb 0a9h,"2"	;0b54
	defb 0aah,"3"	;0b56
	defb 0abh,","	;0b58
	defb 0ach,"0"	;0b5a
	defb 0adh,"."	;0b5c
	defb 0aeh,00dh	;0b5e
	defb 0b0h,"7"	;0b60
	defb 0b1h,"8"	;0b62
	defb 0b2h,"9"	;0b64
	defb 0b3h,"+"	;0b66
	defb 0b4h,"4"	;0b68
	defb 0b5h,"5"	;0b6a
	defb 0b6h,"6"	;0b6c
	defb 0b7h,"-"	;0b6e
	defb 0b8h,"1"	;0b70
	defb 0b9h,"2"	;0b72
	defb 0bah,"3"	;0b74
	defb 0bbh,","	;0b76
	defb 0bch,"0"	;0b78
	defb 0bdh,"."	;0b7a
	defb 0afh,00dh	;0b7c
	defb 081h,"dir a:"	;0b7e
	defb 082h,"stat a:"	;0b85
	defb 083h,"pip a:=b:"	;0b8d
	defb 084h,"*.*"	;0b97
	defb 085h,"[rv]"	;0b9b
	defb 086h,"comal80s",00dh	;0ba0
	defb 087h,"mbasic "	;0baa
	defb 088h,008h	;0bb2
	defb 089h,018h	;0bb4
	defb 08ah,003h,"a:",00dh,"b:",00dh,"a:",00dh,"stat",00dh	;0bb6
	defb 091h,"dir b:"	;0bc6
	defb 092h,"stat b:"	;0bcd
	defb 093h,"pip b:=a:"	;0bd5
	defb 094h,"*.*"	;0bdf
	defb 095h,"[rv]"	;0be3
	defb 096h,"comal-80",00dh	;0be8
	defb 097h,"mbasic",00dh	;0bf2
	defb 098h,018h	;0bfa
	defb 099h,018h	;0bfc
	defb 09ah,018h	;0bfe
	defb 0ffh		;0c00 end of table

	defs 01000h-$,0ffh	; unused, FFh to the end of the 4K image
