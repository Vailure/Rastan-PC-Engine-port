; ***************************************************************************
;
; Rastan - the gargoyle (approximate), round 1 at x 4608 and 6841.
;
; Measured in the arcade (sim/scripts/gargoyle.txt, round 1 census): the
; gargoyle appears when Rastan is 176 px left of its spot and flies the same
; path every time, whatever Rastan does: it glides in, hovers, dives past him,
; turns and swoops back, about 410 frames until it leaves the screen. Its
; path (per-frame steps from the spawn point, pce_objects.py PATHS) is
; replayed here, by two objects: body and wings (arcade slots 9 and 10).
; Touching the body hurts; swings and thrusts did nothing to it in the arcade.
;
; ***************************************************************************

NUM_GARGS	=	2
GARG_AHEAD	=	176
GARG_WINDOW	=	196

	.if	STAGE_ROUND = 1
garg_x_l:	db	<4608, <6841
garg_x_h:	db	>4608, >6841
garg_y_l:	db	<295, <167
garg_y_h:	db	>295, >167
garg_bit:	db	1, 2

; garg_spawn - a gargoyle (two special slots) when Rastan nears its spot.
garg_spawn:
		cly
.loop:		lda	gargs_done
		and	garg_bit, y
		bne	.next
		lda	garg_x_l, y		; p_x - (x - 176) in 0 .. 195?
		sec
		sbc	#<GARG_AHEAD
		sta	<etmp
		lda	garg_x_h, y
		sbc	#>GARG_AHEAD
		sta	<etmp + 1
		lda	<p_x
		sec
		sbc	<etmp
		sta	<etmp
		lda	<p_x + 1
		sbc	<etmp + 1
		bne	.next
		lda	<etmp
		cmp	#GARG_WINDOW
		bcc	.spawn
.next:		iny
		cpy	#NUM_GARGS
		bne	.loop
		rts
.spawn:		ldx	#SPEC_FIRST		; Two free special slots?
		lda	#EK_GARG
		sta	<etmp + 1
.find:		lda	e_state, x
		bne	.used
		jsr	.place
		lda	<etmp + 1
		cmp	#EK_WINGS
		beq	.both
		lda	#EK_WINGS
		sta	<etmp + 1
.used:		inx
		cpx	#SPEC_LAST + 1
		bne	.find
		lda	<etmp + 1		; Not both: undo the body.
		cmp	#EK_WINGS
		bne	!+
		ldx	#SPEC_FIRST
.undo:		lda	e_kind, x
		cmp	#EK_GARG
		bne	.u2
		lda	e_state, x
		beq	.u2
		stz	e_state, x
		bra	!+
.u2:		inx
		cpx	#SPEC_LAST + 1
		bne	.undo
!:		rts
.both:		lda	gargs_done
		ora	garg_bit, y
		sta	gargs_done
		rts

.place:		; X = slot, Y = gargoyle, etmp+1 = kind.
		lda	garg_x_l, y
		sta	e_xl, x
		lda	garg_x_h, y
		sta	e_xh, x
		lda	garg_y_l, y
		sta	e_yl, x
		lda	garg_y_h, y
		sta	e_yh, x
		lda	<etmp + 1
		sta	e_kind, x
		stz	e_face, x
		stz	e_dmg, x
		stz	e_flash, x
		lda	#$FF
		sta	e_shown, x
		phy
		jsr	map_kind
		jsr	start_walk		; ES_WALK, its looping animation
		ply
		stz	e_timer, x		; No run loaded yet (after start_walk,
		lda	#<path_gargoyle		; which sets e_range).
		sta	e_range, x
		lda	#>path_gargoyle
		sta	e_alt, x
		rts

; garg_think - X = body or wings: the next step of the path. Only the wings
; can be struck (the arcade's sword test skips the body's slot 9): two hits,
; or one stronger blow, and body and wings burst together, 500 points each
; (sim/scripts/gargkill.txt).
garg_think:	lda	e_state, x
		cmp	#ES_DYING
		bne	.alive
		lda	e_animend, x		; The burst done: gone.
		beq	!+
		stz	e_state, x
!:		rts
.alive:		lda	e_flash, x		; Struck: untouchable 16 frames (it
		beq	!+			; flies on).
		dec	e_flash, x
		bra	.path
!:		jsr	touch_hurts		; (body and wings: the arcade's both drain 8)
		lda	e_kind, x
		cmp	#EK_WINGS
		bne	.path
		jsr	sword_strike
		bcc	.path
		jmp	garg_kill
.path:
		lda	e_timer, x
		bne	.step
		lda	e_range, x		; Next run: dx, dy, frames (0: the end).
		sta	<ep
		lda	e_alt, x
		sta	<ep + 1
		ldy	#2
		lda	[ep], y
		bne	!+
		stz	e_state, x		; Path done (off screen by now).
		rts
!:		sta	e_timer, x
		lda	[ep]
		sta	e_sub, x
		ldy	#1
		lda	[ep], y
		sta	e_struck, x
		lda	<ep
		clc
		adc	#3
		sta	e_range, x
		lda	<ep + 1
		adc	#0
		sta	e_alt, x
.step:		dec	e_timer, x
		lda	e_sub, x
		jsr	add_x
		lda	e_struck, x
		jmp	add_y

; garg_kill - the wings struck down: both halves burst (each its own death
; animation and 500 points).
garg_kill:	ldx	#SPEC_FIRST
.loop:		lda	e_state, x
		beq	.next
		cmp	#ES_DYING
		beq	.next
		lda	e_kind, x
		cmp	#EK_GARG
		beq	.kill
		cmp	#EK_WINGS
		bne	.next
.kill:		phx
		jsr	kill_enemy
		plx
.next:		inx
		cpx	#SPEC_LAST + 1
		bne	.loop
		rts

	.else
; (round 1's own: other rounds' builds leave it out, bank space)
garg_spawn:
garg_think:
garg_kill:	rts
	.endif