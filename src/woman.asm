; ***************************************************************************
;
; Rastan - the woman warrior (approximate), round 1 at x 4523.
;
; Measured in the arcade (sim/scripts/woman.txt): she appears when Rastan is
; 168 px left of her spot and runs at him: 1 px/frame left, hopping down each
; 32 px step (about 26 frames a hop). She does not stop to fight; about 50 px
; past him she turns and runs back right at 1.5 px/frame, hopping up the
; steps, and leaves. Touching her hurts; one hit kills her (300 points).
;
; ***************************************************************************

WOMAN_X		=	4523
WOMAN_Y		=	304
WOMAN_AHEAD	=	168
WOMAN_PAST	=	50		; Turns this far past Rastan.
HOP_FRAMES	=	32		; A hop: 1 px across and 1 px up or down a frame.

WM_LEFT		=	0		; e_alt
WM_DOWN		=	1
WM_RIGHT	=	2
WM_UP		=	3
WM_FALL		=	4

; woman_spawn - once a life, when Rastan reaches WOMAN_X - 168 (a free walker slot).
woman_spawn:	lda	woman_done
		bne	.r
		lda	<p_x			; p_x - (x - 168) in 0 .. 195?
		sec
		sbc	#<(WOMAN_X - WOMAN_AHEAD)
		sta	<etmp
		lda	<p_x + 1
		sbc	#>(WOMAN_X - WOMAN_AHEAD)
		bne	.r
		lda	<etmp
		cmp	#196
		bcs	.r
		ldx	#NUM_EN - 1
!:		lda	e_state, x
		beq	.slot
		dex
		bpl	!-
.r:		rts
.slot:		inc	woman_done
		lda	#<WOMAN_X
		sta	e_xl, x
		lda	#>WOMAN_X
		sta	e_xh, x
		lda	#<WOMAN_Y
		sta	e_yl, x
		lda	#>WOMAN_Y
		sta	e_yh, x
		lda	#EK_WOMAN
		sta	e_kind, x
		stz	e_face, x
		stz	e_sub, x
		lda	#$FF
		sta	e_shown, x
		jsr	map_kind
		jsr	start_walk
		stz	e_alt, x		; WM_LEFT
		rts

; woman_think - X = the woman, alive (enemy_think handled the sword and dying).
woman_think:	jsr	touch_hurts
		inc	e_sub, x
		lda	e_alt, x
		asl	a
		tay
		lda	.modes + 1, y
		pha
		lda	.modes, y
		pha
		rts				; (to mode - 1)
.modes:		dw	.left - 1, .down - 1, .right - 1, .up - 1, .fall - 1

.left:		; 1 px/frame; a drop ahead: hop down; far enough past Rastan: turn.
		lda	#$FF
		jsr	add_x
		lda	e_xl, x			; e_x + 50 < p_x ?
		clc
		adc	#WOMAN_PAST
		sta	<etmp
		lda	e_xh, x
		adc	#0
		sta	<etmp + 1
		lda	<etmp
		cmp	<p_x
		lda	<etmp + 1
		sbc	<p_x + 1
		bcs	!+
		lda	#1			; Turn round.
		sta	e_face, x
		lda	#WM_RIGHT
		sta	e_alt, x
		rts
!:		lda	#$F4			; Floor 12 px ahead?
		jsr	floor_ahead
		bcs	.r
		lda	#WM_DOWN
		jmp	.hop
.down:		lda	#$FF			; Hop down: left 1, down 1.
		jsr	add_x
		lda	#1
		jsr	add_y
		bra	.hopping
.right:		; 1.5 px/frame; a step up ahead: hop up.
		lda	e_sub, x
		and	#1
		inc	a
		jsr	add_x
		lda	#12			; Solid 12 px ahead, at body height?
		jsr	wall_ahead
		bcc	!+
		lda	#WM_UP
		jmp	.hop
!:		lda	#12			; A drop: fall.
		jsr	floor_ahead
		bcs	.r
		lda	#WM_FALL
		sta	e_alt, x
.r:		rts
.up:		lda	#1			; Hop up: right 1, up 1.
		jsr	add_x
		lda	#$FF
		jsr	add_y
.hopping:	dec	e_timer, x
		bne	.r
		lda	e_face, x		; Hop done: walk on (or fall).
		beq	!+
		lda	#WM_RIGHT
		bra	!++
!:		lda	#WM_LEFT
!:		sta	e_alt, x
		jsr	woman_walk_anim
		lda	#0
		jsr	floor_ahead
		bcs	.r
		lda	#WM_FALL
		sta	e_alt, x
		rts
.fall:		lda	#2
		jsr	add_y
		lda	e_yh, x			; Fell out of the world (the waterfall): gone.
		cmp	#>480
		bcc	!+
		lda	e_yl, x
		cmp	#<480
		bcc	!+
		stz	e_state, x
		rts
!:		lda	#0
		jsr	floor_ahead
		bcc	.r
		lda	#17			; Land: anchor 16 px above the floor cell.
		ldy	#16
		jsr	snap_floor
		lda	e_face, x
		beq	!+
		lda	#WM_RIGHT
		bra	!++
!:		lda	#WM_LEFT
!:		sta	e_alt, x
		rts

.hop:		sta	e_alt, x
		lda	#HOP_FRAMES
		sta	e_timer, x
		lda	#<anim_woman_hop
		ldy	#>anim_woman_hop
		jmp	enemy_set_anim

woman_walk_anim:
		lda	#<anim_woman_walk
		ldy	#>anim_woman_walk
		jmp	enemy_set_anim

; floor_ahead - A = signed x offset: carry set if a floor is at (e_x + A, e_y + 17).
floor_ahead:	ldy	#17
		bra	probe_at
; wall_ahead - A = signed x offset: carry set if solid at (e_x + A, e_y - 8).
wall_ahead:	ldy	#$F8
		jsr	probe_at_raw
		and	#$0F
		cmp	#1
		beq	!+
		clc
		rts
!:		sec
		rts
probe_at:	jsr	probe_at_raw
		phx
		jsr	is_floor
		plx
		rts
probe_at_raw:	; cx = e_x + A, cy = e_y + Y (both signed); A = the collision code.
		pha
		clc
		adc	e_xl, x
		sta	<cx
		pla
		and	#$80
		beq	!+
		lda	#$FF
!:		adc	e_xh, x
		sta	<cx + 1
		tya
		clc
		adc	e_yl, x
		sta	<cy
		tya
		and	#$80
		beq	!+
		lda	#$FF
!:		adc	e_yh, x
		sta	<cy + 1
		phx
		jsr	coll_at
		plx
		rts
