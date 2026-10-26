; ***************************************************************************
;
; Rastan - round 2's piranhas and rounds 2 and 3's green demon (approximate).
;
; Measured on the bot's runs through the rounds (build/r2run.snp, r3run.snp):
;
; - Piranhas (arcade slots 15-17): one leaps out of the water at its spot as
;   Rastan comes 160 px left of it, 4 px a frame up, over to the left in an
;   arc 82 px wide, down into the water, and at once back the same way: a
;   210-frame cycle (object_specs.py PATHS 'piranha'), for as long as it is
;   near. Touching it knocks Rastan back (the arcade's touch code 3); one hit
;   kills it (400 points).
; - The green demon (arcade slots 9 and 10, the gargoyle's, with the arcade's
;   object +$15 byte $2E/$2C: another flight): it comes in as the gargoyle
;   does, gliding and diving (its first 180 frames, PATHS 'garg2'), then
;   hunts Rastan: 2 px a frame toward him, turning only once 24 px past him,
;   drifting to 40 px above his anchor; after 720 frames it flies off. Body
;   and wings are two objects as the gargoyle's; touching drains (code 1); the
;   wings take the sword, one blow (500 points each half).
;
; In bank XBANK2 (the x_pir_* and x_g2_* trampolines).
;
; ***************************************************************************

PIR_AHEAD	=	160
BEAST_WINDOW	=	196
G2_AHEAD	=	176
G2_LIFE		=	180		; Hunting frames / 4.

; ---------------------------------------------------------------------------
; Spawning: once a life each, when p_x - (x - ahead) is in 0 .. 195.

pir_x_l:	db	<5800, <7399, <7656
pir_x_h:	db	>5800, >7399, >7656
pir_y_l:	db	<375, <471, <471
pir_y_h:	db	>375, >471, >471
NUM_PIRS	=	3

g2_x_l:		db	<5819, <6649
g2_x_h:		db	>5819, >6649
g2_y_l:		db	<133, <195
g2_y_h:		db	>133, >195
g2_first:	db	0, 0, 1, 2		; (round n's: [n - 1] .. [n] - 1)

		.bss
pirs_done:	ds	1		; Piranhas spawned this life (bits).
g2_done:	ds	1		; The green demon spawned this life.
g2_tmp:		ds	1
		.code

; beasts_reset - a restart: they all come again.
beasts_reset:	stz	pirs_done
		stz	g2_done
		rts

; beast_near - Y = entry, ex/ex+1 = its x, A = ahead: carry set if Rastan is
; in the window.
beast_near:	sta	<etmp
		lda	<ex
		sec
		sbc	<etmp
		sta	<etmp
		lda	<ex + 1
		sbc	#0
		sta	<etmp + 1
		lda	<p_x
		sec
		sbc	<etmp
		sta	<etmp
		lda	<p_x + 1
		sbc	<etmp + 1
		bne	.no
		lda	<etmp
		cmp	#BEAST_WINDOW
		bcs	.no
		sec
		rts
.no:		clc
		rts

; beast_slot - X = a free slot (carry set), or carry clear: a special slot,
; else a walker's (the special slots are few: a vine, a boulder, a piranha).
beast_slot:	ldx	#SPEC_FIRST
!:		lda	e_state, x
		beq	.yes
		inx
		cpx	#SPEC_LAST + 1
		bne	!-
		ldx	#NUM_EN - 1
!:		lda	e_state, x
		beq	.yes
		dex
		bpl	!-
		clc
		rts
.yes:		sec
		rts

; beast_place - X = slot: at ex, ey, kind A, its walk animation, path ep.
beast_place:	sta	e_kind, x
		lda	<ex
		sta	e_xl, x
		lda	<ex + 1
		sta	e_xh, x
		lda	<ey
		sta	e_yl, x
		lda	<ey + 1
		sta	e_yh, x
		stz	e_face, x
		stz	e_dmg, x
		stz	e_flash, x
		lda	#$FF
		sta	e_shown, x
		lda	<ep			; (start_walk may use ep)
		pha
		lda	<ep + 1
		pha
		jsr	map_kind
		jsr	start_walk		; ES_WALK, its looping animation
		pla
		sta	e_alt, x		; The path.
		pla
		sta	e_range, x
		stz	e_timer, x		; (no run loaded yet)
		rts

pir_spawn:	lda	<cur_round
		cmp	#2
		bne	.r
		cly
.loop:		lda	pirs_done
		and	.bit, y
		bne	.next
		lda	pir_x_l, y
		sta	<ex
		lda	pir_x_h, y
		sta	<ex + 1
		lda	#PIR_AHEAD
		jsr	beast_near
		bcc	.next
		jsr	beast_slot
		bcc	.r
		lda	pirs_done
		ora	.bit, y
		sta	pirs_done
		lda	pir_y_l, y
		sta	<ey
		lda	pir_y_h, y
		sta	<ey + 1
		lda	#<path_piranha
		sta	<ep
		lda	#>path_piranha
		sta	<ep + 1
		lda	#EK_PIRANHA
		phy
		jsr	beast_place
		ply
.next:		iny
		cpy	#NUM_PIRS
		bne	.loop
.r:		rts
.bit:		db	1, 2, 4

g2_spawn:	lda	g2_done
		bne	.r
		ldx	<cur_round
		lda	g2_first, x
		sta	g2_tmp			; (the round's last + 1)
		ldy	g2_first - 1, x
		cpy	g2_tmp
		beq	.r
		lda	g2_x_l, y
		sta	<ex
		lda	g2_x_h, y
		sta	<ex + 1
		lda	#G2_AHEAD
		jsr	beast_near
		bcc	.r
		jsr	beast_slot		; Two free slots?
		bcc	.r
		stx	g2_tmp
		inc	e_state, x		; (held while the second is looked for)
		jsr	beast_slot
		phx
		ldx	g2_tmp
		stz	e_state, x
		plx
		bcs	.a
.r:		rts
.a:		inc	g2_done
		lda	g2_y_l, y
		sta	<ey
		lda	g2_y_h, y
		sta	<ey + 1
		lda	#<path_garg2
		sta	<ep
		lda	#>path_garg2
		sta	<ep + 1
		lda	#EK_G2W			; (the second slot: the wings)
		jsr	beast_place
		lda	#<path_garg2
		sta	<ep
		lda	#>path_garg2
		sta	<ep + 1
		ldx	g2_tmp
		lda	#EK_G2
		jmp	beast_place

; ---------------------------------------------------------------------------
; beast_path - X: the next step of its path (runs of dx, dy, frames from
; e_range/e_alt; the group's bank at $8000). Carry set at the path's end.
beast_path:	lda	e_timer, x
		bne	.step
		lda	e_range, x		; Next run: dx, dy, frames (0: the end).
		sta	<ep
		lda	e_alt, x
		sta	<ep + 1
		ldy	#2
		lda	[ep], y
		bne	!+
		sec
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
		jsr	add_y
		clc
		rts

; beast_dying - X: carry set (and the slot freed once its burst is done) if dying.
beast_dying:	lda	e_state, x
		cmp	#ES_DYING
		bne	.no
		lda	e_animend, x
		beq	!+
		stz	e_state, x
!:		sec
		rts
.no:		clc
		rts

pir_think:	jsr	beast_dying
		bcs	.r
		lda	e_flash, x
		beq	!+
		dec	e_flash, x
		bra	.path
!:		jsr	touch_hurts
		jsr	sword_strike
		bcc	.path
		jmp	kill_enemy
.path:		jsr	beast_path
		bcc	.r
		lda	#<path_piranha		; The cycle again.
		sta	e_range, x
		lda	#>path_piranha
		sta	e_alt, x
		stz	e_timer, x
.r:		rts

; The green demon: e_range/e_alt the path, then e_range = 0 and e_alt its
; hunting time left (in 4 frames); e_sub its x step.
g2_think:	jsr	beast_dying
		bcs	.r
		lda	e_flash, x
		beq	!+
		dec	e_flash, x
		bra	.fly
!:		jsr	touch_hurts
		lda	e_kind, x
		cmp	#EK_G2W
		bne	.fly
		jsr	sword_strike
		bcc	.fly
		jmp	g2_kill
.fly:		lda	e_range, x
		beq	.hunt
		jsr	beast_path
		bcc	.r
		stz	e_range, x		; The path done: hunt.
		lda	#G2_LIFE
		sta	e_alt, x
		stz	e_sub, x
		stz	e_timer, x
.r:		rts
.hunt:		lda	e_alt, x
		bne	!+
		lda	#-3			; Time's up: off to the upper left, gone
		jsr	add_x			; once well above the screen.
		lda	#-2
		jsr	add_y
		lda	e_yl, x
		clc
		adc	#64
		sta	<etmp
		lda	e_yh, x
		adc	#0
		sta	<etmp + 1
		lda	<etmp
		cmp	<scroll_y
		lda	<etmp + 1
		sbc	<scroll_y + 1
		bpl	.r
		stz	e_state, x
		rts
!:		inc	e_timer, x		; (hunting time: 4 frames a count)
		lda	e_timer, x
		and	#3
		bne	!+
		dec	e_alt, x
!:		lda	<p_x			; dx = p_x - x
		sec
		sbc	e_xl, x
		sta	<etmp
		lda	<p_x + 1
		sbc	e_xh, x
		sta	<etmp + 1
		bmi	.left
		bne	.goright		; (256 or more right of it)
		lda	<etmp
		cmp	#24
		bcc	.keep
.goright:	lda	#2
		bra	.setx
.left:		cmp	#$FF
		bne	.goleft
		lda	<etmp
		cmp	#-24
		bcs	.keep
.goleft:	lda	#-2
.setx:		sta	e_sub, x
.keep:		lda	e_sub, x
		bne	!+
		lda	#2			; (at first: toward him)
		sta	e_sub, x
!:		lda	e_sub, x
		bmi	!+
		lda	#1
		sta	e_face, x
		bra	!++
!:		stz	e_face, x
!:		lda	e_sub, x
		jsr	add_x
		lda	<p_y			; Toward 40 px above his anchor, 1 px a frame.
		sec
		sbc	#40
		sta	<etmp
		lda	<p_y + 1
		sbc	#0
		sta	<etmp + 1
		lda	<etmp
		cmp	e_yl, x
		lda	<etmp + 1
		sbc	e_yh, x
		bmi	.up
		lda	<etmp
		cmp	e_yl, x
		bne	.down
		lda	<etmp + 1
		cmp	e_yh, x
		beq	.r2
.down:		lda	#1
		jmp	add_y
.up:		lda	#-1
		jmp	add_y
.r2:		rts

; g2_kill - the wings struck down: both halves burst.
g2_kill:	ldx	#0
.loop:		lda	e_state, x
		beq	.next
		cmp	#ES_DYING
		beq	.next
		lda	e_kind, x
		cmp	#EK_G2
		beq	.kill
		cmp	#EK_G2W
		bne	.next
.kill:		phx
		jsr	kill_enemy
		plx
.next:		inx
		cpx	#NUM_BIG
		bne	.loop
		rts
