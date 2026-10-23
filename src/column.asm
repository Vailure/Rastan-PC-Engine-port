; ***************************************************************************
;
; Rastan - the hanging column of the castle's first room (arcade marker $47).
;
; Measured in the arcade (sim/scripts/hall.txt and variants): over the top
; corridor at x 8480 a 32 x 32 block hangs from the ceiling (y 32), and a
; piston (a shaft and a foot) comes out of it. The foot's top is 34 px below
; the block's top at rest. When the column first comes on the screen it waits
; 9 frames, then cycles every 540 frames: down 2 px every 2 frames to 112
; (the foot on the floor, y 160), held for 258 frames, up 2 px every 4 frames
; to 34, held for 54. It does no harm: it is solid, and coming down it pushes
; Rastan out to 21 px either side of its middle (x 8496) - so the corridor is
; shut most of the time, open about 140 frames in 540.
;
; Sprites like the floor spears' (no object slot), in their palette (sprite
; palette 14). Cells (tools/pce_traps.py column.bin): the block as one 32x32
; sprite, then shaft and foot, at $4E00 (the stage props' cells: the cave
; block's, outside; the castle's fire uses $4C00-$4DFF), uploaded once in the
; castle (bg_palettes clears col_on). The piston is a solid prop box (props:
; pb_*, prop_solid; the cave block, the only other, is outside).
;
; The sealing wall at the lava hall's way in (arcade marker $4D, the same
; kind of map object; hall.txt frames 4230-4700) is here too: when Rastan has
; come into the lava hall it waits 257 frames, then a 16 px wide wall of the floor
; spears' slot-cover cells ($234, 6 high, from y -415 down to the ledge at
; -320) comes out of the shaft's wall at x 8680 and moves right 2 px every 7
; frames, 31 times (to 8740), its top row growing behind it. It is solid and
; pushes: whoever still stands on the ledge before the fire (8704-8767) is
; pushed off into it.
;
; In GAME_BANK (MPR6).
;
; ***************************************************************************

COL_X		=	8480			; Block's left, top.
COL_TOP		=	32
COL_MID		=	8496
COL_PUSH	=	21			; Rastan pushed out to COL_MID +/- this.
COL_REST	=	34			; Foot's top below COL_TOP: at rest,
COL_DOWN	=	112			; down.
COL_PERIOD	=	540
COL_VRAM	=	$4E00
COL_PAT		=	COL_VRAM >> 5		; Block ($270, 32x32), shaft +8, foot +10.
COL_PAL		=	14			; (TRAP_PAL_SPEAR)

		.bss
col_act:	ds	1		; It has come on the screen: the cycle runs.
col_t:		ds	2		; Frame in the cycle.
col_len:	ds	1		; Foot's top below COL_TOP.
col_on:		ds	1		; Its cells are in VRAM.
col_y:		ds	2		; Scratch.
col_w:		ds	1
col_sy:		ds	2
col_sx:		ds	2
wl_x:		ds	2		; Draw scratch.
wl_y:		ds	2
wl_n:		ds	1

wl_act:		ds	1		; The sealing wall: seen, its clock runs.
wl_t:		ds	2		; Frames since then.
wl_step:	ds	1		; 0 (not out yet), 1-31.
wl_cnt:		ds	1		; Frames to the next step.

WL_X		=	8680			; Its column's left at step 1 (+2 a step).
WL_TOP		=	-415			; Top; 6 cells, the bottom at -319.
WL_WAIT		=	257			; Frames from seen to step 1.
WL_STEP		=	7			; Frames a step.

		.code

; column_reset - at rest, waiting to be seen (restarts).
column_reset:	stz	col_act
		lda	#COL_REST
		sta	col_len
		stz	wl_act
		stz	wl_step
		rts

; column_cells - in the castle, once: the cells into VRAM (VBLANK, fire_update).
column_cells:	lda	col_on
		bne	.r
		php
		sei
		lda	#^column_data
		tam3
		st0	#VDC_MAWR
		st1	#<COL_VRAM
		st2	#>COL_VRAM
		st0	#VDC_VWR
		tia	column_data, VDC_DL, 6 * 128
		plp
		lda	#1
		sta	col_on
.r:		rts

; column_update - once a frame in the castle (traps_update).
column_update:	lda	col_act
		bne	.run
		lda	<scroll_x		; On the screen: scroll_x in (COL_X - 256,
		sec				; COL_X + 32) and scroll_y < COL_TOP + 32
		sbc	#<(COL_X - 255)		; (the room's top row).
		sta	col_y
		lda	<scroll_x + 1
		sbc	#>(COL_X - 255)
		sta	col_y + 1
		bcc	.r
		lda	col_y
		cmp	#<(255 + 32)
		lda	col_y + 1
		sbc	#>(255 + 32)
		bcs	.r
		lda	<scroll_y		; scroll_y in -191 .. 63: scroll_y + 191
		clc				; in 0 .. 254 (unsigned)
		adc	#191
		tax
		lda	<scroll_y + 1
		adc	#0
		bne	.r
		cpx	#255
		bcs	.r2
		lda	#1
		sta	col_act
		lda	#<(COL_PERIOD - 9)	; 9 frames, then down.
		sta	col_t
		lda	#>(COL_PERIOD - 9)
		sta	col_t + 1
.r:
.r2:		jmp	column_box
.run:		inc	col_t
		bne	!+
		inc	col_t + 1
!:		lda	col_t
		cmp	#<COL_PERIOD
		lda	col_t + 1
		sbc	#>COL_PERIOD
		bcc	!+
		stz	col_t
		stz	col_t + 1
!:		lda	col_t + 1		; Length for col_t.
		bne	.late			; (256 and up)
		lda	col_t
		cmp	#78			; Down: 36 + 2 (t / 2).
		bcs	!+
		and	#$FE
		clc
		adc	#36
		bra	.set
!:		lda	#COL_DOWN		; Held down (to 333).
		bra	.set
.late:		cmp	#2			; (512 and up: at rest)
		bcs	.rest
		lda	col_t			; t - 256
		cmp	#<(334 - 256)
		bcc	.down
		cmp	#<(486 - 256)
		bcs	.rest
		sec				; Up: 110 - 2 ((t - 334) / 4).
		sbc	#<(334 - 256)
		lsr	a
		lsr	a
		asl	a
		eor	#$FF
		sec
		adc	#110
		bra	.set
.down:		lda	#COL_DOWN
		bra	.set
.rest:		lda	#COL_REST
.set:		sta	col_len
		; (fall through)

; column_box - the piston as the solid prop box: x COL_MID +/- 11 (Rastan's
; wall probes are at +/- 10: he stops 21 px from the middle), y from the
; block's top to the foot's bottom; and pushing him out when it comes down
; on him.
column_box:	lda	<p_y + 1		; (row 0: below it, the sealing wall's box)
		bpl	!+
		rts
!:		lda	#<(COL_MID - 11)
		sta	<pb_x0
		lda	#>(COL_MID - 11)
		sta	<pb_x0 + 1
		lda	#<(COL_MID + 11)
		sta	<pb_x1
		lda	#>(COL_MID + 11)
		sta	<pb_x1 + 1
		lda	#<COL_TOP
		sta	<pb_y0
		stz	<pb_y0 + 1
		lda	col_len
		clc
		adc	#COL_TOP + 16
		sta	<pb_y1
		stz	<pb_y1 + 1
		lda	#1
		sta	<prop_solid
		; Rastan's body (p_y - 24 .. p_y + 24) under the foot, and his middle
		; within 21 px: out to the nearer side.
		lda	<p_y + 1
		bne	.r			; (row 0 only: y 0-255 here)
		lda	<p_y
		sec
		sbc	#24
		bcc	!+
		cmp	<pb_y1
		bcs	.r
!:		lda	<p_x
		sec
		sbc	#<(COL_MID - COL_PUSH + 1)
		sta	col_y
		lda	<p_x + 1
		sbc	#>(COL_MID - COL_PUSH + 1)
		bne	.r			; (p_x - 8476 in 0..40: inside)
		lda	col_y
		cmp	#2 * COL_PUSH - 1
		bcs	.r
		cmp	#COL_PUSH - 1		; Right of the middle (8496 on): right.
		bcs	.right
		lda	#<(COL_MID - COL_PUSH - 1)
		sta	<p_x
		lda	#>(COL_MID - COL_PUSH - 1)
		sta	<p_x + 1
.r:		rts
.right:		lda	#<(COL_MID + COL_PUSH)
		sta	<p_x
		lda	#>(COL_MID + COL_PUSH)
		sta	<p_x + 1
		rts

; column_draw - SATB entries (traps_draw): the block, the shaft's pieces
; (from the foot up, 16 px apart, while more than 16 px below the block's
; top), the foot.
column_draw:	lda	col_on
		beq	.r
		lda	#COL_TOP		; Block.
		ldy	#<COL_PAT
		ldx	#$11			; 32 x 32
		jsr	col_emit
		lda	col_len			; Foot.
		clc
		adc	#COL_TOP
		sta	col_y
		ldy	#<(COL_PAT + 10)
		clx
		jsr	col_emit
.shaft:		lda	col_y			; Shaft pieces above it.
		sec
		sbc	#16
		sta	col_y
		cmp	#COL_TOP + 17
		bcc	.r
		ldy	#<(COL_PAT + 8)
		clx
		jsr	col_emit
		bra	.shaft
.r:		rts

; col_emit - A = world y (0-255), Y = pattern low byte, X = size bits (high
; attribute byte, $11: the 32x32 block at COL_X, 0: 16 wide at COL_X + 8): a
; sprite, if on the screen and the SATB has room.
col_emit:	sta	col_w
		lda	<en_satb
		cmp	<en_cap
		bcc	!+
		inc	<en_full
		rts
!:		lda	col_w			; sy = y - scroll_y
		sec
		sbc	<scroll_y
		sta	col_sy
		cla
		sbc	<scroll_y + 1
		sta	col_sy + 1
		beq	.y			; Visible: -15 .. 239.
		cmp	#$FF
		bne	.off
		bra	.neg
.y:
		lda	col_sy
		cmp	#240
		bcs	.off
		bra	.x
.neg:		lda	col_sy
		cmp	#$F1
		bcc	.off
.x:		lda	#<(COL_X + 8)		; sx = left - scroll_x
		cpx	#0
		beq	!+
		lda	#<COL_X
!:		sec
		sbc	<scroll_x
		sta	col_sx
		lda	#>COL_X
		sbc	<scroll_x + 1
		sta	col_sx + 1
		beq	.on			; Visible: -31 .. 255.
		cmp	#$FF
		bne	.off
		lda	col_sx
		cmp	#$E1
		bcc	.off
.on:		lda	col_sy			; y + 64
		clc
		adc	#64
		sta	VDC_DL
		lda	col_sy + 1
		adc	#0
		and	#3
		sta	VDC_DH
		lda	col_sx			; x + 32
		clc
		adc	#32
		sta	VDC_DL
		lda	col_sx + 1
		adc	#0
		and	#3
		sta	VDC_DH
		sty	VDC_DL			; pattern ($2xx)
		lda	#>COL_PAT
		sta	VDC_DH
		lda	#COL_PAL | $80		; palette, in front
		sta	VDC_DL
		stx	VDC_DH			; size
		inc	<en_satb
.off:		rts

; ---------------------------------------------------------------------------
; wall_update - once a frame in the castle (enemies_update, after column_update).

wall_update:	lda	wl_act
		bne	.run
		lda	<p_y + 1		; Rastan come into the lava hall's square
		cmp	#$FE			; (x 8704 on, y -512 .. -1: in the arcade,
		bne	.box			; as he gets there): its clock starts.
		lda	<p_x
		cmp	#<8704
		lda	<p_x + 1
		sbc	#>8704
		bcc	.box
		lda	#1
		sta	wl_act
		stz	wl_t
		stz	wl_t + 1
		bra	.box
.run:		lda	wl_step			; (all out: it stays)
		cmp	#31
		bcs	.box
		cmp	#0
		bne	.stepping
		inc	wl_t			; Waiting.
		bne	!+
		inc	wl_t + 1
!:		lda	wl_t
		cmp	#<WL_WAIT
		lda	wl_t + 1
		sbc	#>WL_WAIT
		bcc	.box
		lda	#1
		sta	wl_step
		lda	#WL_STEP
		sta	wl_cnt
		bra	.box
.stepping:	dec	wl_cnt
		bne	.box
		lda	#WL_STEP
		sta	wl_cnt
		inc	wl_step
		; (fall through)
.box:		jmp	wall_box

; wall_box - out: the solid prop box (WL_X .. its right edge, WL_TOP .. -319),
; and Rastan pushed right of it (p_x = right edge + 11).
wall_box:	lda	<p_y + 1		; (above row 0: the column's box is row 0's)
		bmi	!+
		rts
!:		lda	wl_step
		bne	!+
		rts
!:
		jsr	wl_right		; col_y = the wall's right edge
		lda	#<WL_X
		sta	<pb_x0
		lda	#>WL_X
		sta	<pb_x0 + 1
		lda	col_y
		sta	<pb_x1
		lda	col_y + 1
		sta	<pb_x1 + 1
		lda	#<WL_TOP
		sta	<pb_y0
		lda	#>WL_TOP
		sta	<pb_y0 + 1
		lda	#<(WL_TOP + 96)
		sta	<pb_y1
		lda	#>(WL_TOP + 96)
		sta	<pb_y1 + 1
		lda	#1
		sta	<prop_solid
		; His body (p_y - 24 .. p_y + 24) beside it and p_x - 11 left of the
		; edge (but right of the wall's start): push.
		lda	<p_y			; p_y + 24 > WL_TOP and p_y - 24 < -319
		sec
		sbc	#<(WL_TOP - 24)
		lda	<p_y + 1
		sbc	#>(WL_TOP - 24)
		bvc	!+
		eor	#$80
!:		bmi	.r
		lda	<p_y
		sec
		sbc	#<(WL_TOP + 96 + 24)
		lda	<p_y + 1
		sbc	#>(WL_TOP + 96 + 24)
		bvc	!+
		eor	#$80
!:		bpl	.r
		lda	<p_x			; WL_X <= p_x < right + 11?
		sec
		sbc	#<WL_X
		lda	<p_x + 1
		sbc	#>WL_X
		bcc	.r
		lda	col_y
		clc
		adc	#11
		sta	col_y
		bcc	!+
		inc	col_y + 1
!:		lda	<p_x
		cmp	col_y
		lda	<p_x + 1
		sbc	col_y + 1
		bcs	.r
		lda	col_y
		sta	<p_x
		lda	col_y + 1
		sta	<p_x + 1
		; The arcade's Rastan leaves the ledge pushed to x 8763 (step 29); the
		; port's floor probe (p_x - 6) only at 8774: from 8763 on, that far.
		cmp	#>8763
		bne	.r
		lda	<p_x
		cmp	#<8763
		bcc	.r
		lda	#<8774
		sta	<p_x
.r:		rts

; wl_right - col_y = WL_X + 2 (wl_step - 1) + 16.
wl_right:	lda	wl_step
		dec	a
		asl	a
		clc
		adc	#<(WL_X + 16)
		sta	col_y
		lda	#>(WL_X + 16)
		adc	#0
		sta	col_y + 1
		rts

; wall_draw - SATB entries (traps_draw): the column (6 cells) and the top row
; (cells 16, 32, ... px left of it, not left of WL_X).
wall_draw:	lda	wl_step
		bne	!+
		rts
!:		jsr	wl_right
		lda	col_y			; Column's left = right edge - 16.
		sec
		sbc	#16
		sta	wl_x
		lda	col_y + 1
		sbc	#0
		sta	wl_x + 1
		lda	#6
		sta	wl_n
		lda	#<WL_TOP
		sta	wl_y
		lda	#>WL_TOP
		sta	wl_y + 1
.col:		jsr	wall_emit
		lda	wl_y
		clc
		adc	#16
		sta	wl_y
		bcc	!+
		inc	wl_y + 1
!:		dec	wl_n
		bne	.col
		lda	#<WL_TOP		; Top row: from the column's left, a cell
		sta	wl_y			; every 16 px back, while not left of WL_X.
		lda	#>WL_TOP
		sta	wl_y + 1
.row:		lda	wl_x
		sec
		sbc	#16
		sta	wl_x
		lda	wl_x + 1
		sbc	#0
		sta	wl_x + 1
		lda	wl_x
		cmp	#<WL_X
		lda	wl_x + 1
		sbc	#>WL_X
		bcc	.r
		jsr	wall_emit
		bra	.row
.r:		rts

; wall_emit - a $234 cell (TRAP_PAT, palette 13) at world (wl_x, wl_y).
wall_emit:	lda	<en_satb
		cmp	<en_cap
		bcc	!+
		inc	<en_full
		rts
!:		lda	wl_y			; sy = y - scroll_y: -15 .. 239
		sec
		sbc	<scroll_y
		sta	col_sy
		lda	wl_y + 1
		sbc	<scroll_y + 1
		sta	col_sy + 1
		beq	.y
		cmp	#$FF
		bne	.off
		lda	col_sy
		cmp	#$F1
		bcc	.off
		bra	.x
.y:		lda	col_sy
		cmp	#240
		bcs	.off
.x:		lda	wl_x			; sx = x - scroll_x: -15 .. 255
		sec
		sbc	<scroll_x
		sta	col_sx
		lda	wl_x + 1
		sbc	<scroll_x + 1
		sta	col_sx + 1
		beq	.on
		cmp	#$FF
		bne	.off
		lda	col_sx
		cmp	#$F1
		bcc	.off
.on:		lda	col_sy
		clc
		adc	#64
		sta	VDC_DL
		lda	col_sy + 1
		adc	#0
		and	#3
		sta	VDC_DH
		lda	col_sx
		clc
		adc	#32
		sta	VDC_DL
		lda	col_sx + 1
		adc	#0
		and	#3
		sta	VDC_DH
		lda	#<TRAP_PAT
		sta	VDC_DL
		lda	#>TRAP_PAT
		sta	VDC_DH
		lda	#TRAP_PAL_COVER | $80
		sta	VDC_DL
		stz	VDC_DH
		inc	<en_satb
.off:		rts
