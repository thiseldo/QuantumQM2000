;
; Quantum QM2000 monitor ROM V2.1 (QM-MON-V21)
; Disassembled from Originals/QM-MON-V21.HEX/.BIN. ROM is mapped at F000h.
; Assemble with e.g.:  z80asm -o QM-MON-V21.bin QM-Mon-V21.asm
;
; Monitor commands (prompt is '>'; single letter, then hex arguments
; separated by spaces, last one ended with Return; errors print "-What?"):
;
;   B                  - boot (restart at cold_start)
;   C ffff tttt cccc   - copy cccc bytes from ffff to tttt (LDIR)
;   E aaaa             - execute at address aaaa
;   F ssss eeee vv     - fill from ssss to eeee (inclusive) with value vv
;   M aaaa             - examine/modify memory at aaaa: shows addr-byte;
;                        hex digits + space/Return = store and advance,
;                        Return alone = skip to next, '-' = back one,
;                        any other key = quit
;   O pp vv            - output value vv to I/O port pp
;   Q pp               - query (read and print) I/O port pp
;   T ffff cc          - type (dump) cc lines of 16 bytes from ffff
;

; ---- Port definitions (GM811/GM813 CPU board and plug-in boards) ----
MMAP:	equ 0feh	; memory mapper (GM813)
PMOD:	equ 0ffh	; page mode (GM813)

; GM812 IVC (video/keyboard) board
IVCDAT:	equ 0b1h	; IVC (video/keyboard) data, read/write
IVCSTA:	equ 0b2h	; IVC status: bit 0 = busy, bit 7 = no data
IVCRST:	equ 0b3h	; IVC reset (read to reset)

; GM829 Floppy disc controller with FD1797 chip
FDCCMD:	equ 0e0h	; FD1797 command register (write)
FDCSTA:	equ 0e0h	; FD1797 status register (read)
FDCSEC:	equ 0e2h	; FD1797 sector register
FDCDAT:	equ 0e3h	; FD1797 data register
FDCDRV:	equ 0e4h	; GM829 card drive select / DRQ poll

; ---- Other constants ----
STACK:	equ 00100h	; stack grows down from here
BOOTGO:	equ 00002h	; entry point of loaded boot sector
BOOTSIG:equ 04747h	; "GG" signature expected in first word of boot sector

	org 0f000h

	jp cold_start		;f000
	jp conin_echo		;f003
	jp conout		;f006
	jp print_a		;f009
	jp print_hl		;f00c
	jp print_space		;f00f
	jp print_cr		;f012
	defb "(C) dci software 22-07-82"	;f015
cold_start:
	in a,(IVCRST)		;f02e
	ld d,040h		;f030
lf032h:
	ld bc,0f000h+MMAP		;f032
	ld e,00fh		;f035
lf037h:
	out (c),e		;f037
	dec e			;f039
	ld a,b			;f03a
	sub 010h		;f03b
	ld b,a			;f03d
	jr nc,lf037h		;f03e
	dec d			;f040
	jr nz,lf032h		;f041
	ld a,011h		;f043
	out (PMOD),a		;f045
	ld sp,STACK		;f047
	in a,(IVCDAT)		;f04a
lf04ch:
	ld hl,00000h		;f04c
	ld a,01bh		;f04f
	call conout_raw		;f051
	ld a,076h		;f054
	call conout_raw		;f056
lf059h:
	dec hl			;f059
	ld a,h			;f05a
	or l			;f05b
	jr z,lf04ch		;f05c
	in a,(IVCSTA)		;f05e
	rlca			;f060
	jr c,lf059h		;f061
	in a,(IVCDAT)		;f063
	ld hl,sign_on_msg		;f065
	call print_str		;f068
	ld a,i			;f06b
	ld a,0ffh		;f06d
	ld i,a			;f06f
	jp z,boot_retry		;f071
	jr system_error		;f074
boot_sector_msg:
	defb " while loading Boot sector",00h		;f076
boot_error:
	ld hl,boot_sector_msg		;f091
	push hl			;f094
	jr show_read_error		;f095
system_load_msg:
	defb " during System load",00h		;f097
system_error:
	ld hl,system_load_msg		;f0ab
	push hl			;f0ae
	jr show_read_error		;f0af
read_error_msg:
	defb 1bh,"A***READ ERROR***",1bh,"N",00h		;f0b1
press_key_msg:
	defb " - Press any key to repeat",0dh,1eh,00h		;f0c6
show_read_error:
	ld hl,read_error_msg		;f0e3
	call print_str		;f0e6
	pop hl			;f0e9
	call print_str		;f0ea
	ld hl,press_key_msg		;f0ed
lf0f0h:
	call print_str		;f0f0
lf0f3h:
	call wait_disk_ready		;f0f3
	jr z,lf0fah		;f0f6
	jr nc,lf0f3h		;f0f8
lf0fah:
	call check_abort_msg		;f0fa
	jr boot_retry		;f0fd
insert_disk_msg:
	defb "             ",1bh		;f0ff
	defb "A Insert Disk in drive A ",1bh,"N",0dh,1eh,00h		;f117
boot_prompt:
	ld hl,insert_disk_msg		;f12b
	call print_str		;f12e
	call wait_disk_ready		;f131
	call check_abort_msg		;f134
	call wait_disk_ready		;f137
	jr z,boot_prompt		;f13a
boot_retry:
	ld sp,STACK		;f13c
	call wait_disk_ready		;f13f
	jr z,boot_prompt		;f142
lf144h:
	in a,(FDCSTA)		;f144
	bit 0,a			;f146
	jr nz,lf144h		;f148
	ld a,05bh		;f14a
	call fdc_command		;f14c
	ld a,00bh		;f14f
	call fdc_command		;f151
	call read_boot_sector		;f154
	or a			;f157
	jp nz,boot_error		;f158
	ld hl,(00000h)		;f15b
	ld de,BOOTSIG		;f15e
	or a			;f161
	sbc hl,de		;f162
	jp z,BOOTGO		;f164
	ld hl,no_cpm_msg		;f167
	jr lf0f0h		;f16a
no_cpm_msg:
	defb "        ",1bh		;f16c
	defb "A ***No QM2000 CP/M system on this Disk*** ",1bh
	defb "N",0dh,1eh,00h		;f184
read_boot_sector:
	ld a,00bh		;f1a5
	call fdc_command		;f1a7
	ld a,000h		;f1aa
	out (FDCSEC),a		;f1ac
	ld hl,00000h		;f1ae
	ld c,FDCDRV		;f1b1
	ld a,088h		;f1b3
	out (FDCCMD),a		;f1b5
	ld b,080h		;f1b7
	jr lf1bbh		;f1b9
lf1bbh:
	in a,(c)		;f1bb
	jr z,lf1bbh		;f1bd
	in a,(FDCDAT)		;f1bf
	ld (hl),a		;f1c1
	inc hl			;f1c2
	djnz lf1bbh		;f1c3
lf1c5h:
	in a,(c)		;f1c5
	jr z,lf1c5h		;f1c7
	in a,(FDCDAT)		;f1c9
	jp m,lf1c5h		;f1cb
	in a,(FDCSTA)		;f1ce
	ret			;f1d0
wait_disk_ready:
	ld a,0d0h		;f1d1
	call fdc_command		;f1d3
	ld a,001h		;f1d6
	out (FDCDRV),a		;f1d8
	ld a,00bh		;f1da
	out (FDCCMD),a		;f1dc
	ld hl,0b000h		;f1de
	ld b,000h		;f1e1
lf1e3h:
	in a,(FDCSTA)		;f1e3
	rlca			;f1e5
	jr c,lf1eah		;f1e6
	ld b,0ffh		;f1e8
lf1eah:
	dec l			;f1ea
	jr nz,lf1e3h		;f1eb
	call check_abort		;f1ed
	or a			;f1f0
	scf			;f1f1
	ret nz			;f1f2
	dec h			;f1f3
	jr nz,lf1e3h		;f1f4
	ld a,b			;f1f6
	or a			;f1f7
	ret			;f1f8
check_abort_msg:
	ld hl,esc_clear_line		;f1f9
	call print_str		;f1fc
check_abort:
	call kbd_status		;f1ff
	or a			;f202
	ret z			;f203
	call kbd_get		;f204
	cp 013h			;f207
	ld a,001h		;f209
	ret nz			;f20b
	ld hl,esc_clear_line		;f20c
	call print_str		;f20f
	jp monitor_start		;f212
esc_clear_line:
	defb 1bh,"*",00h		;f215
fdc_command:
	out (FDCCMD),a		;f218
	ld a,00ah		;f21a
lf21ch:
	dec a			;f21c
	jr nz,lf21ch		;f21d
lf21fh:
	in a,(FDCSTA)		;f21f
	bit 0,a			;f221
	jr nz,lf21fh		;f223
	ret			;f225
monitor_banner:
	defb 0dh,0ah,1bh,"E       SImple MONitor",0dh,0ah,00h		;f226
monitor_start:
	xor a			;f242
	out (FDCDRV),a		;f243
	ld i,a			;f245
	ld hl,monitor_banner		;f247
	call print_str		;f24a
monitor_loop:
	ld sp,STACK		;f24d
	ld a,03eh		;f250
	call conout		;f252
	call conout		;f255
	ld hl,monitor_loop		;f258
	push hl			;f25b
	call conin_echo		;f25c
	cp 042h			;f25f
	jp z,cold_start		;f261
	cp 043h			;f264
	jp z,cmd_copy		;f266
	cp 045h			;f269
	jp z,cmd_execute		;f26b
	cp 046h			;f26e
	jp z,cmd_fill		;f270
	cp 04dh			;f273
	jp z,cmd_modify		;f275
	cp 04fh			;f278
	jp z,cmd_out		;f27a
	cp 051h			;f27d
	jp z,cmd_in		;f27f
	cp 054h			;f282
	jp z,cmd_dump		;f284
what_error:
	ld hl,what_msg		;f287
	jr print_str		;f28a
what_msg:
	defb "  -What?",0dh,00h		;f28c
	cp 030h			;f296
	ret c			;f298
	cp 03ah			;f299
	jr c,lf2a6h		;f29b
	cp 041h			;f29d
	ret c			;f29f
	cp 047h			;f2a0
	ccf			;f2a2
	ret c			;f2a3
	sub 007h		;f2a4
lf2a6h:
	and 00fh		;f2a6
	ret			;f2a8
print_str:
	ld a,(hl)		;f2a9
	or a			;f2aa
	ret z			;f2ab
	call conout		;f2ac
	inc hl			;f2af
	jr print_str		;f2b0
print_hl:
	ld a,h			;f2b2
	call print_a		;f2b3
	ld a,l			;f2b6
print_a:
	push af			;f2b7
	rrca			;f2b8
	rrca			;f2b9
	rrca			;f2ba
	rrca			;f2bb
	call print_nibble		;f2bc
	pop af			;f2bf
print_nibble:
	and 00fh		;f2c0
	add a,090h		;f2c2
	daa			;f2c4
	adc a,040h		;f2c5
	daa			;f2c7
	jp conout		;f2c8
print_cr:
	ld a,00dh		;f2cb
	jp conout		;f2cd
print_space:
	ld a,020h		;f2d0
	jp conout		;f2d2
get_hex_digit:
	call conin_echo		;f2d5
	cp 030h			;f2d8
	ret c			;f2da
	cp 03ah			;f2db
	jr c,lf2e8h		;f2dd
	cp 041h			;f2df
	ret c			;f2e1
	cp 047h			;f2e2
	ccf			;f2e4
	ret c			;f2e5
	sub 007h		;f2e6
lf2e8h:
	and 00fh		;f2e8
	ret			;f2ea
get_hex_word:
	ld hl,00000h		;f2eb
	call get_hex_digit		;f2ee
	jr nc,lf2f9h		;f2f1
	cp 020h			;f2f3
	jr z,get_hex_word		;f2f5
	scf			;f2f7
	ret			;f2f8
lf2f9h:
	add hl,hl		;f2f9
	ret c			;f2fa
	add hl,hl		;f2fb
	ret c			;f2fc
	add hl,hl		;f2fd
	ret c			;f2fe
	add hl,hl		;f2ff
	ret c			;f300
	add a,l			;f301
	ld l,a			;f302
	call get_hex_digit		;f303
	jr nc,lf2f9h		;f306
	cp 020h			;f308
	ret z			;f30a
	cp 00dh			;f30b
	ret z			;f30d
	scf			;f30e
	ret			;f30f
get_arg:
	call get_hex_word		;f310
	jr c,lf318h		;f313
	cp 020h			;f315
	ret z			;f317
lf318h:
	pop hl			;f318
	jp what_error		;f319
get_last_arg:
	call get_hex_word		;f31c
	jr c,lf318h		;f31f
	cp 00dh			;f321
	ret z			;f323
	jr lf318h		;f324
cmd_copy:
	call get_arg		;f326
	ex de,hl		;f329
	call get_arg		;f32a
	ld b,h			;f32d
	ld c,l			;f32e
	call get_last_arg		;f32f
	push bc			;f332
	ex (sp),hl		;f333
	pop bc			;f334
	ex de,hl		;f335
	ldir			;f336
	ret			;f338
cmd_execute:
	call get_last_arg		;f339
	jp (hl)			;f33c
cmd_fill:
	call get_arg		;f33d
	ex de,hl		;f340
	call get_arg		;f341
	sbc hl,de		;f344
	ret c			;f346
	ld b,h			;f347
	ld c,l			;f348
	call get_last_arg		;f349
	ex de,hl		;f34c
	ld (hl),e		;f34d
	ld d,h			;f34e
	ld e,l			;f34f
	inc de			;f350
	ldir			;f351
	ret			;f353
cmd_modify:
	call get_last_arg		;f354
lf357h:
	call print_hl		;f357
	ld a,02dh		;f35a
	call conout		;f35c
	ld a,(hl)		;f35f
	call print_a		;f360
	call print_space		;f363
	ex de,hl		;f366
	call get_hex_word		;f367
	ex de,hl		;f36a
	push af			;f36b
	cp 00dh			;f36c
	call nz,print_cr		;f36e
	pop af			;f371
	jr nc,lf37fh		;f372
	cp 00dh			;f374
	jr z,lf37eh		;f376
	cp 02dh			;f378
	ret nz			;f37a
	dec hl			;f37b
	jr lf357h		;f37c
lf37eh:
	ld e,(hl)		;f37e
lf37fh:
	cp 00dh			;f37f
	ld a,00dh		;f381
	call nz,conout		;f383
	ld a,d			;f386
	or a			;f387
	jp nz,what_error		;f388
	ld (hl),e		;f38b
	ld a,(hl)		;f38c
	cp e			;f38d
	jp nz,what_error		;f38e
	inc hl			;f391
	jr lf357h		;f392
cmd_out:
	call get_arg		;f394
	ld a,h			;f397
	or a			;f398
	jp nz,what_error		;f399
	ld c,l			;f39c
	call get_last_arg		;f39d
	ld a,h			;f3a0
	or a			;f3a1
	jp nz,what_error		;f3a2
	out (c),l		;f3a5
	ret			;f3a7
cmd_in:
	call get_last_arg		;f3a8
	ld a,h			;f3ab
	or a			;f3ac
	jp nz,what_error		;f3ad
	ld c,l			;f3b0
	in a,(c)		;f3b1
	call print_a		;f3b3
	jp print_cr		;f3b6
cmd_dump:
	call get_arg		;f3b9
	ex de,hl		;f3bc
	call get_last_arg		;f3bd
	ld c,l			;f3c0
	ex de,hl		;f3c1
lf3c2h:
	call print_hl		;f3c2
	ld b,010h		;f3c5
lf3c7h:
	call print_space		;f3c7
	ld a,(hl)		;f3ca
	call print_a		;f3cb
	inc hl			;f3ce
	ld a,009h		;f3cf
	cp b			;f3d1
	jr nz,lf3dch		;f3d2
	call print_space		;f3d4
	ld a,02dh		;f3d7
	call conout		;f3d9
lf3dch:
	djnz lf3c7h		;f3dc
	call print_cr		;f3de
	dec c			;f3e1
	jr nz,lf3c2h		;f3e2
	ret			;f3e4
conin_echo:
	call kbd_get		;f3e5
conout:
	cp 00dh			;f3e8
	jr nz,conout_raw		;f3ea
	call conout_raw		;f3ec
	ld a,00ah		;f3ef
	call conout_raw		;f3f1
	ld a,00dh		;f3f4
	ret			;f3f6
conout_raw:
	push af			;f3f7
lf3f8h:
	in a,(IVCSTA)		;f3f8
	rrca			;f3fa
	jr c,lf3f8h		;f3fb
	pop af			;f3fd
	out (IVCDAT),a		;f3fe
	ret			;f400
kbd_status:
	ld a,01bh		;f401
	call conout_raw		;f403
	ld a,06bh		;f406
	call conout_raw		;f408
	call uart_read		;f40b
	ret			;f40e
kbd_get:
	ld a,01bh		;f40f
	call conout_raw		;f411
	ld a,04bh		;f414
	call conout_raw		;f416
	call uart_read		;f419
	cp 061h			;f41c
	ret c			;f41e
	cp 07bh			;f41f
	ret nc			;f421
	and 05fh		;f422
	ret			;f424
uart_read:
	in a,(IVCSTA)		;f425
	rlca			;f427
	jr c,uart_read		;f428
	in a,(IVCDAT)		;f42a
	ret			;f42c
sign_on_msg:
	defb "  ",1ah,1bh,"D",0ah,0ah,0ah,"                "		;f42d
	defb "  ****  Quantum QM2000  ****",0dh,0ah,0ah,00h		;f445

; unused ROM space
	defs 0f800h-$,0ffh
	end
