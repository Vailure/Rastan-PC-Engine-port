; ***************************************************************************
;
; Rastan - the floor spears of the castle's first room.
;
; Measured in the arcade (sim/scripts/spikes.txt): two traps (markers $46 at
; x 8328 and 8488) of two spears 16 px apart, drawn as sprites over a slot
; cover in the floor (top y 320). A spear's head rests at y 318; it rises
; 2 px a frame for 31 frames to y 256, stays 3 frames, sinks back in 31 and
; rests; the cycle is 163 frames, the second trap 32 frames behind the first.
; A spear standing out of the floor kills Rastan on touch.
;
; The three cells (cover, head, shaft) stay in VRAM at TRAP_VRAM (the end of
; the stage's tile pool, tools/pce_stage.py NUM_SLOTS); their palettes are
; sprite palettes 13 (cover) and 14 (spear). The spears take SATB entries
; after the objects' (enemies_draw).
;
; ***************************************************************************

NUM_TRAPS	=	2
TRAP_PERIOD	=	163
TRAP_FLOOR	=	320
TRAP_REST	=	318
TRAP_TOP	=	256
TRAP_VRAM	=	$4B00
TRAP_PAT	=	TRAP_VRAM >> 5		; SATB pattern of the cover (head +2, shaft +4).
TRAP_PAL_COVER	=	13
TRAP_PAL_SPEAR	=	14
TRAP_ROOM	=	8192			; They run while Rastan is in this room.

trap_x_l:	db	<8320, <8480
trap_x_h:	db	>8320, >8480
trap_delay:	db	0, 32

; traps_load - cells and palettes (enemies_load: at start, after the menu).
traps_load:	php
		sei
		lda	#^trap_cells
		tam3
		st0	#VDC_MAWR
		st1	#<TRAP_VRAM
		st2	#>TRAP_VRAM
		st0	#VDC_VWR
		tia	trap_cells, VDC_DL, 3 * 128
		lda	#^trap_palettes
		tam3
		stz	VCE_CTA + 0		; Sprite palettes 13 and 14: VCE 256 + 13 * 16.
		lda	#1
		sta	VCE_CTA + 1
		lda	#<(TRAP_PAL_COVER * 16)
		sta	VCE_CTA + 0
		tia	trap_palettes, VCE_CTW, 64
		plp
		rts

; trap_head - A = trap: head y (16-bit) in etmp for this frame.
trap_head:	tay
		lda	trap_t
		sec
		sbc	trap_delay, y
		bcs	!+
		adc	#TRAP_PERIOD
!:		cmp	#31			; Rising.
		bcs	!+
		asl	a
		eor	#$FF
		sec				; 316 - 2t
		adc	#<(TRAP_REST - 2)
		sta	<etmp
		lda	#>(TRAP_REST - 2)
		sbc	#0
		sta	<etmp + 1
		rts
!:		cmp	#34			; At the top.
		bcs	!+
		lda	#<TRAP_TOP
		sta	<etmp
		lda	#>TRAP_TOP
		sta	<etmp + 1
		rts
!:		cmp	#65			; Sinking: 256 + 2(t - 33).
		bcs	.rest
		sec
		sbc	#33
		asl	a
		clc
		adc	#<TRAP_TOP
		sta	<etmp
		lda	#>TRAP_TOP
		adc	#0
		sta	<etmp + 1
		rts
.rest:		lda	#<TRAP_REST
		sta	<etmp
		lda	#>TRAP_REST
		sta	<etmp + 1
		rts

; traps_active - carry set while Rastan is in the room (x 8192-8703, row 0).
traps_active:	lda	<p_y + 1
		bmi	.no
		lda	<p_x + 1
		and	#$FE
		cmp	#>TRAP_ROOM
		bne	.no
		sec
		rts
.no:		clc
		rts

; traps_update - once a frame (enemies_update): the clock, and the spears' touch.
traps_update:	inc	trap_t
		lda	trap_t
		cmp	#TRAP_PERIOD
		bcc	!+
		stz	trap_t
!:		jsr	traps_active
		bcc	.r
		lda	<p_state
		cmp	#ST_DEAD
		beq	.r
		lda	<dbg_god
		bne	.r
		ldx	#NUM_TRAPS - 1
.trap:		txa
		jsr	trap_head
		lda	<p_y			; Rastan above the floor (p_y - 24 < 320)?
		sec
		sbc	#<(TRAP_FLOOR + 24)
		lda	<p_y + 1
		sbc	#>(TRAP_FLOOR + 24)
		bpl	.r
		lda	<etmp			; Out of the floor (above y 312)?
		cmp	#<312
		lda	<etmp + 1
		sbc	#>312
		bcs	.next
		; Rastan's body (x +/- 12, y - 24 .. y + 24) over x .. x + 31, head .. floor?
		lda	trap_x_l, x		; p_x + 12 > x  and  p_x - 12 < x + 32
		sec
		sbc	#12
		sta	<ex
		lda	trap_x_h, x
		sbc	#0
		sta	<ex + 1
		lda	<ex
		cmp	<p_x
		lda	<ex + 1
		sbc	<p_x + 1
		bcs	.next			; x - 12 >= p_x: left of it
		lda	<ex
		clc
		adc	#32 + 24
		sta	<ex
		lda	<ex + 1
		adc	#0
		sta	<ex + 1
		lda	<p_x
		cmp	<ex
		lda	<p_x + 1
		sbc	<ex + 1
		bcs	.next			; p_x >= x + 44: right of it
		lda	<p_y			; p_y + 24 > head?
		clc
		adc	#24
		sta	<ey
		lda	<p_y + 1
		adc	#0
		sta	<ey + 1
		lda	<etmp
		cmp	<ey
		lda	<etmp + 1
		sbc	<ey + 1
		bcs	.next
		jmp	enter_dead		; Pierced.
.next:		dex
		bpl	.trap
.r:		rts

; traps_draw - SATB entries (VWR already selected, enemies_draw), en_satb counts.
traps_draw:	jsr	column_draw		; (src/column.asm)
		jsr	wall_draw
		jsr	weights_draw		; (src/weights.asm)
		jsr	traps_active
		bcc	.r
		ldx	#NUM_TRAPS - 1
.trap:		txa
		phx
		jsr	trap_head
		plx
		lda	trap_x_l, x		; ex = screen x of the first spear
		sec
		sbc	<scroll_x
		sta	<ex
		lda	trap_x_h, x
		sbc	<scroll_x + 1
		sta	<ex + 1
		beq	.on			; 0 .. 255
		cmp	#$FF			; or just left of the screen
		bne	.next
		lda	<ex
		cmp	#$E0
		bcc	.next
.on:		lda	<etmp			; etmp = screen y of the head
		sec
		sbc	<scroll_y
		sta	<etmp
		lda	<etmp + 1
		sbc	<scroll_y + 1
		sta	<etmp + 1
		lda	#<TRAP_FLOOR		; ey = screen y of the floor
		sec
		sbc	<scroll_y
		sta	<ey
		lda	#>TRAP_FLOOR
		sbc	<scroll_y + 1
		sta	<ey + 1
		ldy	#0			; Covers (in front), then each spear.
		jsr	.cover
		ldy	#16
		jsr	.cover
		ldy	#0
		jsr	.spear
		ldy	#16
		jsr	.spear
.next:		dex
		bpl	.trap
.r:		rts

.cover:		lda	<ey
		sta	<cy
		lda	<ey + 1
		sta	<cy + 1
		lda	#<TRAP_PAT
		sta	<ctmp
		lda	#TRAP_PAL_COVER
		jmp	trap_emit
.spear:		lda	<etmp			; The head,
		sta	<cy
		lda	<etmp + 1
		sta	<cy + 1
		lda	#<TRAP_PAT + 2
		sta	<ctmp
		lda	#TRAP_PAL_SPEAR
		jsr	trap_emit
		lda	#<TRAP_PAT + 4		; then shafts while above the floor.
		sta	<ctmp
.shaft:		lda	<cy
		clc
		adc	#16
		sta	<cy
		bcc	!+
		inc	<cy + 1
!:		lda	<cy
		cmp	<ey
		lda	<cy + 1
		sbc	<ey + 1
		bcs	.done			; (signed enough on screen)
		lda	#TRAP_PAL_SPEAR
		jsr	trap_emit
		bra	.shaft
.done:		rts

; trap_emit - one SATB entry: screen (ex + Y, cy), pattern ctmp, palette A.
trap_emit:	pha
		lda	<en_satb
		cmp	<en_cap
		bcc	!+
		pla
		rts
!:		lda	<cy			; y + 64
		clc
		adc	#64
		sta	VDC_DL
		lda	<cy + 1
		adc	#0
		and	#$03
		sta	VDC_DH
		tya				; x = ex + Y, + 32
		clc
		adc	<ex
		sta	<ctx
		lda	<ex + 1
		adc	#0
		sta	<ctx + 1
		lda	<ctx
		clc
		adc	#32
		sta	VDC_DL
		lda	<ctx + 1
		adc	#0
		and	#$03
		sta	VDC_DH
		lda	<ctmp			; pattern
		sta	VDC_DL
		lda	#>TRAP_PAT
		sta	VDC_DH
		pla				; palette, in front of the BG
		ora	#$80
		sta	VDC_DL
		st2	#0			; 16x16, no flip
		inc	<en_satb
		rts
