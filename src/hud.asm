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
; The HUD owns SATB entries 0..6 (in front of everything) and VRAM cells at
; HUD_VRAM: 0-5 bar (rewritten as it changes), 6-7 icon, 8-11 text, 12 lives.
;
; ***************************************************************************

		include	"hud.inc"

HUD_VRAM	=	$7700		; After the enemy cells (up to $76FF), 32 cells.
HUD_PAT		=	HUD_VRAM >> 5		; Pattern index of slot 0 (even).

	.if	EN_VRAM_END > HUD_VRAM
	.fail	Enemy cells overrun the HUD cells
	.endif
HUD_ENTRIES	=	7
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

		st0	#VDC_MAWR		; SATB entries 0..6.
		st1	#<SATB_ADDR
		st2	#>SATB_ADDR
		st0	#VDC_VWR
		clx
.ent:		lda	hud_ty, x		; y
		sta	VDC_DL
		lda	#>HUD_Y
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
hud_reset:	lda	#$FF			; Force a full redraw.
		sta	<hud_drawn
		sta	<hud_icon
		sta	<hud_lives_dr
		lda	#PLAYER_HP
		sta	<hud_disp
		rts

		; lives, icon, bar 0-1, bar 2-3, bar 4-5, ROUN, D 1
hud_ty:		db	<HUD_Y, <HUD_Y, <HUD_Y, <HUD_Y, <HUD_Y, <HUD_Y, <HUD_Y
hud_tx:		db	32 + 8, 32 + 24, 32 + 56, 32 + 88, 32 + 120, 32 + 176, 32 + 208
hud_tpat:	db	12 * 2, 6 * 2, 0, 2 * 2, 4 * 2, 8 * 2, 10 * 2
hud_twide:	db	$00, $01, $01, $01, $01, $01, $01

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
.done:		plp
		rts

; ---------------------------------------------------------------------------
; player_died - lose a life and restart the stage (no game over screen yet:
; out of lives starts again with START_LIVES).

player_died:	dec	<lives
		bne	!+
		lda	#START_LIVES
		sta	<lives
!:		jsr	hud_reset
		jmp	stage_start
