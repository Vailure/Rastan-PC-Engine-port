; ***************************************************************************
;
; Rastan - shaft 2's spiked weights (arcade marker $45, object type $18).
;
; Measured in the arcade (sim/scripts/weights.txt; the handler is $0442BA):
; over the corridor at the top of shaft 2 (floor y -729) three weights hang
; from plates in the ceiling at x 9952, 10016 and 10080 (y -832). They are
; map objects that appear when the camera's top comes up to y -752 (the
; port: scroll_y -744, the same view) and then run on their own:
;
;   phase 1: wait (the first time 8, 40, 72 frames: weight i 32 later than
;            weight i - 1; then 80 frames), then come down 1 a frame to 31,
;   phase 2: wait 2 frames, then go up 1 a frame to 0,
;   phase 0: one frame,
;
; a cycle of 147 frames. At length L the frame is drawn at y -830 + 2L, the
; spiked bar (32 wide) 16 px below it, the chain's links (at most 4) above.
;
; A touch kills (the arcade's hit effect $0553D6, state 8, like the fire):
; Rastan's middle within -26 .. +30 px of the weight's x, and his body's top
; (p_y - 24) above the bar's bottom, -796 + 2L for the weight's length on the
; frame before (the arcade reads it a frame late): standing on the corridor's
; floor, from L 23. Crouched he lives through whole cycles (the arcade), so
; his top is then taken as p_y - 5: the bar, down to -734, never reaches it.
;
; Sprites like the column's (no object slot): plate, frame, bar (32 x 16) and
; chain links; the plate in Rastan's palette (0), the rest in the spears'
; (14). Cells (tools/pce_traps.py weights.bin) at WT_VRAM: HUD cells 26-30,
; which the HUD leaves free. Uploaded with the column's (column_cells).
;
; In GAME_BANK (MPR6).
;
; ***************************************************************************

NUM_WT		=	3
WT_Y		=	-832			; Anchor: the plate's bottom.
WT_ON_Y		=	-744			; scroll_y at which they appear.
WT_VRAM		=	$7700 + 26 * 64		; (HUD_VRAM + cell 26)
WT_PAT		=	WT_VRAM >> 5		; Chain, frame +2, bar +4 (32 wide), plate +8.
WT_PAL		=	14			; (TRAP_PAL_SPEAR)
WT_WAIT		=	80

		.bss
wt_act:		ds	1		; They have appeared: their clocks run.
wt_ph:		ds	NUM_WT		; Phase (3: just appeared).
wt_t:		ds	NUM_WT		; Frames to wait.
wt_len:		ds	NUM_WT		; L, 0-31.
wt_wx:		ds	2		; Draw scratch: world x, y.
wt_wy:		ds	2
wt_sx:		ds	2
wt_sy:		ds	2
wt_n:		ds	1
wt_i:		ds	1

		.code

wt_x_l:		db	<9952, <10016, <10080
wt_x_h:		db	>9952, >10016, >10080

; weights_reset - not there yet (restarts).
weights_reset:	stz	wt_act
		ldx	#NUM_WT - 1
!:		stz	wt_len, x
		dex
		bpl	!-
		rts

; weights_update - once a frame in the castle (enemies_update): the touch
; (with this frame's lengths: the arcade's are a frame late), then the clocks.
weights_update:	lda	wt_act
		bne	.run
		lda	<scroll_x + 1		; The camera in shaft 2 (x 9728 - 10239)
		and	#$FE			; and up to y -744.
		cmp	#>9728
		bne	.r
		lda	<scroll_y
		cmp	#<(WT_ON_Y + 1)
		lda	<scroll_y + 1
		sbc	#>(WT_ON_Y + 1)
		bvc	!+
		eor	#$80
!:		bpl	.r
		lda	#1
		sta	wt_act
		ldx	#NUM_WT - 1
!:		lda	#3
		sta	wt_ph, x
		stz	wt_t, x
		stz	wt_len, x
		dex
		bpl	!-
.r:		rts
.run:		jsr	wt_touch
		ldx	#NUM_WT - 1
.one:		lda	wt_t, x
		beq	!+
		dec	wt_t, x
		bra	.next
!:		lda	wt_ph, x
		beq	.ph0
		cmp	#2
		beq	.ph2
		bcs	.first
		lda	wt_len, x		; 1: down to 31, then wait 2.
		cmp	#31
		beq	!+
		inc	wt_len, x
		bra	.next
!:		lda	#2
		sta	wt_ph, x
		sta	wt_t, x
		bra	.next
.ph2:		lda	wt_len, x		; 2: up to 0, then phase 0.
		beq	!+
		dec	wt_len, x
		bra	.next
!:		stz	wt_ph, x
		bra	.next
.ph0:		lda	#WT_WAIT		; 0: wait 80, phase 1.
		bra	.wait
.first:		txa				; (the first time: 8 + 32 i)
		asl	a
		asl	a
		asl	a
		asl	a
		asl	a
		adc	#8
.wait:		sta	wt_t, x
		lda	#1
		sta	wt_ph, x
.next:		dex
		bpl	.one
		rts

; wt_touch - a weight over Rastan kills him.
wt_touch:	lda	<p_state
		cmp	#ST_DEAD
		beq	.r
		lda	<dbg_god
		bne	.r
		lda	<p_y			; In the corridor: his feet (p_y + 24)
		cmp	#<(WT_Y - 16 - 24 + 1)	; below the plates' top (the room above
		lda	<p_y + 1		; is out of reach).
		sbc	#>(WT_Y - 16 - 24 + 1)
		bvc	!+
		eor	#$80
!:		bmi	.r
		ldx	#NUM_WT - 1
.one:		lda	<p_x			; p_x - (x - 26) in 0 .. 56?
		sec
		sbc	wt_x_l, x
		sta	wt_sx
		lda	<p_x + 1
		sbc	wt_x_h, x
		sta	wt_sx + 1
		lda	wt_sx
		clc
		adc	#26
		sta	wt_sx
		lda	wt_sx + 1
		adc	#0
		bne	.next
		lda	wt_sx
		cmp	#57
		bcs	.next
		; p_y < -772 + 2L (crouched: -791 + 2L): his top above the bar's bottom.
		lda	wt_len, x
		asl	a
		sta	wt_sy
		stz	wt_sy + 1
		lda	<p_state
		cmp	#ST_CROUCH
		beq	.low
		cmp	#ST_CATK
		beq	.low
		lda	#<(-772)
		ldy	#>(-772)
		bra	!+
.low:		lda	#<(-791)
		ldy	#>(-791)
!:		clc
		adc	wt_sy
		sta	wt_sy
		tya
		adc	#0
		sta	wt_sy + 1
		lda	<p_y			; p_y - limit < 0 (signed)?
		cmp	wt_sy
		lda	<p_y + 1
		sbc	wt_sy + 1
		bvc	!+
		eor	#$80
!:		bpl	.next
		jmp	enter_dead
.next:		dex
		bpl	.one
.r:		rts

; weights_draw - SATB entries (traps_draw): per weight the plate, the frame,
; the bar and the chain's links above the frame (16 px apart, while not above
; the plate's top; at most 4).
weights_draw:	lda	wt_act
		beq	.r
		lda	col_on
		beq	.r
		ldx	#NUM_WT - 1
.one:		stx	wt_i
		jsr	wt_draw1
		ldx	wt_i
		dex
		bpl	.one
.r:		rts

wt_draw1:	lda	wt_x_l, x		; Plate: (x - 8, WT_Y - 16).
		sec
		sbc	#8
		sta	wt_wx
		lda	wt_x_h, x
		sbc	#0
		sta	wt_wx + 1
		lda	#<(WT_Y - 16)
		sta	wt_wy
		lda	#>(WT_Y - 16)
		sta	wt_wy + 1
		lda	#<(WT_PAT + 8)
		ldy	#0 | $80
		clx
		jsr	wt_emit
		ldx	wt_i			; Frame: y = WT_Y + 2 + 2L.
		lda	wt_len, x
		asl	a
		clc
		adc	#<(WT_Y + 2)
		sta	wt_wy
		lda	#>(WT_Y + 2)
		adc	#0
		sta	wt_wy + 1
		lda	#<(WT_PAT + 2)
		ldy	#WT_PAL | $80
		clx
		jsr	wt_emit
		jsr	wt_down16		; Bar: 16 below, 32 wide from x - 16.
		lda	wt_wx
		sec
		sbc	#8
		sta	wt_wx
		bcs	!+
		dec	wt_wx + 1
!:		lda	#<(WT_PAT + 4)
		ldy	#WT_PAL | $80
		ldx	#$01
		jsr	wt_emit
		lda	wt_wx			; (back to x - 8)
		clc
		adc	#8
		sta	wt_wx
		bcc	!+
		inc	wt_wx + 1
!:		ldx	wt_i			; Links: n = min(4, (L + 9) / 8), from the
		lda	wt_len, x		; frame up.
		clc
		adc	#9
		lsr	a
		lsr	a
		lsr	a
		cmp	#5
		bcc	!+
		lda	#4
!:		sta	wt_n
		jsr	wt_up16			; (back to the frame)
.link:		lda	wt_n
		beq	.r
		dec	wt_n
		jsr	wt_up16
		lda	#<WT_PAT
		ldy	#WT_PAL | $80
		clx
		jsr	wt_emit
		bra	.link
.r:		rts

wt_down16:	lda	wt_wy
		clc
		adc	#16
		sta	wt_wy
		bcc	!+
		inc	wt_wy + 1
!:		rts

wt_up16:	lda	wt_wy
		sec
		sbc	#16
		sta	wt_wy
		bcs	!+
		dec	wt_wy + 1
!:		rts

; wt_emit - A = pattern low byte (high: >WT_PAT), Y = palette and priority,
; X = size (high attribute byte: 0 16 x 16, $01 32 x 16): a sprite at world
; (wt_wx, wt_wy), if on the screen and the SATB has room.
wt_emit:	pha
		lda	<en_satb
		cmp	<en_cap
		bcc	!+
		inc	<en_full
		pla
		rts
!:		lda	wt_wy			; sy = y - scroll_y: -15 .. 239
		sec
		sbc	<scroll_y
		sta	wt_sy
		lda	wt_wy + 1
		sbc	<scroll_y + 1
		sta	wt_sy + 1
		beq	.y
		cmp	#$FF
		bne	.off
		lda	wt_sy
		cmp	#$F1
		bcc	.off
		bra	.x
.y:		lda	wt_sy
		cmp	#240
		bcs	.off
.x:		lda	wt_wx			; sx = x - scroll_x: -31 .. 255
		sec
		sbc	<scroll_x
		sta	wt_sx
		lda	wt_wx + 1
		sbc	<scroll_x + 1
		sta	wt_sx + 1
		beq	.on
		cmp	#$FF
		bne	.off
		lda	wt_sx
		cmp	#$E1
		bcc	.off
.on:		lda	wt_sy
		clc
		adc	#64
		sta	VDC_DL
		lda	wt_sy + 1
		adc	#0
		and	#3
		sta	VDC_DH
		lda	wt_sx
		clc
		adc	#32
		sta	VDC_DL
		lda	wt_sx + 1
		adc	#0
		and	#3
		sta	VDC_DH
		pla
		sta	VDC_DL			; pattern
		lda	#>WT_PAT
		sta	VDC_DH
		sty	VDC_DL			; palette, in front
		stx	VDC_DH			; size
		inc	<en_satb
		rts
.off:		pla
		rts
