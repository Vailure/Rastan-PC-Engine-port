; ***************************************************************************
;
; Rastan - boulders (approximate), round 1.
;
; Measured in the arcade (round 1 census; arcade slots 14/15): boulders
; appear when Rastan reaches 169 px left of their spot, hop 4 px, then fall at
; 2 px/frame. Two at x 2898 fall through everything and wrap from the bottom
; of the 512 px world to the top, a rockfall column. The ones at 4601 and
; 6674 land and roll left at 7/6 px/frame, dropping off ledges as they go.
; Touching one hurts like a club; the sword does nothing to them.
;
; ***************************************************************************

NUM_ROCKS	=	4
ROCK_AHEAD	=	169
ROCK_WINDOW	=	196
ROCK_FOOT	=	9		; Floor probe below the anchor (it rests 9 px above a floor).
SPEC_FIRST	=	NUM_EN + 2	; Special slots 6..8.
SPEC_LAST	=	NUM_BIG - 1

RM_FALL		=	0		; e_alt
RM_ROLL		=	1
RM_LOOP		=	2		; Falls forever.

rock_x_l:	db	<2898, <2898, <4601, <6674
rock_x_h:	db	>2898, >2898, >4601, >6674
rock_y_l:	db	<427, <139, <243, <123
rock_y_h:	db	>427, >139, >243, >123
rock_mode:	db	RM_LOOP, RM_LOOP, RM_FALL, RM_FALL
rock_bit:	db	1, 2, 4, 8

; rock_spawn - boulders whose spot Rastan nears (uses etmp, ex).
rock_spawn:	cly
.loop:		lda	rocks_done
		and	rock_bit, y
		bne	.next
		lda	rock_x_l, y		; p_x - (x - 169) in 0 .. 195?
		sec
		sbc	#<ROCK_AHEAD
		sta	<etmp
		lda	rock_x_h, y
		sbc	#>ROCK_AHEAD
		sta	<etmp + 1
		lda	<p_x
		sec
		sbc	<etmp
		sta	<etmp
		lda	<p_x + 1
		sbc	<etmp + 1
		bne	.next
		lda	<etmp
		cmp	#ROCK_WINDOW
		bcs	.next
		ldx	#SPEC_FIRST		; A free special slot?
!:		lda	e_state, x
		beq	.slot
		inx
		cpx	#SPEC_LAST + 1
		bne	!-
		rts
.slot:		lda	rocks_done
		ora	rock_bit, y
		sta	rocks_done
		lda	rock_x_l, y
		sta	e_xl, x
		lda	rock_x_h, y
		sta	e_xh, x
		lda	rock_y_l, y
		sta	e_yl, x
		lda	rock_y_h, y
		sta	e_yh, x
		lda	rock_mode, y
		sta	e_alt, x
		stz	e_face, x
		stz	e_sub, x
		stz	e_timer, x
		lda	#$FF
		sta	e_shown, x
		lda	#EK_ROCK
		sta	e_kind, x
		phy
		jsr	map_kind
		jsr	start_walk		; (ES_WALK: the spin loops)
		ply
.next:		iny
		cpy	#NUM_ROCKS
		bne	.loop
		rts

; rock_think - X = boulder.
rock_think:	jsr	touch_hurts
		lda	e_timer, x		; A hop at first: up 1 px every other
		cmp	#8			; frame for 8 frames.
		bcs	.move
		inc	e_timer, x
		and	#1
		bne	.r
		lda	#$FF
		jmp	add_y
.move:		lda	e_alt, x
		cmp	#RM_ROLL
		beq	.roll
		lda	#2			; Falling 2 px/frame, wrapping at 512.
		jsr	add_y
		lda	e_yh, x
		and	#1
		sta	e_yh, x
		lda	e_alt, x
		cmp	#RM_LOOP
		beq	.r
		jsr	rock_floor
		bcc	.r
		lda	#ROCK_FOOT		; Landed: sit on the floor cell's top,
		tay				; and roll.
		jsr	snap_floor
		lda	#RM_ROLL
		sta	e_alt, x
.r:		rts
.roll:		inc	e_sub, x		; 7 px every 6 frames, to the left.
		lda	e_sub, x
		cmp	#6
		bcc	!+
		stz	e_sub, x
		lda	#$FE
		bra	.step
!:		lda	#$FF
.step:		jsr	add_x
		jsr	rock_floor		; Nothing under it: fall.
		bcs	.r
		stz	e_alt, x		; RM_FALL
		rts

; snap_floor - X's y = ((y + A) & ~7) - Y: the anchor Y px above the top of
; the floor cell probed A px below it.
snap_floor:	clc
		adc	e_yl, x
		sta	<etmp
		lda	e_yh, x
		adc	#0
		sta	<etmp + 1
		sty	<ex
		lda	<etmp
		and	#$F8
		sec
		sbc	<ex
		sta	e_yl, x
		lda	<etmp + 1
		sbc	#0
		sta	e_yh, x
		rts

; rock_floor - carry set if X stands on a floor (probe at x, y + ROCK_FOOT).
rock_floor:	lda	e_xl, x
		sta	<cx
		lda	e_xh, x
		sta	<cx + 1
		lda	e_yl, x
		clc
		adc	#ROCK_FOOT
		sta	<cy
		lda	e_yh, x
		adc	#0
		sta	<cy + 1
		phx
		jsr	coll_at
		jsr	is_floor
		plx
		rts
