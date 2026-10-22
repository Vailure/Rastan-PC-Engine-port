; ***************************************************************************
;
; Rastan - stage props (approximate): objects that belong to the map.
;
; Round 1 has the brown block over the cave entrance (arcade object slot 0,
; spawned by map marker $48). It fills the 32 px gap in the ground, so it is
; solid (coll_at asks prop_coll); a down thrust that reaches it crumbles it in
; three steps (tools/pce_props.py, sim/scripts/block.txt) and opens the gap. A
; broken block stays broken until the stage restarts.
;
; One prop is active at a time: the first unbroken one within 48 px of the
; screen. Its cells are uploaded to PROP_VRAM when it becomes active.
;
; ***************************************************************************

		include	"props.inc"

PROP_VRAM	=	$4C00		; 16 cells after the BG tile pool ($1000-$4BFF).
PROP_PATTERN	=	PROP_VRAM >> 5
PROP_SATB	=	HUD_ENTRIES + 24	; 4 SATB entries after the HUD's and Rastan's.
PROP_PAL	=	8		; Sprite palette 8 (VCE 384).
PROP_MARGIN	=	48

PK_BLOCK	=	0

PS_OFF		=	0		; pr_state
PS_INTACT	=	1
PS_BREAKING	=	2

		.zp
prop_solid:	ds	1		; Nonzero: coll_at checks the prop's box.
pr_state:	ds	1
pr_index:	ds	1		; Active prop ($FF none).
pr_loaded:	ds	1		; Prop kind whose cells are in VRAM ($FF none).
pr_x:		ds	2
pr_y:		ds	2
pb_x0:		ds	2		; Solid box (world, x0 <= x < x1, y0 <= y < y1).
pb_x1:		ds	2
pb_y0:		ds	2
pb_y1:		ds	2
pr_pose:	ds	1
pr_anim:	ds	2
pr_animi:	ds	1
pr_animt:	ds	1
pr_ptr:		ds	2

		.bss
prop_done:	ds	NUM_PROPS	; Broken (until the stage restarts).

		.code

; ---------------------------------------------------------------------------
; props_init - palette (once).

props_init:	lda	#^prop_palette
		tam3
		php
		sei
		lda	#<(256 + PROP_PAL * 16)
		sta	VCE_CTA + 0
		lda	#>(256 + PROP_PAL * 16)
		sta	VCE_CTA + 1
		tia	prop_palette, VCE_CTW, 32
		plp
		lda	#$FF
		sta	<pr_loaded

; props_reset - stage (re)start: everything unbroken, nothing active.
props_reset:	ldx	#NUM_PROPS - 1
!:		stz	prop_done, x
		dex
		bpl	!-
		stz	<pr_state
		stz	<prop_solid
		lda	#$FF
		sta	<pr_index
		rts

; ---------------------------------------------------------------------------
; props_update - after player_update (the sword box is this frame's).

props_update:	lda	<pr_state
		bne	.active
		jmp	props_find

.active:	jsr	prop_onscreen		; Gone too far: drop it (unbroken).
		bcs	!+
		stz	<pr_state
		stz	<prop_solid
		lda	#$FF
		sta	<pr_index
		rts
!:		lda	<pr_state
		cmp	#PS_BREAKING
		beq	.breaking
		; Intact: a down thrust that reaches the box breaks it.
		lda	<p_state
		cmp	#ST_AIR
		bne	.r
		lda	<p_jatk
		cmp	#2
		bne	.r
		jsr	sword_box
		bcc	.r
		jsr	sword_vs_box
		bcc	.r
		lda	#PS_BREAKING
		sta	<pr_state
		ldx	<pr_index
		lda	#1
		sta	prop_done, x
		lda	#<anim_block_break
		ldy	#>anim_block_break
		jmp	prop_set_anim
.r:		rts

.breaking:	jsr	prop_anim		; Crumbles; solid until the last step ends.
		bcc	.r
		stz	<pr_state
		stz	<prop_solid
		rts

; props_find - activate the first unbroken prop within the margin.
props_find:	ldx	#0
		lda	#<stage_props
		sta	<pr_ptr
		lda	#>stage_props
		sta	<pr_ptr + 1
.next:		lda	[pr_ptr]
		cmp	#$FF
		beq	.none
		lda	prop_done, x
		bne	.skip
		ldy	#1
		lda	[pr_ptr], y
		sta	<pr_x
		iny
		lda	[pr_ptr], y
		sta	<pr_x + 1
		iny
		lda	[pr_ptr], y
		sta	<pr_y
		iny
		lda	[pr_ptr], y
		sta	<pr_y + 1
		phx
		jsr	prop_onscreen
		plx
		bcs	.found
.skip:		lda	<pr_ptr
		clc
		adc	#5
		sta	<pr_ptr
		bcc	!+
		inc	<pr_ptr + 1
!:		inx
		bra	.next
.none:		rts

.found:		stx	<pr_index
		lda	[pr_ptr]		; Kind (only PK_BLOCK so far).
		cmp	<pr_loaded
		beq	!+
		sta	<pr_loaded
		jsr	prop_upload
!:		; Solid box from the anchor.
		lda	<pr_x
		clc
		adc	#<BLOCK_X0
		sta	<pb_x0
		lda	<pr_x + 1
		adc	#>BLOCK_X0
		sta	<pb_x0 + 1
		lda	<pr_x
		clc
		adc	#<BLOCK_X1
		sta	<pb_x1
		lda	<pr_x + 1
		adc	#>BLOCK_X1
		sta	<pb_x1 + 1
		lda	<pr_y
		clc
		adc	#<BLOCK_Y0
		sta	<pb_y0
		lda	<pr_y + 1
		adc	#>BLOCK_Y0
		sta	<pb_y0 + 1
		lda	<pr_y
		clc
		adc	#<BLOCK_Y1
		sta	<pb_y1
		lda	<pr_y + 1
		adc	#>BLOCK_Y1
		sta	<pb_y1 + 1
		lda	#PS_INTACT
		sta	<pr_state
		sta	<prop_solid
		lda	#<anim_block
		ldy	#>anim_block
		jmp	prop_set_anim

; prop_onscreen - carry set if pr_x is within scroll_x - margin .. scroll_x +
; 256 + margin.
prop_onscreen:	lda	<pr_x			; d = pr_x - scroll_x + margin
		sec
		sbc	<scroll_x
		tay
		lda	<pr_x + 1
		sbc	<scroll_x + 1
		tax
		tya
		clc
		adc	#PROP_MARGIN
		tay
		txa
		adc	#0
		bmi	.no			; d < 0
		cmp	#>(256 + 2 * PROP_MARGIN)
		bcc	.yes
		bne	.no
		cpy	#<(256 + 2 * PROP_MARGIN)
		bcs	.no
.yes:		sec
		rts
.no:		clc
		rts

; prop_upload - copy the prop cells to PROP_VRAM (display time is fine: a
; one-off 2 KB write).
prop_upload:	lda	#^prop_cells
		tam3
		php
		sei
		st0	#VDC_MAWR
		st1	#<PROP_VRAM
		st2	#>PROP_VRAM
		st0	#VDC_VWR
		tia	prop_cells, VDC_DL, PROP_CELLS * 128
		plp
		rts

; ---------------------------------------------------------------------------
; prop_coll - carry set if (cx, cy) is inside the solid box (A only).

prop_coll:	lda	<cx			; cx >= x0
		cmp	<pb_x0
		lda	<cx + 1
		sbc	<pb_x0 + 1
		bvc	!+
		eor	#$80
!:		bmi	.no
		lda	<cx			; cx < x1
		cmp	<pb_x1
		lda	<cx + 1
		sbc	<pb_x1 + 1
		bvc	!+
		eor	#$80
!:		bpl	.no
		lda	<cy			; cy >= y0
		cmp	<pb_y0
		lda	<cy + 1
		sbc	<pb_y0 + 1
		bvc	!+
		eor	#$80
!:		bmi	.no
		lda	<cy			; cy < y1
		cmp	<pb_y1
		lda	<cy + 1
		sbc	<pb_y1 + 1
		bvc	!+
		eor	#$80
!:		bpl	.no
		sec
		rts
.no:		clc
		rts

; sword_vs_box - carry set if the sword box (sb_*) overlaps the solid box:
; sb_x0 < x1, x0 <= sb_x1, sb_y0 < y1, y0 <= sb_y1 (signed 16-bit).
sword_vs_box:	lda	<sb_x0			; sb_x0 < x1
		cmp	<pb_x1
		lda	<sb_x0 + 1
		sbc	<pb_x1 + 1
		bvc	!+
		eor	#$80
!:		bpl	.no
		lda	<sb_x1			; not sb_x1 < x0
		cmp	<pb_x0
		lda	<sb_x1 + 1
		sbc	<pb_x0 + 1
		bvc	!+
		eor	#$80
!:		bmi	.no
		lda	<sb_y0			; sb_y0 < y1
		cmp	<pb_y1
		lda	<sb_y0 + 1
		sbc	<pb_y1 + 1
		bvc	!+
		eor	#$80
!:		bpl	.no
		lda	<sb_y1			; not sb_y1 < y0
		cmp	<pb_y0
		lda	<sb_y1 + 1
		sbc	<pb_y0 + 1
		bvc	!+
		eor	#$80
!:		bmi	.no
		sec
		rts
.no:		clc
		rts

; ---------------------------------------------------------------------------
; Animation: (pose, frames) pairs, $FF end.

prop_set_anim:	sta	<pr_anim
		sty	<pr_anim + 1
		stz	<pr_animi
		lda	[pr_anim]
		sta	<pr_pose
		ldy	#1
		lda	[pr_anim], y
		sta	<pr_animt
		rts

; prop_anim - advance a frame; carry set when the last step has ended.
prop_anim:	dec	<pr_animt
		bne	.no
		lda	<pr_animi
		clc
		adc	#2
		sta	<pr_animi
		tay
		lda	[pr_anim], y
		cmp	#$FF
		beq	.end
		sta	<pr_pose
		iny
		lda	[pr_anim], y
		sta	<pr_animt
.no:		clc
		rts
.end:		sec
		rts

; ---------------------------------------------------------------------------
; props_draw - SATB entries PROP_SATB .. +3 (hidden when nothing is shown).

props_draw:	php				; VDC writes: IRQ held off (see stream_column).
		sei
		st0	#VDC_MAWR
		lda	#<(SATB_ADDR + PROP_SATB * 4)
		sta	VDC_DL
		lda	#>(SATB_ADDR + PROP_SATB * 4)
		sta	VDC_DH
		st0	#VDC_VWR
		ldx	#4			; Entries left to write.
		lda	<pr_state
		bne	!+
		jmp	.clear
!:		lda	<pr_pose
		asl	a
		tay
		lda	ppose_table, y
		sta	<pr_ptr
		lda	ppose_table + 1, y
		sta	<pr_ptr + 1
		lda	[pr_ptr]
		sta	<ctmp			; Piece count.
		ldy	#1
.piece:		; Screen y + 64 = pr_y - scroll_y + dy + 64.
		lda	[pr_ptr], y		; dx
		sta	<cx
		iny
		lda	[pr_ptr], y		; dy
		iny
		phx
		pha
		lda	<pr_y
		sec
		sbc	<scroll_y
		sta	<cy
		lda	<pr_y + 1
		sbc	<scroll_y + 1
		sta	<cy + 1
		pla
		jsr	.sadd			; cy += signed A
		lda	<cy
		clc
		adc	#64
		sta	VDC_DL
		lda	<cy + 1
		adc	#0
		and	#$03
		sta	VDC_DH
		lda	<pr_x			; Screen x + 32.
		sec
		sbc	<scroll_x
		sta	<cy
		lda	<pr_x + 1
		sbc	<scroll_x + 1
		sta	<cy + 1
		lda	<cx
		jsr	.sadd
		lda	<cy
		clc
		adc	#32
		sta	VDC_DL
		lda	<cy + 1
		adc	#0
		and	#$03
		sta	VDC_DH
		lda	[pr_ptr], y		; Pattern = PROP_PATTERN + cell * 2.
		iny
		asl	a
		clc
		adc	#<PROP_PATTERN
		sta	VDC_DL
		cla
		adc	#>PROP_PATTERN
		sta	VDC_DH
		lda	#PROP_PAL | $80		; Palette, in front of the BG.
		sta	VDC_DL
		lda	[pr_ptr], y		; Flips: arcade X bit 6 -> PCE bit 3 (high byte).
		iny
		tax
		and	#$80
		sta	<cx
		txa
		and	#$40
		lsr	a
		lsr	a
		lsr	a
		ora	<cx
		sta	VDC_DH
		plx
		dex
		dec	<ctmp
		bne	.piece
.clear:		txa
		beq	.done
!:		st1	#0
		st2	#0
		st1	#0
		st2	#0
		st1	#0
		st2	#0
		st1	#0
		st2	#0
		dex
		bne	!-
.done:		plp
		rts

.sadd:		pha				; cy += signed A
		clc
		adc	<cy
		sta	<cy
		pla
		and	#$80
		beq	!+
		lda	#$FF
!:		adc	<cy + 1
		sta	<cy + 1
		rts
