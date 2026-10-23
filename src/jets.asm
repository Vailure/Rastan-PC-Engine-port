; ***************************************************************************
;
; Rastan - fire jets over the castle's lava pits (approximate), x 9870-10062
; in the lava hall (world square ($13, -1); arcade census x 10382-10574, y 280).
;
; Measured in the arcade (round 1 census, sim/scripts/castle.txt): a jet
; erupts when Rastan is 172 px left of it: the flame rises in the pit (17
; frames), dies down for 18, then a column of fire flickers for 57 frames.
; It erupts again about 220 frames after the last start while Rastan is
; still near. The column hurts as it shoots up (its first 11 frames: the
; arcade's state 2, a touch of type 2: 8 units drained).
;
; ***************************************************************************

NUM_JETS	=	3
JET_AHEAD	=	172
JET_RANGE	=	172 + 64	; Erupts while p_x is in x - 172 .. x + 63.
JET_PERIOD	=	220
JET_RISE	=	17
JET_PAUSE	=	18
JET_COLUMN	=	57
JET_SHOOT	=	11

JP_RISE		=	0		; e_alt
JP_PAUSE	=	1
JP_COLUMN	=	2

jet_x_l:	db	<9870, <9966, <10062
jet_x_h:	db	>9870, >9966, >10062
jet_y_l:	db	<-232, <-235, <-232
jet_y_h:	db	>-232, >-235, >-232

; jets_spawn - erupt the jets Rastan is near, once per JET_PERIOD each.
jets_spawn:
	.if	STAGE_ROUND - 1		; (round 1's own: none in other rounds yet)
		rts
	.endif
		cly
.loop:		lda	jet_wait, y
		beq	!+
		dec	a
		sta	jet_wait, y
		bra	.next
!:		lda	jet_x_l, y		; p_x - (x - 172) in 0 .. JET_RANGE - 1?
		sec
		sbc	#<JET_AHEAD
		sta	<etmp
		lda	jet_x_h, y
		sbc	#>JET_AHEAD
		sta	<etmp + 1
		lda	<p_x
		sec
		sbc	<etmp
		sta	<etmp
		lda	<p_x + 1
		sbc	<etmp + 1
		bne	.next
		lda	<etmp
		cmp	#JET_RANGE
		bcs	.next
		ldx	#SPEC_FIRST		; A free special slot?
!:		lda	e_state, x
		beq	.slot
		inx
		cpx	#SPEC_LAST + 1
		bne	!-
		bra	.next
.slot:		lda	#JET_PERIOD
		sta	jet_wait, y
		lda	jet_x_l, y
		sta	e_xl, x
		lda	jet_x_h, y
		sta	e_xh, x
		lda	jet_y_l, y
		sta	e_yl, x
		lda	jet_y_h, y
		sta	e_yh, x
		lda	#EK_JET
		sta	e_kind, x
		stz	e_face, x
		lda	#$FF
		sta	e_shown, x
		phy
		jsr	map_kind
		jsr	start_walk
		lda	#<anim_jet_rise		; (not looping: ES_ATTACK)
		ldy	#>anim_jet_rise
		jsr	enemy_set_anim
		ply
		lda	#ES_ATTACK
		sta	e_state, x
		stz	e_alt, x		; JP_RISE
		lda	#JET_RISE
		sta	e_timer, x
.next:		iny
		cpy	#NUM_JETS
		beq	!+
		jmp	.loop
!:		rts

; jet_think - X = jet.
jet_think:	lda	e_alt, x		; The flame hurts only as the column
		cmp	#JP_COLUMN		; shoots up, its first JET_SHOOT frames
		bne	!+			; (the arcade's state 2: castle.snp,
		lda	e_timer, x		; markers $4B and $57, 1475-1485; its
		cmp	#JET_COLUMN - JET_SHOOT + 1	; box $37 then, a touch type 2).
		bcc	!+
		jsr	touch_hurts
!:		dec	e_timer, x
		bne	.r
		lda	e_alt, x
		cmp	#JP_RISE
		bne	!+
		inc	e_alt, x		; Rise done: hidden for a while.
		lda	#ES_HIDDEN
		sta	e_state, x
		lda	#JET_PAUSE
		sta	e_timer, x
		rts
!:		cmp	#JP_PAUSE
		bne	.done
		inc	e_alt, x		; The column.
		lda	#ES_WALK
		sta	e_state, x
		lda	#JET_COLUMN
		sta	e_timer, x
		lda	#<anim_jet_column
		ldy	#>anim_jet_column
		jmp	enemy_set_anim
.done:		stz	e_state, x		; Column done: gone till the next eruption.
.r:		rts
