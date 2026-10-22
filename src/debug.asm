; ***************************************************************************
;
; Rastan - checkpoints and the debug menu.
;
; Checkpoints are the arcade's (continue table $5073A): round 1 restarts at
; segments 0, 4, 8, 12, 16 and 19. A death restarts at the last one the camera
; has reached, with the arcade's camera and Rastan's position there. Restarting
; fast-forwards the column stream from column 0 with the display off, so the
; VRAM tile cache ends up exactly as if the stage had been played to there.
;
; Debug menu: SELECT opens it (the core's soft reset is RUN held + SELECT).
; UP/DOWN pick a line, LEFT/RIGHT change a value, I applies, SELECT or II
; closes. While it is open the game is frozen, sprites are hidden, and the
; menu font sits in the enemy sprite cells. Closing re-streams the resident
; window of columns, which rewrites the tile map exactly (every pattern a
; window column uses is still resident), reloads the enemy cells and the BG
; colors, and the game carries on.
;
; This code lives in bank DEBUG_BANK, mapped in MPR2 ($4000) all the time.
;
; ***************************************************************************

NUM_CP		=	6

FONT_VRAM	=	$5C00			; Enemy cells (reloaded on close).
FONT_TILE	=	FONT_VRAM >> 4		; Tile number of ' '.
MENU_COL	=	2			; Box position on screen (tiles).
MENU_ROW	=	3
MENU_W		=	28
MENU_H		=	22
MENU_LINES	=	8			; Selectable lines.

		.zp
cur_cp:		ds	1		; Checkpoint a death restarts at.
dbg_god:	ds	1		; Nonzero: nothing hurts Rastan.
dbg_noenemy:	ds	1		; Nonzero: no enemies.
dbg_slow:	ds	1		; Logic runs when (loop_cnt & dbg_slow) == 0.
dbg_sel:	ds	1
dbg_cp:		ds	1		; Warp target shown in the menu.
dbg_ptr:	ds	2
dbg_col:	ds	1		; Tile map column / row of the screen's corner.
dbg_row:	ds	1
dbg_x:		ds	1		; Text cursor (tiles, relative to the screen).
dbg_y:		ds	1
dbg_pal:	ds	1		; $00 normal, $10 highlighted (BAT palette hi nibble).
dbg_num:	ds	2
dbg_digits:	ds	1
dbg_t:		ds	1		; put_char scratch.
dbg_line:	ds	1

		.code

; ---------------------------------------------------------------------------
; Checkpoints: camera x, camera y (port scroll_y), Rastan's x and y (world).
; Measured in the arcade by starting the round at each checkpoint.

cp_cam_x:	dw	0, 2048, 4096, 6144, 8192, 9728
cp_cam_y:	dw	192, 160, 192, 192, 265, 265
cp_p_x:		dw	48, 2096, 4144, 6192, 8240, 9808
cp_p_y:		dw	295, 263, 295, 295, 455, 455

; checkpoint_track - once a frame: the checkpoint moves on when the camera
; reaches the next one's segment (the arcade picks it by segment).
checkpoint_track:
		lda	<cur_cp
		cmp	#NUM_CP - 1
		bcs	.done
		inc	a
		asl	a
		tax
		lda	<scroll_x + 1		; scroll_x >= cp_cam_x[cur_cp + 1]?
		cmp	cp_cam_x + 1, x
		bcc	.done
		bne	.next
		lda	<scroll_x
		cmp	cp_cam_x, x
		bcc	.done
.next:		inc	<cur_cp
.done:		rts

; checkpoint_start - (re)start the stage at checkpoint cur_cp.
checkpoint_start:
		call	set_dspoff
		lda	<cur_cp
		asl	a
		tax
		lda	cp_cam_x, x
		sta	<scroll_x
		lda	cp_cam_x + 1, x
		sta	<scroll_x + 1
		lda	cp_cam_y, x
		sta	<scroll_y
		lda	cp_cam_y + 1, x
		sta	<scroll_y + 1
		phx
		stz	<next_col		; Fast-forward the stream to the camera.
		stz	<next_col + 1
		jsr	stream_ahead
		jsr	player_init_pos
		plx
		lda	cp_p_x, x
		sta	<p_x
		lda	cp_p_x + 1, x
		sta	<p_x + 1
		lda	cp_p_y, x
		sta	<p_y
		lda	cp_p_y + 1, x
		sta	<p_y + 1
		jsr	enemies_reset
		jsr	props_reset
		jsr	dyn_reset
		jsr	dyn_update		; (sky for this column, before showing it)
		jsr	camera_update
		jsr	set_scroll_regs
		jsr	player_draw
		jsr	props_draw
		jsr	enemies_draw
		call	wait_vsync		; SATB DMA, then show the screen.
		call	set_dspon
		rts

; ---------------------------------------------------------------------------
; debug_check - once a frame, before the game logic: SELECT opens the menu.

debug_check:	lda	joytrg
		and	#JOY_SEL
		beq	!+
		jmp	debug_menu
!:		rts

; ---------------------------------------------------------------------------
; debug_menu - runs until closed.

debug_menu:	php
		sei
		lda	<vdc_crl		; Sprites off (the VBLANK IRQ writes CR).
		and	#$BF
		sta	<vdc_crl
		jsr	font_upload
		jsr	menu_colors
		plp
		lda	<cur_cp
		sta	<dbg_cp
		stz	<dbg_sel
		jsr	menu_draw

.loop:		call	wait_vsync
		php				; Keep the tile map still while open.
		sei
		st0	#VDC_BXR
		lda	<dbg_col
		asl	a
		asl	a
		asl	a
		sta	VDC_DL
		lda	<dbg_col
		lsr	a
		lsr	a
		lsr	a
		lsr	a
		lsr	a
		and	#1
		sta	VDC_DH
		st0	#VDC_BYR
		lda	<dbg_row
		asl	a
		asl	a
		asl	a
		sta	VDC_DL
		lda	<dbg_row
		lsr	a
		lsr	a
		lsr	a
		lsr	a
		lsr	a
		and	#1
		sta	VDC_DH
		plp
		lda	joytrg
		bit	#JOY_SEL		; Close.
		bne	.close
		bit	#JOY_B2
		bne	.close
		bit	#JOY_U
		beq	!+
		lda	<dbg_sel
		beq	.loop
		dec	<dbg_sel
		bra	.redraw
!:		bit	#JOY_D
		beq	!+
		lda	<dbg_sel
		cmp	#MENU_LINES - 1
		bcs	.loop
		inc	<dbg_sel
		bra	.redraw
!:		bit	#JOY_L
		beq	!+
		lda	#$FF
		jsr	menu_change
		bra	.redraw
!:		bit	#JOY_R
		beq	!+
		lda	#1
		jsr	menu_change
		bra	.redraw
!:		bit	#JOY_B1
		beq	.loop
		jsr	menu_apply		; Carry set: close the menu.
		bcs	.close
.redraw:	jsr	menu_draw
		bra	.loop

.close:		jsr	menu_close
		rts

; menu_change - LEFT/RIGHT on the selected line (A = +1 or -1).
menu_change:	ldx	<dbg_sel
		cpx	#0			; Warp target.
		bne	.god
		clc
		adc	<dbg_cp
		cmp	#NUM_CP
		bcs	.done			; (also catches -1)
		sta	<dbg_cp
		rts
.god:		cpx	#1
		bne	.enemies
		lda	<dbg_god
		eor	#1
		sta	<dbg_god
		rts
.enemies:	cpx	#2
		bne	.lives
		lda	<dbg_noenemy
		eor	#1
		sta	<dbg_noenemy
		rts
.lives:		cpx	#4
		bne	.slow
		clc
		adc	<lives
		beq	.done			; 1..9
		cmp	#10
		bcs	.done
		sta	<lives
		lda	#$FF			; Redraw the HUD's lives digit.
		sta	<hud_lives_dr
		rts
.slow:		cpx	#5
		bne	.weapon
		cmp	#1
		beq	.slower
		lda	<dbg_slow		; 0, 1, 3, 7: off, 1/2, 1/4, 1/8 speed.
		lsr	a
		sta	<dbg_slow
		rts
.slower:	lda	<dbg_slow
		cmp	#7
		bcs	.done
		sec
		rol	a
		sta	<dbg_slow
.done:		rts
.weapon:	cpx	#6			; 1 sword, 2 axe, 3 morning star, 4 fire sword.
		bne	.done
		clc
		adc	<p_weapon
		beq	.done
		cmp	#WPN_FIRE + 1
		bcs	.done
		jmp	player_set_weapon

; menu_apply - I on the selected line. Carry set to close the menu.
menu_apply:	lda	<dbg_sel
		bne	.health
		lda	<dbg_cp			; Warp: restart at that checkpoint.
		sta	<cur_cp
		jsr	menu_close_quiet
		jsr	checkpoint_start
		sec
		rts
.health:	cmp	#3
		bne	.toggle
		lda	#PLAYER_HP
		sta	<p_hp
		clc
		rts
.toggle:	cmp	#7			; Resume.
		beq	.resume
		lda	#1			; Other lines: I acts like RIGHT.
		jsr	menu_change
		clc
		rts
.resume:	sec
		rts

; menu_close - put the stage back and carry on.
menu_close:	php
		sei
		jsr	restream_window		; Tile map back as it was.
		jsr	menu_close_quiet
		plp
		lda	<dbg_noenemy		; Enemies switched off: clear them.
		beq	!+
		jsr	enemies_reset
!:		rts

; menu_close_quiet - colors, enemy cells and sprites back (no tile map).
menu_close_quiet:
		php
		sei
		lda	#^palette_data		; BG colors from ROM, then the run-time
		tam3				; ones (the sky follows next_col).
		stz	VCE_CTA + 0
		stz	VCE_CTA + 1
		tia	palette_data, VCE_CTW, 512
		jsr	dyn_reset
		jsr	dyn_update
		jsr	enemies_load
		lda	<vdc_crl		; Sprites back on.
		ora	#$40
		sta	<vdc_crl
		plp
		rts

; restream_window - stream the resident window of columns again.
restream_window:
		lda	<next_col		; tmp = next_col (end)
		sta	<tmp
		lda	<next_col + 1
		sta	<tmp + 1
		lda	<next_col		; next_col -= STAGE_WINDOW (min 0)
		sec
		sbc	#STAGE_WINDOW
		sta	<next_col
		lda	<next_col + 1
		sbc	#0
		sta	<next_col + 1
		bcs	.loop
		stz	<next_col
		stz	<next_col + 1
.loop:		lda	<next_col
		cmp	<tmp
		bne	.go
		lda	<next_col + 1
		cmp	<tmp + 1
		beq	.done
.go:		jsr	stream_column
		bra	.loop
.done:		rts

; font_upload - 64 characters ($20-$5F) as 4bpp tiles: text color 15 on 1.
font_upload:	st0	#VDC_MAWR
		st1	#<FONT_VRAM
		st2	#>FONT_VRAM
		st0	#VDC_VWR
		lda	#^debug_font
		tam3
		lda	#<debug_font
		sta	<dbg_ptr
		lda	#>debug_font
		sta	<dbg_ptr + 1
		ldx	#64
.char:		cly				; planes 0/1: $FF / row
.p01:		lda	#$FF
		sta	VDC_DL
		lda	[dbg_ptr], y
		sta	VDC_DH
		iny
		cpy	#8
		bne	.p01
		cly				; planes 2/3: row / row
.p23:		lda	[dbg_ptr], y
		sta	VDC_DL
		sta	VDC_DH
		iny
		cpy	#8
		bne	.p23
		lda	<dbg_ptr
		clc
		adc	#8
		sta	<dbg_ptr
		bcc	!+
		inc	<dbg_ptr + 1
!:		dex
		bne	.char
		rts

; menu_colors - palette 0: colors 1 (box) and 15 (text); palette 1 the same
; with a yellow highlight.
menu_colors:	stz	VCE_CTA + 1
		ldx	#3
.loop:		lda	.addr, x
		sta	VCE_CTA + 0
		lda	.col_lo, x
		sta	VCE_CTW + 0
		lda	.col_hi, x
		sta	VCE_CTW + 1
		dex
		bpl	.loop
		rts
		;	box, text, box, highlighted text (GRB 9-bit: g<<6 | r<<3 | b)
.addr:		db	$01, $0F, $11, $1F
.col_lo:	db	<$002, <$1FF, <$002, <$1F8
.col_hi:	db	>$002, >$1FF, >$002, >$1F8

; ---------------------------------------------------------------------------
; Drawing. The menu draws into the tile map under the screen; the screen is
; snapped to the tile grid while it is open.

menu_draw:	lda	<scroll_x		; dbg_col = scroll_x >> 3 (mod 64)
		sta	<dbg_num
		lda	<scroll_x + 1
		lsr	a
		ror	<dbg_num
		lsr	a
		ror	<dbg_num
		lsr	a
		ror	<dbg_num
		lda	<dbg_num
		and	#63
		sta	<dbg_col
		lda	<scroll_y
		sta	<dbg_num
		lda	<scroll_y + 1
		lsr	a
		ror	<dbg_num
		lsr	a
		ror	<dbg_num
		lsr	a
		ror	<dbg_num
		lda	<dbg_num
		and	#63
		sta	<dbg_row

		php
		sei
		stz	<dbg_pal		; Clear the box.
		lda	#MENU_ROW
		sta	<dbg_y
.clr:		lda	#MENU_COL
		sta	<dbg_x
		ldx	#MENU_W
.clrc:		lda	#' '
		jsr	put_char
		dex
		bne	.clrc
		inc	<dbg_y
		lda	<dbg_y
		cmp	#MENU_ROW + MENU_H
		bne	.clr

		ldx	#0			; Title and position.
		ldy	#1
		lda	#<txt_title
		jsr	print_at_l
		ldx	#0
		ldy	#3
		lda	#<txt_pos
		jsr	print_at_l
		ldx	#2
		ldy	#3
		lda	<p_x
		sta	<dbg_num
		lda	<p_x + 1
		sta	<dbg_num + 1
		jsr	print_num5
		ldx	#10
		ldy	#3
		lda	<p_y
		sta	<dbg_num
		lda	<p_y + 1
		sta	<dbg_num + 1
		jsr	print_num5
		ldx	#21
		ldy	#3
		lda	<cur_cp
		jsr	print_digit

		stz	<dbg_line		; The selectable lines, box rows 5, 7, ...
.line:		stz	<dbg_pal
		lda	<dbg_line
		cmp	<dbg_sel
		bne	!+
		lda	#$10
		sta	<dbg_pal
!:		lda	<dbg_line
		asl	a
		clc
		adc	#5
		tay
		ldx	<dbg_line
		lda	menu_labels, x
		ldx	#0
		jsr	print_at_l		; (leaves dbg_y on the line's row)
		ldy	<dbg_line
		jsr	menu_value
		inc	<dbg_line
		lda	<dbg_line
		cmp	#MENU_LINES
		bne	.line

		stz	<dbg_pal
		ldx	#0
		ldy	#21
		lda	#<txt_help
		jsr	print_at_l
		plp
		rts

; menu_value - the value column of line Y (row in dbg_y).
menu_value:	cpy	#0
		bne	.god
		lda	<dbg_cp			; Warp: "< n >"
		jmp	print_digit_arrows
.god:		cpy	#1
		bne	.enemies
		lda	<dbg_god
		jmp	print_onoff
.enemies:	cpy	#2
		bne	.lives
		lda	<dbg_noenemy
		eor	#1
		jmp	print_onoff
.lives:		cpy	#4
		bne	.slow
		lda	<lives
		jmp	print_digit_arrows
.slow:		cpy	#5
		bne	.weapon
		lda	<dbg_slow		; 0, 1, 3, 7 -> speed 1, 2, 4, 8
		inc	a
		jmp	print_digit_arrows_div
.weapon:	cpy	#6
		bne	.done
		lda	<p_weapon
		jmp	print_digit_arrows
.done:		rts

; ---------------------------------------------------------------------------
; Text helpers. Coordinates are relative to the box; the text is upper case.

; print_at_l - string txt page (A = low byte) at box (X, Y).
print_at_l:	sta	<dbg_ptr
		lda	#>txt_page
		sta	<dbg_ptr + 1
		txa
		clc
		adc	#MENU_COL + 1
		sta	<dbg_x
		tya
		clc
		adc	#MENU_ROW
		sta	<dbg_y
		cly
.ch:		lda	[dbg_ptr], y
		beq	.done
		phy
		jsr	put_char
		ply
		iny
		bra	.ch
.done:		rts

; print_onoff - A nonzero "ON", else "OFF", at column dbg_x of row dbg_y.
print_onoff:	ldx	#MENU_COL + 1 + 20
		stx	<dbg_x
		tax
		lda	#<txt_off
		cpx	#0
		beq	!+
		lda	#<txt_on
!:		sta	<dbg_ptr
		lda	#>txt_page
		sta	<dbg_ptr + 1
		cly
.ch:		lda	[dbg_ptr], y
		beq	.done
		phy
		jsr	put_char
		ply
		iny
		bra	.ch
.done:		rts

; print_digit_arrows - "< n >" for A = 0..9.
print_digit_arrows:
		pha
		ldx	#MENU_COL + 1 + 20
		stx	<dbg_x
		lda	#'<'
		jsr	put_char
		lda	#' '
		jsr	put_char
		pla
		clc
		adc	#'0'
		jsr	put_char
		lda	#' '
		jsr	put_char
		lda	#'>'
		jmp	put_char

; print_digit_arrows_div - "1/n" for A = 1, 2, 4, 8 ("OFF" for 1).
print_digit_arrows_div:
		cmp	#1
		bne	!+
		cla
		jmp	print_onoff
!:		pha
		ldx	#MENU_COL + 1 + 20
		stx	<dbg_x
		lda	#'1'
		jsr	put_char
		lda	#'/'
		jsr	put_char
		pla
		clc
		adc	#'0'
		jmp	put_char

; print_digit - A = 0..9 at box (X, Y).
print_digit:	pha
		txa
		clc
		adc	#MENU_COL + 1
		sta	<dbg_x
		tya
		clc
		adc	#MENU_ROW
		sta	<dbg_y
		pla
		clc
		adc	#'0'
		jmp	put_char

; print_num5 - dbg_num as 5 decimal digits at box (X, Y).
print_num5:	txa
		clc
		adc	#MENU_COL + 1
		sta	<dbg_x
		tya
		clc
		adc	#MENU_ROW
		sta	<dbg_y
		ldx	#0
.digit:		stz	<dbg_digits
.sub:		lda	<dbg_num		; while num >= pow10[x]: subtract
		sec
		sbc	.pow_lo, x
		tay
		lda	<dbg_num + 1
		sbc	.pow_hi, x
		bcc	.out
		sta	<dbg_num + 1
		sty	<dbg_num
		inc	<dbg_digits
		bra	.sub
.out:		lda	<dbg_digits
		clc
		adc	#'0'
		phx
		jsr	put_char
		plx
		inx
		cpx	#5
		bne	.digit
		rts
.pow_lo:	db	<10000, <1000, <100, <10, <1
.pow_hi:	db	>10000, >1000, >100, >10, >1

; put_char - A at screen tile (dbg_x, dbg_y), then dbg_x++. IRQ must be off.
put_char:	sec
		sbc	#' '
		clc
		adc	#<FONT_TILE
		pha
		lda	<dbg_y			; MAWR = ((row + y) & 63) * 64 + ((col + x) & 63)
		clc
		adc	<dbg_row
		and	#63
		stz	<dbg_t
		lsr	a
		ror	<dbg_t
		lsr	a
		ror	<dbg_t			; a = hi, dbg_t = bits 6-7 of lo
		pha
		lda	<dbg_x
		clc
		adc	<dbg_col
		and	#63
		ora	<dbg_t
		st0	#VDC_MAWR
		sta	VDC_DL
		pla
		sta	VDC_DH
		st0	#VDC_VWR
		pla
		sta	VDC_DL
		lda	#>FONT_TILE
		ora	<dbg_pal
		sta	VDC_DH
		inc	<dbg_x
		rts

; ---------------------------------------------------------------------------
; Text. Every string lives in one 256-byte page (print_at_l takes the low byte).

		.align	256
txt_page:
txt_title:	db	"RASTAN DEBUG MENU", 0
txt_pos:	db	"X       Y       CP", 0
txt_on:		db	"ON ", 0
txt_off:	db	"OFF", 0
txt_help:	db	"SELECT CLOSE  I APPLY", 0
txt_warp:	db	"WARP TO CHECKPOINT", 0
txt_god:	db	"INVINCIBLE", 0
txt_enemies:	db	"ENEMIES", 0
txt_health:	db	"REFILL HEALTH", 0
txt_lives:	db	"LIVES", 0
txt_slow:	db	"SLOW MOTION", 0
txt_weapon:	db	"WEAPON", 0
txt_resume:	db	"RESUME", 0
txt_end:

	.if	(txt_end - txt_page) > 256
	.fail	debug menu strings must fit in one page
	.endif

; Line labels (low bytes in txt_page).
menu_labels:	db	<txt_warp, <txt_god, <txt_enemies, <txt_health
		db	<txt_lives, <txt_slow, <txt_weapon, <txt_resume
