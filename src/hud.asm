; ***************************************************************************
;
; Rastan - HUD: lives, Rastan icon, health bar, "ROUND 1" (sprites).
;
; Cells come from the arcade's own HUD sprites (tools/pce_hud.py). The bar is
; 6 cells x 8 levels = 48 units for full health (arcade: 12288 health, 256 per
; unit); a lizardman hit costs 12 units. As in the arcade, the bar drains
; toward the new value a unit every 2 frames, and the icon flashes while
; Rastan is invulnerable.
;
; The HUD owns SATB entries 0..11 (in front of everything) and VRAM cells at
; HUD_VRAM: 0-5 bar (rewritten as it changes), 6-7 icon, 8-11 text, 12 lives,
; 16-25 the top line.
;
; Top line (arcade $10C11C score, $10C140 high score: 3 BCD bytes, low byte
; first, in hundreds; the arcade's high score starts at 273100): "1UP" and
; "HIGH SCORE" with the numbers 8 px below, from the arcade's own cells. The
; label rows are static; the digit rows of those cells are rewritten from an
; 8x8 font when a number changes. Lizardmen are worth 300, blue throwers and
; bats 200.
;
; ***************************************************************************

		include	"hud.inc"

HUD_VRAM	=	$7700		; After the enemy cells (up to $76FF), 32 cells.
HUD_PAT		=	HUD_VRAM >> 5		; Pattern index of slot 0 (even).

	.if	EN_VRAM_END > HUD_VRAM
	.fail	Enemy cells overrun the HUD cells
	.endif
HUD_ENTRIES	=	12
HUD_TOP_SLOT	=	16		; Top line cells: 4 left, 6 right.
TOP_Y		=	8 + 64		; Screen y 8.
SCORE_CHARS	=	8		; Left block: 6 digits, "00".
HIGH_CHARS	=	12		; Right block: 3 blank, 6 digits, "00", blank.
FONT_BLANK	=	10
HUD_Y		=	200 + 64		; Screen y 200.
HUD_PALETTE	=	15
START_LIVES	=	3

		.zp
hud_disp:	ds	1		; Bar units shown (0..48).
hud_drawn:	ds	1		; Units currently in VRAM ($FF = redraw).
hud_icon:	ds	1		; Icon frame in VRAM.
hud_lives_dr:	ds	1		; Lives digit in VRAM.
hud_tick:	ds	1
lives:		ds	1
hsrc:		ds	2
score:		ds	3		; BCD hundreds, low byte first (arcade layout).
hiscore:	ds	3
hud_sdirty:	ds	1		; Numbers to redraw.
hud_cell:	ds	1

		.bss
hud_chars:	ds	HIGH_CHARS

		.code

; ---------------------------------------------------------------------------
; hud_init - palette, static cells and the 7 SATB entries.

hud_init:	php
		sei
		lda	#^hud_palette		; Sprite palette 15 (VCE 496).
		tam3
		lda	#<(256 + HUD_PALETTE * 16)
		sta	VCE_CTA + 0
		lda	#>(256 + HUD_PALETTE * 16)
		sta	VCE_CTA + 1
		tia	hud_palette, VCE_CTW, 32

		ldx	#HUD_TEXT		; "ROUND 1" -> slots 8..11.
		ldy	#8
		jsr	hud_copy
		ldx	#HUD_TEXT + 1
		ldy	#9
		jsr	hud_copy
		ldx	#HUD_TEXT + 2
		ldy	#10
		jsr	hud_copy
		ldx	#HUD_TEXT + 3
		ldy	#11
		jsr	hud_copy
		ldx	#HUD_ICON + 2		; Icon right half -> slot 7.
		ldy	#7
		jsr	hud_copy
		ldx	#HUD_TOP		; Top line labels -> slots 16..25.
		ldy	#HUD_TOP_SLOT
!:		phy
		jsr	hud_copy
		ply
		inx
		iny
		cpy	#HUD_TOP_SLOT + 10
		bne	!-

		st0	#VDC_MAWR		; SATB entries 0..6.
		st1	#<SATB_ADDR
		st2	#>SATB_ADDR
		st0	#VDC_VWR
		clx
.ent:		lda	hud_ty, x		; y
		sta	VDC_DL
		lda	hud_tyh, x
		sta	VDC_DH
		lda	hud_tx, x		; x
		sta	VDC_DL
		stz	VDC_DH
		lda	hud_tpat, x		; pattern
		clc
		adc	#<HUD_PAT
		sta	VDC_DL
		lda	#>HUD_PAT
		adc	#0
		sta	VDC_DH
		lda	#$80 + HUD_PALETTE	; In front; 16 or 32 wide.
		sta	VDC_DL
		lda	hud_twide, x
		sta	VDC_DH
		inx
		cpx	#HUD_ENTRIES
		bne	.ent
		plp

		lda	#START_LIVES
		sta	<lives
		stz	<score
		stz	<score + 1
		stz	<score + 2
		lda	#$31			; 273100
		sta	<hiscore
		lda	#$27
		sta	<hiscore + 1
		stz	<hiscore + 2
hud_reset:	lda	#1
		sta	<hud_sdirty
		lda	#$FF			; Force a full redraw.
		sta	<hud_drawn
		sta	<hud_icon
		sta	<hud_lives_dr
		lda	#PLAYER_HP
		sta	<hud_disp
		rts

		; lives, icon, bar 0-1, bar 2-3, bar 4-5, ROUN, D 1,
		; top line: left 2 x 32, right 3 x 32 (arcade x - 16)
hud_ty:		db	<HUD_Y, <HUD_Y, <HUD_Y, <HUD_Y, <HUD_Y, <HUD_Y, <HUD_Y
		db	<TOP_Y, <TOP_Y, <TOP_Y, <TOP_Y, <TOP_Y
hud_tyh:	db	>HUD_Y, >HUD_Y, >HUD_Y, >HUD_Y, >HUD_Y, >HUD_Y, >HUD_Y
		db	>TOP_Y, >TOP_Y, >TOP_Y, >TOP_Y, >TOP_Y
hud_tx:		db	32 + 8, 32 + 24, 32 + 56, 32 + 88, 32 + 120, 32 + 176, 32 + 208
		db	32 + 0, 32 + 32, 32 + 96, 32 + 128, 32 + 160
hud_tpat:	db	12 * 2, 6 * 2, 0, 2 * 2, 4 * 2, 8 * 2, 10 * 2
		db	16 * 2, 18 * 2, 20 * 2, 22 * 2, 24 * 2
hud_twide:	db	$00, $01, $01, $01, $01, $01, $01
		db	$01, $01, $01, $01, $01

; hud_copy - copy hud.bin cell X to HUD VRAM slot Y (IRQ must be off).
hud_copy:	phx
		st0	#VDC_MAWR		; MAWR = HUD_VRAM + Y * 64
		tya
		lsr	a
		lsr	a
		sta	<hsrc + 1
		tya				; lo = (Y & 3) << 6
		and	#3
		lsr	a
		ror	a
		ror	a
		sta	VDC_DL
		lda	<hsrc + 1
		clc
		adc	#>HUD_VRAM
		sta	VDC_DH
		st0	#VDC_VWR
		lda	#^hud_cells		; Source = hud_cells + X * 128.
		tam3
		inc	a
		tam4
		stz	<hsrc + 1
		txa
		lsr	a
		ror	<hsrc + 1
		sta	<hsrc			; hi byte for now
		lda	<hsrc + 1		; lo = (X & 1) * 128
		pha
		lda	<hsrc
		clc
		adc	#>hud_cells
		sta	<hsrc + 1
		pla
		clc
		adc	#<hud_cells
		sta	<hsrc
		bcc	!+
		inc	<hsrc + 1
!:		cly
.w:		lda	[hsrc], y
		sta	VDC_DL
		iny
		lda	[hsrc], y
		sta	VDC_DH
		iny
		bpl	.w			; 128 bytes
		plx
		rts

; ---------------------------------------------------------------------------
; hud_update - once a frame, after the player update (VDC writes, IRQ off).

hud_update:	php
		sei
		; Bar: drain toward p_hp a unit every 2 frames, refill at once.
		lda	<p_hp
		cmp	<hud_disp
		bcs	.set			; target >= shown: show it now
		inc	<hud_tick
		lda	<hud_tick
		and	#1
		bne	.bar
		dec	<hud_disp
		bra	.bar
.set:		sta	<hud_disp
.bar:		lda	<hud_disp
		cmp	<hud_drawn
		beq	.icon
		sta	<hud_drawn
		ldy	#0			; cell y: level = clamp(disp - 8y, 0, 8)
.cell:		tya
		asl	a
		asl	a
		asl	a
		sta	<hsrc
		lda	<hud_disp
		sec
		sbc	<hsrc
		bcs	!+
		cla
!:		cmp	#9
		bcc	!+
		lda	#8
!:		tax				; hud cell = HUD_LEVEL0 + level
		phy
		jsr	hud_copy
		ply
		iny
		cpy	#6
		bne	.cell

.icon:		ldx	#HUD_ICON		; Flash (971) every 4 frames while invulnerable.
		lda	<p_invuln
		beq	!+
		lda	<p_frame
		and	#4
		beq	!+
		inx
!:		cpx	<hud_icon
		beq	.lives
		stx	<hud_icon
		ldy	#6
		jsr	hud_copy

.lives:		lda	<lives			; Show spare lives, as the arcade does.
		dec	a
		cmp	<hud_lives_dr
		beq	.done
		sta	<hud_lives_dr
		clc
		adc	#HUD_DIGIT0
		tax
		ldy	#12
		jsr	hud_copy
.done:		lda	<hud_sdirty
		beq	!+
		stz	<hud_sdirty
		jsr	draw_numbers
!:		plp
		rts

; ---------------------------------------------------------------------------
; score_add - A = points in hundreds (BCD): add, keep the high score, redraw.

score_add:	php
		sei
		sed
		clc
		adc	<score
		sta	<score
		lda	<score + 1
		adc	#0
		sta	<score + 1
		lda	<score + 2
		adc	#0
		sta	<score + 2
		cld
		lda	<hiscore + 2		; score > high score?
		cmp	<score + 2
		bne	!+
		lda	<hiscore + 1
		cmp	<score + 1
		bne	!+
		lda	<hiscore
		cmp	<score
!:		bcs	!+
		lda	<score
		sta	<hiscore
		lda	<score + 1
		sta	<hiscore + 1
		lda	<score + 2
		sta	<hiscore + 2
!:		lda	#1
		sta	<hud_sdirty
		plp
		rts

; draw_numbers - both numbers into the digit rows of the top line cells.
draw_numbers:	ldx	#<score
		ldy	#0			; Left block: chars 0..7.
		jsr	number_chars
		lda	#HUD_TOP_SLOT
		ldx	#SCORE_CHARS / 2
		jsr	draw_chars
		lda	#FONT_BLANK		; Right block: blank, blank, blank,
		sta	hud_chars
		sta	hud_chars + 1
		sta	hud_chars + 2
		sta	hud_chars + 11		; ... and blank at the end.
		ldx	#<hiscore
		ldy	#3
		jsr	number_chars
		lda	#HUD_TOP_SLOT + 4
		ldx	#HIGH_CHARS / 2
		jmp	draw_chars

; number_chars - the 3-byte BCD number at zp X as 6 digits (leading zeros
; blank, a zero number shows only "00") then "00", into hud_chars from Y.
number_chars:	lda	#FONT_BLANK		; Leading zeros blank while ctmp is set.
		sta	<ctmp
		lda	#3
		sta	<hud_cell
		inx				; Most significant byte first.
		inx
.byte:		lda	<0, x
		lsr	a
		lsr	a
		lsr	a
		lsr	a
		jsr	.digit
		lda	<0, x
		and	#$0F
		jsr	.digit
		dex
		dec	<hud_cell
		bne	.byte
		cla				; "00"
		sta	hud_chars, y
		sta	hud_chars + 1, y
		rts
.digit:		bne	!+
		lda	<ctmp			; A zero: blank while leading.
		sta	hud_chars, y
		iny
		rts
!:		stz	<ctmp			; (no longer leading)
		sta	hud_chars, y
		iny
		rts

; draw_chars - X cells from HUD slot A: the bottom 8 rows of each, from
; hud_chars (two 8 px chars per cell). IRQ must be off.
draw_chars:	sta	<hud_cell
		stx	<cty
		cly				; char index
.cell:		clx				; plane
.plane:		st0	#VDC_MAWR		; HUD_VRAM + cell * 64 + plane * 16 + 8
		lda	<hud_cell
		lsr	a
		lsr	a
		clc
		adc	#>HUD_VRAM
		sta	<hsrc + 1
		lda	<hud_cell
		and	#3
		lsr	a
		ror	a
		ror	a			; (cell & 3) << 6
		sta	<hsrc
		txa
		asl	a
		asl	a
		asl	a
		asl	a
		ora	#8
		ora	<hsrc
		sta	VDC_DL
		lda	<hsrc + 1
		sta	VDC_DH
		st0	#VDC_VWR
		phx
		phy
		lda	hud_chars + 1, y	; right char -> low byte
		jsr	.font
		sta	<ctx
		lda	<hsrc + 1
		sta	<ctx + 1
		lda	hud_chars, y		; left char -> high byte
		jsr	.font
		ldy	#0
.row:		lda	[ctx], y
		sta	VDC_DL
		lda	[hsrc], y
		sta	VDC_DH
		iny
		cpy	#8
		bne	.row
		ply
		plx
		inx
		cpx	#4
		bne	.plane
		iny
		iny
		inc	<hud_cell
		dec	<cty
		bne	.cell
		rts
.font:		; hsrc = hud_font + char * 32 + plane * 8 (X = plane); A = low byte
		stz	<hsrc + 1
		asl	a
		asl	a
		asl	a
		asl	a
		rol	<hsrc + 1
		asl	a
		rol	<hsrc + 1
		sta	<hsrc
		txa
		asl	a
		asl	a
		asl	a
		clc
		adc	<hsrc
		bcc	!+
		inc	<hsrc + 1
!:		clc
		adc	#<hud_font
		sta	<hsrc
		lda	<hsrc + 1
		adc	#>hud_font
		sta	<hsrc + 1
		lda	<hsrc
		rts

		include	"hudfont.inc"

; ---------------------------------------------------------------------------
; player_died - lose a life and restart the stage (no game over screen yet:
; out of lives starts again with START_LIVES).

player_died:	dec	<lives
		bne	!+
		lda	#START_LIVES		; Out of lives: a new game (the high score stays).
		sta	<lives
		stz	<score
		stz	<score + 1
		stz	<score + 2
!:		jsr	hud_reset
		jmp	stage_start
