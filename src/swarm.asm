; ***************************************************************************
;
; Rastan - the hurry-up swarm.
;
; The arcade's answer to dawdling (its $049FA6, measured with sim/scripts/
; swarm.txt and hall.txt). A timer runs while the stream stays in one pair of
; segments: every 64 frames it counts one, and at 40 (42 s) nine small bats
; come (arcade object slots 20-28, type $0B). Each wave raises the level (up
; to 3) and the next comes sooner: after 30, 20, then 10 counts. A new pair of
; segments restarts the count; a death or a restart clears it all. Not in the
; boss room.
;
; Bats 0-5 enter at the left or right edge of the screen at heights that
; depend on where Rastan stands, bats 6-8 from below him. Each flies toward a
; target, Rastan's position (16 px up) when the wave came, kept as a point on
; the screen (the arcade keeps objects in screen coordinates). A bat flies
; scripts of six steps, a step every 4 frames (2 from level 2, 1 at level 3):
; the step moves it by a velocity from a 56-direction table, and each next
; step turns the direction by one. When a script ends, the bat picks the next
; by where the target is (left/right, and, on a bit of its own pseudo-random
; byte, above/below), so the swarm circles in on the target in loops. At
; level 3 a bat aims at where Rastan is now each time it picks.
;
; A bat touching Rastan bites (1024 of 12288 health, 4 bar units, then 45
; frames before the next bite, no knockback); one sword hit kills it (100
; points, $276 shown for a few frames). A wave also replaces the bats that are
; off the screen. All bats flap on one clock: cells $268, $269, $26A (the same
; image as $269, lower), $269, 4 frames each.
;
; The three cells stay in VRAM: $4A80 and $4AC0 (after the BG tile pool, which
; tools/pce_stage.py keeps below them) and $76C0 (after the object buffers).
;
; Lives in bank DEBUG_BANK (MPR2, always mapped).
;
; ***************************************************************************

SW_N		=	9			; Bats.
SW_VRAM0	=	$4A80			; Cell $268,
SW_VRAM1	=	$4AC0			; $269 (and $26A),
SW_VRAM_DEAD	=	$76C0			; $276 (killed).
SW_SPAWN	=	3			; sw_st: entering (flies from the next frame),
SW_DYING	=	$0F			; killed; 4-9 flying (the script chosen).
SW_DEAD_FRAMES	=	4
SW_BITE		=	45			; Frames between bites.
SW_BITE_HP	=	4			; Bar units a bite (1024 of 12288).
SW_FIRST	=	40			; Counts of 64 frames before the first wave.

SWC0_SRC	=	$6000 + (SWARM_CELL0 & 63) * 128
SWC1_SRC	=	$6000 + (SWARM_CELL1 & 63) * 128
SWCD_SRC	=	$6000 + (SWARM_DEAD & 63) * 128

		.bss				; (zero page is full: the System Card's
sw_level:	ds	1		; Waves so far (0-3).
sw_count:	ds	1		; Counts of 64 frames in this pair of segments.
sw_period:	ds	1		; Counts before the next wave.
sw_pair:	ds	1		; Pair of segments being counted ($FF: none yet).
sw_int:		ds	1		; Frames a step: 4, 2 (level 2), 1 (level 3).
sw_bite:	ds	1		; Frames before a bat can bite again.
sw_rot:		ds	1		; First bat drawn (turns, so losses flicker).
sw_i:		ds	1
sw_sword:	ds	1		; Bit 7: the sword is out this frame.
sw_sx:		ds	2		; Bat's screen position.
sw_sy:		ds	2
sw_t:		ds	1
sw_dx:		ds	1		; sw_emit: piece offset, pattern, attributes.
sw_dy:		ds	1
sw_pl:		ds	1
sw_ph:		ds	1
sw_a0:		ds	1
sw_a1:		ds	1

					; variables start at $20E0)
sw_st:		ds	SW_N		; 0 free, SW_SPAWN, 4-9 flying, SW_DYING.
sw_xl:		ds	SW_N		; World position.
sw_xh:		ds	SW_N
sw_yl:		ds	SW_N
sw_yh:		ds	SW_N
sw_ang:		ds	SW_N		; Direction 1-56 (1 up, 15 right, 29 down, 43 left).
sw_turn:	ds	SW_N		; +1 or -1 a step.
sw_seg:		ds	SW_N		; Steps left in the script.
sw_cnt:		ds	SW_N		; Frames to the next step (dying: frames left).
sw_busy:	ds	SW_N		; A script is running.
sw_rnd:		ds	SW_N		; The bat's pseudo-random byte.
sw_flip:	ds	SW_N		; Flying left (sprite mirrored).
sw_txl:		ds	SW_N		; Target on the screen.
sw_txh:		ds	SW_N
sw_tyl:		ds	SW_N
sw_tyh:		ds	SW_N
sw_box:		ds	16		; Sword box, then Rastan's body box (sb_* layout).
sw_pb:		ds	8		; The solid prop's box, kept (swarm_update).
sw_ox:		ds	2		; swarm_save: the camera before a door.
sw_oy:		ds	2

		.code

; ---------------------------------------------------------------------------
; swarm_reset - no bats, the timer from zero (stage starts, restarts, the
; boss room door); the three cells into VRAM.

swarm_reset:	ldx	#SW_N - 1
.c:		stz	sw_st, x
		dex
		bpl	.c
		stz	sw_level
		stz	sw_count
		stz	sw_bite
		lda	#SW_FIRST
		sta	sw_period
		lda	#$FF
		sta	sw_pair
		lda	#4
		sta	sw_int
		; (fall through)

; swarm_cells - the bat cells from the object data into VRAM.
swarm_cells:	php
		sei
		tma3
		pha
		st0	#VDC_MAWR
		st1	#<SW_VRAM0
		st2	#>SW_VRAM0
		st0	#VDC_VWR
		lda	#OBJ_CELL_BANK + (SWARM_CELL0 >> 6)
		tam3
		lda	#<SWC0_SRC
		sta	ram_tia + 1
		lda	#>SWC0_SRC
		sta	ram_tia + 2
		jsr	ram_tia			; (128 bytes: one cell)
		lda	#OBJ_CELL_BANK + (SWARM_CELL1 >> 6)
		tam3
		lda	#<SWC1_SRC		; (SW_VRAM1 follows SW_VRAM0)
		sta	ram_tia + 1
		lda	#>SWC1_SRC
		sta	ram_tia + 2
		jsr	ram_tia
		st0	#VDC_MAWR
		st1	#<SW_VRAM_DEAD
		st2	#>SW_VRAM_DEAD
		st0	#VDC_VWR
		lda	#OBJ_CELL_BANK + (SWARM_DEAD >> 6)
		tam3
		lda	#<SWCD_SRC
		sta	ram_tia + 1
		lda	#>SWCD_SRC
		sta	ram_tia + 2
		jsr	ram_tia
		pla
		tam3
		plp
		rts

; swarm_save / swarm_follow - around the castle gate's cut: the bats move
; with the camera (the arcade keeps them in screen coordinates).
swarm_save:	lda	<scroll_x
		sta	sw_ox
		lda	<scroll_x + 1
		sta	sw_ox + 1
		lda	<scroll_y
		sta	sw_oy
		lda	<scroll_y + 1
		sta	sw_oy + 1
		rts

swarm_follow:	lda	<scroll_x		; sw_ox/oy = the camera's move
		sec
		sbc	sw_ox
		sta	sw_ox
		lda	<scroll_x + 1
		sbc	sw_ox + 1
		sta	sw_ox + 1
		lda	<scroll_y
		sec
		sbc	sw_oy
		sta	sw_oy
		lda	<scroll_y + 1
		sbc	sw_oy + 1
		sta	sw_oy + 1
		ldx	#SW_N - 1
.b:		lda	sw_xl, x
		clc
		adc	sw_ox
		sta	sw_xl, x
		lda	sw_xh, x
		adc	sw_ox + 1
		sta	sw_xh, x
		lda	sw_yl, x
		clc
		adc	sw_oy
		sta	sw_yl, x
		lda	sw_yh, x
		adc	sw_oy + 1
		sta	sw_yh, x
		dex
		bpl	.b
		rts

; ---------------------------------------------------------------------------
; swarm_update - once a game frame, after enemies_update.

swarm_update:	lda	<dbg_noenemy		; (debug menu: enemies off)
		beq	!+
		rts
!:		jsr	sw_timer
		lda	sw_bite
		beq	!+
		dec	sw_bite
!:		jsr	sword_box		; The sword's box and Rastan's body box,
		ror	sw_sword		; once for all the bats.
		ldx	#7
.sb:		lda	<sb_x0, x
		sta	sw_box, x
		dex
		bpl	.sb
		lda	<p_x			; Body: p_x +/- 12, p_y - 24 .. p_y + 24
		sec				; (as body_vs_enemy).
		sbc	#12
		sta	sw_box + 8
		lda	<p_x + 1
		sbc	#0
		sta	sw_box + 9
		lda	<p_x
		clc
		adc	#12
		sta	sw_box + 10
		lda	<p_x + 1
		adc	#0
		sta	sw_box + 11
		lda	<p_y
		sec
		sbc	#24
		sta	sw_box + 12
		lda	<p_y + 1
		sbc	#0
		sta	sw_box + 13
		lda	<p_y
		clc
		adc	#24
		sta	sw_box + 14
		lda	<p_y + 1
		adc	#0
		sta	sw_box + 15
		ldx	#7			; (pb_* is the solid prop's box: the bats
.sv:		lda	<pb_x0, x		; borrow it)
		sta	sw_pb, x
		dex
		bpl	.sv
		ldx	#SW_N - 1
.b:		lda	sw_st, x
		beq	.n
		jsr	sw_one
.n:		dex
		bpl	.b
		ldx	#7
.rs:		lda	sw_pb, x
		sta	<pb_x0, x
		dex
		bpl	.rs
		rts

; sw_timer - the wave timer (arcade $049FB2).
sw_timer:	lda	<next_col		; The boss room (past the door's line): none.
		cmp	#<(STAGE_DOOR_LINE + 1)
		lda	<next_col + 1
		sbc	#>(STAGE_DOOR_LINE + 1)
		bcc	!+
		rts
!:		lda	<next_col		; Pair = (last line streamed) / 128: the
		sec				; arcade's (segment - 1) / 2, its segment
		sbc	#1			; being one ahead of the camera's.
		sta	sw_t
		lda	<next_col + 1
		sbc	#0
		bcs	!+
		cla				; (nothing streamed yet: pair 0)
		stz	sw_t
!:		asl	sw_t
		rol	a
		cmp	sw_pair
		beq	.same
		sta	sw_pair		; A new pair: count from zero, 40 to go.
		stz	sw_count
		lda	#SW_FIRST
		sta	sw_period
		rts
.same:		lda	<p_frame		; A count every 64 frames.
		and	#$3F
		bne	.r
		inc	sw_count
		lda	sw_count
		cmp	sw_period
		bcc	.r
		stz	sw_count		; A wave: level + 1 (3 at most), the next
		lda	sw_level		; after (4 - level) * 10 counts.
		cmp	#3
		bcs	!+
		inc	sw_level
!:		lda	#4
		sec
		sbc	sw_level
		asl	a
		sta	sw_t
		asl	a
		asl	a
		clc
		adc	sw_t
		sta	sw_period
		ldy	sw_level
		lda	sw_ints, y
		sta	sw_int
		jmp	sw_wave
.r:		rts

sw_ints:	db	4, 4, 2, 1		; Frames a step, by level.

; sw_wave - bats 0-8 (arcade numbers 9-1), each if free or off the screen.
sw_wave:	clx
		lda	#9
		sta	sw_i
.loop:		lda	sw_st, x
		beq	.init
		jsr	sw_screen
		jsr	sw_offscreen
		bcc	.next
.init:		jsr	sw_spawn
.next:		inx
		dec	sw_i
		bne	.loop
		rts

; sw_offscreen - carry set if the bat at (sw_sx, sw_sy) is off the screen:
; x < -8 or x >= 264, y < 0 or y >= 240 (the arcade: $148-$1F7, $100 up).
sw_offscreen:	lda	sw_sx			; x + 8 in 0..271?
		clc
		adc	#8
		sta	sw_t
		lda	sw_sx + 1
		adc	#0
		bmi	.off
		beq	.y
		cmp	#1
		bne	.off
		lda	sw_t
		cmp	#16
		bcs	.off
.y:		lda	sw_sy + 1
		bne	.off			; (negative, or 256 and more)
		lda	sw_sy
		cmp	#240
		rts				; (carry: off)
.off:		sec
		rts

; sw_spawn - X = bat, sw_i = its arcade number (9-1): enter (arcade $045C0C).
sw_spawn:	lda	sw_i
		sta	sw_rnd, x
		lda	#SW_SPAWN
		sta	sw_st, x
		stz	sw_busy, x
		stz	sw_flip, x
		jsr	sw_target
		lda	sw_i
		cmp	#4
		bcs	.side
		tay				; Numbers 1-3: below Rastan.
		lda	sw_low_dx - 1, y
		pha
		clc
		adc	<p_x
		sta	sw_xl, x
		pla
		and	#$80
		beq	!+
		lda	#$FF
!:		adc	<p_x + 1
		sta	sw_xh, x
		lda	sw_low_y - 1, y
		bra	.y
.side:		lsr	a			; Odd: the left edge, even: the right.
		bcc	.right
		lda	<scroll_x
		sec
		sbc	#16
		sta	sw_xl, x
		lda	<scroll_x + 1
		sbc	#0
		sta	sw_xh, x
		bra	.height
.right:		lda	<scroll_x
		clc
		adc	#<264
		sta	sw_xl, x
		lda	<scroll_x + 1
		adc	#>264
		sta	sw_xh, x
.height:	lda	<p_x			; Heights by where Rastan stands on the
		sec				; screen (the arcade's 106 and 212 of 320).
		sbc	<scroll_x
		ldy	#0
		cmp	#85
		bcc	!+
		ldy	#6
		cmp	#170
		bcc	!+
		ldy	#12
!:		tya
		clc
		adc	sw_i
		tay
		lda	sw_side_y - 4, y
.y:		clc				; y = scroll_y + A (screen row)
		adc	<scroll_y
		sta	sw_yl, x
		lda	<scroll_y + 1
		adc	#0
		sta	sw_yh, x
		rts

; Entry heights (the arcade's rows of 240, scaled to 224), for numbers 4-9:
; Rastan in the left third, the middle, the right third. Numbers 1-3: below
; Rastan, 32 px left of him, 32 right, under him.
sw_side_y:	db	30, 105, 119, 179, 209, 45
		db	15, 15, 112, 127, 224, 224
		db	105, 119, 37, 30, 149, 209
sw_low_dx:	db	-32, 32, 0
sw_low_y:	db	231, 231, 217

; sw_target - X = bat: its target, Rastan 16 px up, as a point on the screen.
sw_target:	lda	<p_x
		sec
		sbc	<scroll_x
		sta	sw_txl, x
		lda	<p_x + 1
		sbc	<scroll_x + 1
		sta	sw_txh, x
		lda	<p_y
		sec
		sbc	#16
		sta	sw_t
		lda	<p_y + 1
		sbc	#0
		pha
		lda	sw_t
		sec
		sbc	<scroll_y
		sta	sw_tyl, x
		pla
		sbc	<scroll_y + 1
		sta	sw_tyh, x
		rts

; sw_screen - X = bat: sw_sx, sw_sy = its screen position.
sw_screen:	lda	sw_xl, x
		sec
		sbc	<scroll_x
		sta	sw_sx
		lda	sw_xh, x
		sbc	<scroll_x + 1
		sta	sw_sx + 1
		lda	sw_yl, x
		sec
		sbc	<scroll_y
		sta	sw_sy
		lda	sw_yh, x
		sbc	<scroll_y + 1
		sta	sw_sy + 1
		rts

; ---------------------------------------------------------------------------
; sw_one - X = bat (not free): one frame.

sw_one:		lda	sw_st, x
		cmp	#SW_SPAWN
		bne	!+
		lda	#4			; (it picks a script next frame)
		sta	sw_st, x
		rts
!:		cmp	#SW_DYING
		bne	.fly
		dec	sw_cnt, x
		bne	.r
		stz	sw_st, x
.r:		rts
.fly:		lda	sw_busy, x
		bne	.step
		jsr	sw_choose		; A script: pick, start, first step now.
		jsr	sw_load
		bra	.move
.step:		dec	sw_cnt, x		; (arcade $042E38)
		bne	.hits
		lda	sw_int
		sta	sw_cnt, x
		dec	sw_seg, x
		bne	.turn
		stz	sw_busy, x		; Script over (no step this frame).
		bra	.hits
.turn:		lda	sw_ang, x		; Turn one direction (1-56, wrapping).
		clc
		adc	sw_turn, x
		bne	!+
		lda	#56
!:		cmp	#57
		bcc	!+
		lda	#1
!:		sta	sw_ang, x
.move:		jsr	sw_move
.hits:		jmp	sw_hits

; sw_choose - X = bat: the next script, by where its target is (arcade
; $041FAC): its byte goes on (r + ((r + 1) & 15) * 16 + 1); left of the
; target 4, else 5; with bit 4 of the byte set, also by height: left and
; above 6, left and below 8, right and below 9, right and above 7.
sw_choose:	lda	sw_rnd, x
		inc	a
		and	#$0F
		asl	a
		asl	a
		asl	a
		asl	a
		sec
		adc	sw_rnd, x
		sta	sw_rnd, x
		jsr	sw_screen
		lda	sw_sx			; sx < tx (signed)?
		cmp	sw_txl, x
		lda	sw_sx + 1
		sbc	sw_txh, x
		bvc	!+
		eor	#$80
!:		bmi	.left
		ldy	#5
		bra	!+
.left:		ldy	#4
!:		lda	sw_rnd, x
		and	#$10
		beq	.set
		lda	sw_sy			; sy < ty (signed)?
		cmp	sw_tyl, x
		lda	sw_sy + 1
		sbc	sw_tyh, x
		bvc	!+
		eor	#$80
!:		and	#$80			; A = $80: above the target.
		cpy	#4
		bne	.right
		ldy	#6
		cmp	#0
		bne	.set
		ldy	#8
		bra	.set
.right:		ldy	#7
		cmp	#0
		bne	.set
		ldy	#9
.set:		tya
		sta	sw_st, x
		rts

; sw_load - X = bat: start the script of its state (arcade $042D42 table):
; first direction and turn; six steps, sw_int frames apart.
sw_load:	lda	sw_st, x
		sec
		sbc	#4
		tay
		lda	sw_sang, y
		sta	sw_ang, x
		lda	sw_sturn, y
		sta	sw_turn, x
		lda	#6
		sta	sw_seg, x
		lda	sw_int
		sta	sw_cnt, x
		lda	#1
		sta	sw_busy, x
		lda	sw_level		; Level 3: aim where Rastan is now.
		cmp	#3
		bcc	!+
		jsr	sw_target
!:		rts

sw_sang:	db	$11, $28, $15, $24, $08, $31	; States 4-9.
sw_sturn:	db	$FF, 1, $FF, 1, 1, $FF

; sw_move - X = bat: a step at the velocity of its direction (arcade $03CFD4).
sw_move:	lda	sw_ang, x
		dec	a
		asl	a
		tay
		lda	sw_vel, y		; dx
		stz	sw_flip, x
		bpl	!+
		inc	sw_flip, x
!:		jsr	.add
		sta	sw_xl, x
		lda	sw_t
		adc	sw_xh, x
		sta	sw_xh, x
		lda	sw_vel + 1, y		; dy
		jsr	.add2
		sta	sw_yl, x
		lda	sw_t
		adc	sw_yh, x
		sta	sw_yh, x
		rts
.add:		pha				; A (signed) + sw_xl: low byte in A,
		and	#$80			; high byte step in sw_t (with carry).
		beq	!+
		lda	#$FF
!:		sta	sw_t
		pla
		clc
		adc	sw_xl, x
		rts
.add2:		pha
		and	#$80
		beq	!+
		lda	#$FF
!:		sta	sw_t
		pla
		clc
		adc	sw_yl, x
		rts

sw_vel:		db	0, -3, 1, -4, 1, -3, 1, -3, 2, -3, 2, -3, 3, -3, 3, -3
		db	3, -2, 3, -2, 3, -1, 3, -1, 4, -1, 3, 0, 3, 0, 4, 1
		db	3, 1, 3, 1, 3, 2, 3, 2, 3, 3, 3, 3, 2, 3, 2, 3
		db	1, 3, 1, 3, 1, 4, 0, 3, 0, 3, -1, 4, -1, 3, -1, 3
		db	-2, 3, -2, 3, -3, 3, -3, 3, -3, 2, -3, 2, -3, 1, -3, 1
		db	-4, 1, -3, 0, -3, 0, -4, -1, -3, -1, -3, -1, -3, -2, -3, -2
		db	-3, -3, -3, -3, -2, -3, -2, -3, -1, -3, -1, -3, -1, -4, 0, -3

; sw_hits - X = flying bat: the sword kills it; touching Rastan, it bites.
sw_hits:	lda	sw_xl, x		; pb_*: the bat, 16 x 16 around (x, y).
		sec
		sbc	#8
		sta	<pb_x0
		lda	sw_xh, x
		sbc	#0
		sta	<pb_x0 + 1
		lda	sw_xl, x
		clc
		adc	#8
		sta	<pb_x1
		lda	sw_xh, x
		adc	#0
		sta	<pb_x1 + 1
		lda	sw_yl, x
		sec
		sbc	#8
		sta	<pb_y0
		lda	sw_yh, x
		sbc	#0
		sta	<pb_y0 + 1
		lda	sw_yl, x
		clc
		adc	#8
		sta	<pb_y1
		lda	sw_yh, x
		adc	#0
		sta	<pb_y1 + 1
		bit	sw_sword
		bpl	.bite
		ldy	#7			; The sword's box.
.s:		lda	sw_box, y
		sta	sb_x0, y		; (absolute: there is no zp,Y store)
		dey
		bpl	.s
		jsr	sword_vs_box
		bcc	.bite
		lda	#SW_DYING		; Killed: 100 points.
		sta	sw_st, x
		lda	#SW_DEAD_FRAMES
		sta	sw_cnt, x
		phx
		lda	#$01
		jsr	score_add
		lda	#SFX_ENEMY
		jsr	sound_sfx
		plx
		rts
.bite:		lda	sw_bite
		bne	.r
		ldy	#7			; Rastan's body.
.b:		lda	sw_box + 8, y
		sta	sb_x0, y
		dey
		bpl	.b
		jsr	sword_vs_box
		bcc	.r
		lda	#SW_BITE
		sta	sw_bite
		lda	#SW_BITE_HP
		phx
		jsr	player_drain
		plx
.r:		rts

; ---------------------------------------------------------------------------
; swarm_draw - SATB entries for the bats (enemies_draw, last: where sprites
; crowd, bats are what the VDC drops, and the first one drawn turns).

swarm_draw:	inc	sw_rot
		lda	sw_rot
		cmp	#SW_N
		bcc	!+
		stz	sw_rot
!:		ldx	sw_rot
		lda	#SW_N
		sta	sw_i
.b:		lda	sw_st, x
		beq	.n
		lda	<en_satb
		cmp	<en_cap
		bcc	!+
		inc	<en_full		; (out of SATB entries)
		rts
!:		jsr	sw_emit
.n:		inx
		cpx	#SW_N
		bcc	!+
		clx
!:		dec	sw_i
		bne	.b
		rts

; sw_emit - X = bat: its SATB entry, if on the screen.
sw_emit:	jsr	sw_screen
		lda	sw_st, x
		cmp	#SW_DYING
		bne	.fly
		lda	#$F8			; Killed: cell $276 at (-8, -8).
		sta	sw_dx
		sta	sw_dy
		lda	#<(SW_VRAM_DEAD >> 5)
		sta	sw_pl
		lda	#>(SW_VRAM_DEAD >> 5)
		sta	sw_ph
		lda	#(SWARM_DEAD_ATTR & $0F) | $80
		sta	sw_a0
		stz	sw_a1
		bra	.pos
.fly:		lda	<p_frame		; Flap step 0-3, 4 frames each: cell $268
		lsr	a			; 8 px up, $269 6 up, $26A (the same
		lsr	a			; image as $269) level, $269.
		and	#3
		tay
		lda	sw_flap_dy, y
		sta	sw_dy
		lda	sw_flap_pat, y
		sta	sw_pl
		lda	#>(SW_VRAM0 >> 5)
		sta	sw_ph
		lda	#(SWARM_CELL0_ATTR & $0F) | $80
		sta	sw_a0
		stz	sw_a1
		lda	#$F8			; 8 px left, 9 when mirrored (flying left).
		ldy	sw_flip, x
		beq	!+
		dec	a
		ldy	#$08
		sty	sw_a1
!:		sta	sw_dx
.pos:		lda	sw_dx			; screen x = sx + dx
		clc
		adc	sw_sx
		sta	sw_sx
		lda	sw_sx + 1
		adc	#$FF			; (dx is negative)
		sta	sw_sx + 1
		lda	sw_dy			; screen y = sy + dy
		clc
		adc	sw_sy
		sta	sw_sy
		lda	sw_dy
		and	#$80
		beq	!+
		lda	#$FF
!:		adc	sw_sy + 1
		sta	sw_sy + 1
		; Visible if -16 < x < 256 and -16 < y < 240.
		lda	sw_sx + 1
		beq	.xok
		cmp	#$FF
		bne	.off
		lda	sw_sx
		cmp	#$F1
		bcc	.off
.xok:		lda	sw_sy + 1
		beq	.yok
		cmp	#$FF
		bne	.off
		lda	sw_sy
		cmp	#$F1
		bcc	.off
		bra	.out
.yok:		lda	sw_sy
		cmp	#240
		bcs	.off
.out:		lda	sw_sy			; y + 64
		clc
		adc	#64
		sta	VDC_DL
		lda	sw_sy + 1
		adc	#0
		and	#$03
		sta	VDC_DH
		lda	sw_sx			; x + 32
		clc
		adc	#32
		sta	VDC_DL
		lda	sw_sx + 1
		adc	#0
		and	#$03
		sta	VDC_DH
		lda	sw_pl			; pattern
		sta	VDC_DL
		lda	sw_ph
		sta	VDC_DH
		lda	sw_a0			; palette, in front; X flip
		sta	VDC_DL
		lda	sw_a1
		sta	VDC_DH
		inc	<en_satb
.off:		rts

sw_flap_dy:	db	-8, -6, 0, -6
sw_flap_pat:	db	<(SW_VRAM0 >> 5), <(SW_VRAM1 >> 5), <(SW_VRAM1 >> 5), <(SW_VRAM1 >> 5)
