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
; A touch kills (the arcade's hit effect $0553D6, state 8, like the fire).
; The arcade's boxes (inclusive; the test is $044CBA, the weights' boxes
; $044CE0 + 4 * ($27 + L / 2), Rastan's at $10D248): the weight x - 16 ..
; x + 16, y -828 + 4 (L / 2) .. -796 + 4 (L / 2); Rastan x - 12 .. x + 12,
; y - 24 .. y + 26 (crouched: y .. y + 26). So: |p_x - x| <= 28 and his top
; at or above the bar's bottom. The hit is recorded in one frame and takes
; effect in the next (here: tested with the length before this frame's
; step). Standing on the corridor's floor (-729) he dies from L 22 (dead as
; it reaches 23); crouched, never: the bar comes down to -736.
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
wt_cnt:		ds	1		; How many (3 in round 1, 1 in round 3).
wt_xl:		ds	NUM_WT		; Their x (from the round's table).
wt_xh:		ds	NUM_WT
wt_dy:		ds	2		; The round's anchor - WT_Y (round 3: 128).
wt_pal:		ds	1		; Palette (round 1: 14; round 3: 8, loaded).
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
weights_update:
		lda	wt_act
		bne	.run
		lda	<cur_round		; (round 3: one; round 2: none, its marker
		cmp	#3			; $45 makes none in the arcade's run from
		bne	!+			; its restart at segment $28)
		jmp	wt3_on
!:		cmp	#2
		bne	!+
		rts
!:		lda	<scroll_x + 1		; The camera in shaft 2 (x 9728 - 10239)
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
		lda	#3			; (round 1's three)
		sta	wt_cnt
		ldx	#2
!:		lda	wt_x_l, x
		sta	wt_xl, x
		lda	wt_x_h, x
		sta	wt_xh, x
		dex
		bpl	!-
		stz	wt_dy
		stz	wt_dy + 1
		lda	#WT_PAL
		sta	wt_pal
		jmp	wt_go
.r:		rts
.run:		jsr	wt_touch
		ldx	wt_cnt
		dex
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

; wt_go - they appear: their clocks start.
wt_go:		lda	#1
		sta	wt_act
		ldx	wt_cnt
		dex
!:		lda	#3
		sta	wt_ph, x
		stz	wt_t, x
		stz	wt_len, x
		dex
		bpl	!-
		rts

; wt3_on - round 3: its one weight (marker $45 at x 9006, plate 128: build/
; r3run.snp, where it appears as the camera reaches x 8650), same clocks, its
; cells and colours (sprite palette 8: the arcade's $4C) loaded then.
; Round 2's (an estimate from its map: marker $45 at (8896, 416); the plate
; under the ceiling above it, y 320, and x as the marker's block's middle;
; appearing 356 px ahead, as round 3's) the same way.
wt3_on:		ldy	<cur_round
		lda	<scroll_x
		cmp	.on_l - 2, y
		lda	<scroll_x + 1
		sbc	.on_h - 2, y
		bcs	!+
		rts
!:		lda	#1
		sta	wt_cnt
		lda	.x_l - 2, y
		sta	wt_xl
		lda	.x_h - 2, y
		sta	wt_xh
		lda	.dy_l - 2, y
		sta	wt_dy
		lda	.dy_h - 2, y
		sta	wt_dy + 1
		lda	#8
		sta	wt_pal
		php
		sei
		lda	#^weights_data
		tam3
		st0	#VDC_MAWR
		st1	#<WT_VRAM
		st2	#>WT_VRAM
		st0	#VDC_VWR
		tia	weights_data, VDC_DL, 5 * 128
		lda	#^weight3_pal
		tam3
		lda	#<(256 + 8 * 16)
		sta	VCE_CTA + 0
		lda	#>(256 + 8 * 16)
		sta	VCE_CTA + 1
		tia	weight3_pal, VCE_CTW, 32
		plp
		jmp	wt_go
.on_l:		db	<8556, <8650
.on_h:		db	>8556, >8650
.x_l:		db	<8912, <9006
.x_h:		db	>8912, >9006
.dy_l:		db	<(320 - WT_Y), <(128 - WT_Y)
.dy_h:		db	>(320 - WT_Y), >(128 - WT_Y)

; wt_touch - a weight over Rastan kills him.
wt_touch:	bra	!+
.rr:		rts
!:		lda	<p_state
		cmp	#ST_DEAD
		beq	.rr
		lda	<dbg_god
		bne	.rr
		lda	<p_y			; In the corridor: his feet (p_y + 24)
		sec				; below the plates' top (the room above
		sbc	wt_dy			; is out of reach). (y - wt_dy: round 1's)
		sta	wt_sy
		lda	<p_y + 1
		sbc	wt_dy + 1
		sta	wt_sy + 1
		lda	wt_sy
		cmp	#<(WT_Y - 16 - 24 + 1)
		lda	wt_sy + 1
		sbc	#>(WT_Y - 16 - 24 + 1)
		bvc	!+
		eor	#$80
!:		bmi	.rr
		ldx	wt_cnt
		dex
.one:		lda	<p_x			; p_x - (x - 28) in 0 .. 56?
		sec
		sbc	wt_xl, x
		sta	wt_sx
		lda	<p_x + 1
		sbc	wt_xh, x
		sta	wt_sx + 1
		lda	wt_sx
		clc
		adc	#28
		sta	wt_sx
		lda	wt_sx + 1
		adc	#0
		bne	.next
		lda	wt_sx
		cmp	#57
		bcs	.next
		; p_y < -771 + 4 (L / 2) (crouched: -795 + ...): his top at or above
		lda	wt_len, x		; the bar's bottom.
		and	#$FE
		asl	a
		sta	wt_sy
		stz	wt_sy + 1
		lda	<p_state
		cmp	#ST_CROUCH
		beq	.low
		cmp	#ST_CATK
		beq	.low
		lda	#<(-771)
		ldy	#>(-771)
		bra	!+
.low:		lda	#<(-795)
		ldy	#>(-795)
!:		clc
		adc	wt_sy
		sta	wt_sy
		tya
		adc	#0
		sta	wt_sy + 1
		lda	wt_sy			; (+ the round's anchor)
		clc
		adc	wt_dy
		sta	wt_sy
		lda	wt_sy + 1
		adc	wt_dy + 1
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
		lda	<cur_round		; (round 1: once the castle's cells are in)
		cmp	#1
		bne	!+
		lda	col_on
		beq	.r
!:		ldx	wt_cnt
		dex
.one:		stx	wt_i
		jsr	wt_draw1
		ldx	wt_i
		dex
		bpl	.one
.r:		rts

wt_draw1:	lda	wt_xl, x		; Plate: (x - 8, WT_Y - 16).
		sec
		sbc	#8
		sta	wt_wx
		lda	wt_xh, x
		sbc	#0
		sta	wt_wx + 1
		lda	#<(WT_Y - 16)
		clc
		adc	wt_dy
		sta	wt_wy
		lda	#>(WT_Y - 16)
		adc	wt_dy + 1
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
		lda	wt_wy
		clc
		adc	wt_dy
		sta	wt_wy
		lda	wt_wy + 1
		adc	wt_dy + 1
		sta	wt_wy + 1
		lda	wt_pal			; (palette, in front)
		ora	#$80
		tay
		lda	#<(WT_PAT + 2)
		clx
		jsr	wt_emit
		jsr	wt_down16		; Bar: 16 below, 32 wide from x - 16.
		lda	wt_wx
		sec
		sbc	#8
		sta	wt_wx
		bcs	!+
		dec	wt_wx + 1
!:		lda	wt_pal			; (palette, in front)
		ora	#$80
		tay
		lda	#<(WT_PAT + 4)
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
		lda	wt_pal			; (palette, in front)
		ora	#$80
		tay
		lda	#<WT_PAT
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
