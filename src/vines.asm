; ***************************************************************************
;
; Rastan - swinging vines (marker $4F; the arcade's object type $4F).
;
; Measured in the arcade (the bot's swing over the chasm at x 2750,
; build/vine.snp): a vine hangs from its anchor (marker + (22, -96)) and
; swings with a phase counter that steps every 2 frames through 90 steps
; (180 frames): out to the right in 22 half-steps of its 45 poses, a pause,
; back, then the same to the left. Rastan, caught in the air near its end,
; hangs there (body 15 / legs 13): his anchor 8 + about 2 px per half-step
; right of the vine's, 107 px below it, 93 at the ends of the swing. Jump
; lets go, but only on the side he faces (the arcade ignored a jump on the
; far side); he leaves with an ordinary jump.
;
; The lava hall's three vines (markers $4F, $50, $51, world square ($11, -1))
; swing together here; the arcade's phases there are not measured.
;
; ***************************************************************************

NUM_VINES	=	6		; (all rounds': vr_first)
VINE_NEAR	=	240		; Present while |p_x - x| < this.
VINE_GRAB_X	=	40		; Caught within this of the hanging point,
VINE_GRAB_Y	=	24
VINE_NOGRAB	=	20		; and not again this many frames after a jump.

; Round 1's: the chasm's, then the lava hall's three.
; Round 2's: markers $4F at (5632, 208) and (8416, 240), placed as round 1's
; chasm vine is from its marker at (2720, 80): + (30, -96).
vine_x_l:	db	<2750, <8830, <8990, <9150, <5662, <8446
vine_x_h:	db	>2750, >8830, >8990, >9150, >5662, >8446
vine_y_l:	db	<-16, <-496, <-496, <-496, <112, <144
vine_y_h:	db	>-16, >-496, >-496, >-496, >112, >144
vine_bit:	db	1, 2, 4, 8, 16, 32
; Phase offset (frames) within the 180-frame swing. The lava hall's middle vine
; swings opposite its neighbours, so a hop always meets the next vine coming
; back: measured only for the chasm's vine, chosen for the hall's.
vine_phase:	db	0, 0, 90, 0, 0, 0
; Each round's vines: vr_first[round - 1] .. vr_first[round] - 1.
vr_first:	db	0, 4, 6

; Per phase: the swing's half-step (signed), Rastan's x and y from the anchor.
vine_h:		db	0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14
			db	15, 16, 17, 18, 19, 20, 21, 22, 22, 21, 20, 19, 18, 17, 16
			db	15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1
			db	0, -1, -2, -3, -4, -5, -6, -7, -8, -9, -10, -11, -12, -13, -14
			db	-15, -16, -17, -18, -19, -20, -21, -22, -22, -21, -20, -19, -18, -17, -16
			db	-15, -14, -13, -12, -11, -10, -9, -8, -7, -6, -5, -4, -3, -2, -1
vine_dx:		db	8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 29, 30, 32, 34, 36
			db	38, 40, 42, 44, 45, 47, 49, 51, 51, 49, 47, 45, 44, 42, 40
			db	38, 36, 34, 32, 30, 29, 26, 24, 22, 20, 18, 16, 14, 12, 10
			db	8, 6, 4, 2, 0, -2, -4, -6, -8, -10, -13, -14, -16, -18, -20
			db	-22, -24, -26, -28, -29, -31, -33, -35, -35, -33, -31, -29, -28, -26, -24
			db	-22, -20, -18, -16, -14, -13, -10, -8, -6, -4, -2, 0, 2, 4, 6
vine_dy:		db	107, 107, 107, 107, 106, 106, 106, 106, 105, 105, 104, 104, 103, 102, 101
			db	100, 99, 99, 98, 97, 95, 94, 93, 93, 94, 95, 97, 98, 99, 99
			db	100, 101, 102, 103, 104, 104, 105, 105, 106, 106, 106, 106, 107, 107, 107
			db	107, 107, 107, 107, 106, 106, 106, 106, 105, 105, 104, 104, 103, 102, 101
			db	100, 99, 99, 98, 97, 95, 94, 93, 93, 94, 95, 97, 98, 99, 99
			db	100, 101, 102, 103, 104, 104, 105, 105, 106, 106, 106, 106, 107, 107, 107

; vines_spawn - vines whose anchor Rastan is near (uses etmp).
vines_spawn:
		ldx	<cur_round
		lda	vr_first, x
		sta	vn_end
		ldy	vr_first - 1, x
.loop:		lda	vines_done
		and	vine_bit, y
		bne	.next
		lda	vine_x_l, y		; |p_x - x| < VINE_NEAR?
		sec
		sbc	<p_x
		sta	<etmp
		lda	vine_x_h, y
		sbc	<p_x + 1
		jsr	vine_abs
		cmp	#VINE_NEAR
		bcs	.next
		ldx	#SPEC_FIRST		; A free special slot?
!:		lda	e_state, x
		beq	.slot
		inx
		cpx	#SPEC_LAST + 1
		bne	!-
		rts
.slot:		lda	vines_done
		ora	vine_bit, y
		sta	vines_done
		lda	vine_x_l, y
		sta	e_xl, x
		lda	vine_x_h, y
		sta	e_xh, x
		lda	vine_y_l, y
		sta	e_yl, x
		lda	vine_y_h, y
		sta	e_yh, x
		stz	e_face, x
		lda	#$FF
		sta	e_shown, x
		lda	#EK_VINE
		sta	e_kind, x
		phy
		jsr	map_kind
		jsr	start_walk		; (the swing loops)
		ply
		tya				; Which vine (after start_walk, which
		sta	e_range, x		; sets e_range).
.next:		iny
		cpy	vn_end
		bne	.loop
		rts

; vines_tick - the shared swing clock, once a frame (enemies_update).
vines_tick:	inc	vine_t
		lda	vine_t
		cmp	#180
		bcc	!+
		stz	vine_t
!:		rts

; vine_think - X = vine: swing; carry Rastan, or catch him; go when he is far.
vine_think:	ldy	e_range, x		; Phase = (clock + its offset) / 2, mod 90.
		lda	vine_t
		clc
		adc	vine_phase, y
		cmp	#180
		bcc	!+
		sbc	#180
!:		lsr	a
		tay
		lda	vine_dx, y		; ex = hanging point x
		clc
		adc	e_xl, x
		sta	<ex
		lda	vine_dx, y
		and	#$80
		beq	!+
		lda	#$FF
!:		adc	e_xh, x
		sta	<ex + 1
		lda	vine_dy, y		; ey = hanging point y
		clc
		adc	e_yl, x
		sta	<ey
		lda	e_yh, x
		adc	#0
		sta	<ey + 1
		lda	<p_state
		cmp	#ST_SWING
		bne	.loose
		txa				; Rastan on this vine: carry him.
		inc	a
		cmp	<p_vine
		bne	.r
		lda	vine_h, y
		sta	<p_vine_h
.carry:		lda	<ex
		sta	<p_x
		lda	<ex + 1
		sta	<p_x + 1
		lda	<ey
		sta	<p_y
		lda	<ey + 1
		sta	<p_y + 1
.r:		rts
.loose:		cmp	#ST_AIR			; In the air near the hanging point?
		beq	!+
		stz	<p_vine_last		; (landed: any vine again)
		bra	.far
!:		lda	<p_nograb
		bne	.far
		txa				; Not the one he just let go of.
		inc	a
		cmp	<p_vine_last
		beq	.far
		lda	<p_x
		sec
		sbc	<ex
		sta	<etmp
		lda	<p_x + 1
		sbc	<ex + 1
		jsr	vine_abs
		cmp	#VINE_GRAB_X + 1
		bcs	.far
		lda	<p_y
		sec
		sbc	<ey
		sta	<etmp
		lda	<p_y + 1
		sbc	<ey + 1
		jsr	vine_abs
		cmp	#VINE_GRAB_Y + 1
		bcs	.far
		txa				; Caught.
		inc	a
		sta	<p_vine
		lda	vine_h, y
		sta	<p_vine_h
		jsr	enter_swing
		bra	.carry
.far:		lda	e_xl, x			; Rastan far away: gone (it comes back).
		sec
		sbc	<p_x
		sta	<etmp
		lda	e_xh, x
		sbc	<p_x + 1
		jsr	vine_abs
		cmp	#VINE_NEAR + 8
		bcc	.r
		ldy	e_range, x
		lda	vine_bit, y
		eor	#$FF
		and	vines_done
		sta	vines_done
		stz	e_state, x
		rts
; vine_abs - A:etmp = a signed difference (flags of A) -> A = its size, $FF past 255.
vine_abs:	bpl	.pos
		eor	#$FF
		pha
		lda	<etmp
		eor	#$FF
		clc
		adc	#1
		sta	<etmp
		pla
		adc	#0
.pos:		bne	.big
		lda	<etmp
		rts
.big:		lda	#$FF
		rts
