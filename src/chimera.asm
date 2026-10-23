; ***************************************************************************
;
; Rastan - chimeras and their fireballs (approximate), round 1 from x 2400.
;
; Measured in the arcade (sim/scripts/chimera.txt, round 1 census): a chimera
; walks left at 1/2 px/frame whatever Rastan does, stops once to breathe fire
; (about 113 frames; fireballs leave its mouth, 24 px ahead and 6 up, 33 and
; 81 frames in), then walks on. Fireballs fly left at 1.75 px/frame (4 and 3
; px every other frame). Touching either hurts like a lizardman's club; one
; sword hit kills a chimera (300 points) and knocks a fireball away.
;
; ***************************************************************************

FIRE_DX		=	24
FIRE_DY		=	6
FIRE_1		=	33		; Frames into the breath.
FIRE_2		=	81

; chim_think - X = chimera, alive (enemy_think handled the sword and dying).
chim_think:	jsr	touch_hurts
		lda	e_state, x
		cmp	#ES_ATTACK
		beq	.breath
		; Walking: 1 px every other frame, to the left.
		inc	e_sub, x
		lda	e_sub, x
		lsr	a
		bcc	!+
		lda	e_xl, x
		bne	.dec
		dec	e_xh, x
.dec:		dec	e_xl, x
!:		lda	e_alt, x		; Breathed already: walk on.
		bne	.r
		dec	e_timer, x
		bne	.r
		inc	e_alt, x
		lda	#ES_ATTACK
		sta	e_state, x
		lda	#<anim_chim_breath
		ldy	#>anim_chim_breath
		jmp	enemy_set_anim

.breath:	inc	e_timer, x
		lda	e_timer, x
		cmp	#FIRE_1
		beq	.fire
		cmp	#FIRE_2
		bne	!+
.fire:		jsr	breathe_fire
!:		lda	e_animend, x
		beq	.r
		lda	#ES_WALK
		sta	e_state, x
		lda	#<anim_chim_walk
		ldy	#>anim_chim_walk
		jmp	enemy_set_anim
.r:		rts

; touch_hurts - X's body touching Rastan's: the effect of its kind's touch
; type (kind_touch, the arcade's: player_touch).
touch_hurts:	ldy	e_kind, x
		lda	kind_touch, y
		beq	.r
		pha
		jsr	body_vs_enemy
		pla
		bcc	.r
		phx
		jsr	player_touch
		plx
.r:		rts

; breathe_fire - X = chimera: a fireball from its mouth.
breathe_fire:	ldy	#NUM_OBJ - 1		; Free projectile slot?
!:		lda	e_state, y
		beq	.slot
		dey
		cpy	#NUM_BIG
		bcs	!-
		rts
.slot:		lda	e_xl, x
		sec
		sbc	#FIRE_DX
		sta	e_xl, y
		lda	e_xh, x
		sbc	#0
		sta	e_xh, y
		lda	e_yl, x
		sec
		sbc	#FIRE_DY
		sta	e_yl, y
		lda	e_yh, x
		sbc	#0
		sta	e_yh, y
		lda	#EK_FIRE
		sta	e_kind, y
		lda	#$FF
		sta	e_shown, y
		cla
		sta	e_face, y
		sta	e_sub, y
		phx
		tya
		tax
		jsr	map_kind
		jsr	start_walk
		plx
		rts

; fire_think - X = fireball.
fire_think:	jsr	sword_vs_enemy		; Knocked away.
		bcs	.gone
		inc	e_sub, x		; 4 and 3 px every other frame.
		lda	e_sub, x
		lsr	a
		bcs	.hit
		and	#1
		eor	#4			; 4, 3, 4, 3 ...
		sbc	#0			; (carry clear: -1 when the bit was set)
		sta	<etmp
		lda	e_xl, x
		sec
		sbc	<etmp
		sta	e_xl, x
		bcs	.hit
		dec	e_xh, x
.hit:		jsr	body_vs_enemy
		bcc	.r
		phx
		lda	#$FF
		ldy	#HIT_DAMAGE
		jsr	player_hit
		plx
.gone:		stz	e_state, x
.r:		rts
