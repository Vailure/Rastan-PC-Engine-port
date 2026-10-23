; ***************************************************************************
;
; Rastan - the round 1 boss (approximate).
;
; Measured in the arcade (sim/scripts/boss.txt, round 1 census): when Rastan
; enters the last room the boss drops in at x 11440 and lands (anchor y 446).
; It walks at him (anims 0-3, 16 frames a step, about 0.9 px/frame), leaps
; when he is far (37 frames, about 74 px), and alternates two attacks: fire
; (72 frames; five fragments form at the top of the screen, 70-86 px in front
; of it, and 30 frames in rain down at him in a fan: 0.5-2 px/frame across,
; 2-0.5 down) and a staff swing (49 frames, reaching about 80 px in front).
; Ten sword hits kill it (about 20 frames apart at least: it is untouchable
; meanwhile), for 5000 points; the round is clear a few seconds later.
;
; The arcade draws it with up to 18 sprites; the port uses two objects, the
; first 13 pieces (EK_BOSS, which thinks) and the rest (EK_BOSS2, which follows).
;
; ***************************************************************************

BOSS_X		=	11440
BOSS_Y0		=	384		; Drops in from here,
BOSS_FLOOR	=	446		; and lands here.
BOSS_ROOM	=	11300		; Rastan past this: the boss comes.
BOSS_LEFT	=	11300		; Its range in the room.
BOSS_RIGHT	=	11740
BOSS_HITS	=	10
BOSS_INVULN	=	20
BOSS_WALK	=	64
BOSS_LEAP	=	37
BOSS_FAR	=	112		; Leaps when Rastan is farther than this.
BOSS_STAFF_RANGE =	80
BOSS_CLEAR	=	240		; Frames from its death to the round clear.
FRAG_FORM	=	30
FRAG_ABOVE	=	178		; Fragments form this far above its anchor.

BS_FALL		=	0		; e_alt
BS_WALK		=	1
BS_RAIN		=	2
BS_STAFF	=	3
BS_LEAP		=	4

BA_WALK		=	0		; Animation pairs (boss_anim).
BA_RAIN		=	1
BA_STAFF	=	2
BA_LEAP		=	3
BA_DEATH	=	4

; boss_spawn - once, when Rastan enters the room: body in slot SPEC_FIRST, the
; rest in the next.
boss_spawn:	lda	boss_done
		bne	.r
		lda	<p_x
		cmp	#<BOSS_ROOM
		lda	<p_x + 1
		sbc	#>BOSS_ROOM
		bcc	.r
		inc	boss_done
		ldx	#SPEC_FIRST
		lda	#EK_BOSS
		jsr	.place
		ldx	#SPEC_FIRST + 1
		lda	#EK_BOSS2
		jsr	.place
		ldx	#SPEC_FIRST
		stz	e_alt, x		; BS_FALL
		stz	e_range, x		; hits
		stz	e_struck, x
		lda	#BA_WALK
		jmp	boss_anim
.r:		rts
.place:		sta	e_kind, x
		lda	#<BOSS_X
		sta	e_xl, x
		lda	#>BOSS_X
		sta	e_xh, x
		lda	#<BOSS_Y0
		sta	e_yl, x
		lda	#>BOSS_Y0
		sta	e_yh, x
		stz	e_face, x
		lda	#$FF
		sta	e_shown, x
		lda	#ES_WALK
		sta	e_state, x
		rts

; boss_anim - A = BA_*: both parts' animations (X = the body, slot SPEC_FIRST).
boss_anim:	pha
		jsr	map_kind		; (uses Y)
		pla
		pha
		tay
		lda	boss_anims_l, y
		pha
		lda	boss_anims_h, y
		tay
		pla
		jsr	enemy_set_anim
		pla
		tay
		inx
		lda	boss2_anims_l, y
		pha
		lda	boss2_anims_h, y
		tay
		pla
		jsr	enemy_set_anim
		dex
		rts

boss_anims_l:	db	<anim_boss_walk, <anim_boss_rain, <anim_boss_staff, <anim_boss_leap, <anim_boss_death
boss_anims_h:	db	>anim_boss_walk, >anim_boss_rain, >anim_boss_staff, >anim_boss_leap, >anim_boss_death
boss2_anims_l:	db	<anim_boss2_walk, <anim_boss2_rain, <anim_boss2_staff, <anim_boss2_leap, <anim_boss2_death
boss2_anims_h:	db	>anim_boss2_walk, >anim_boss2_rain, >anim_boss2_staff, >anim_boss2_leap, >anim_boss2_death

; boss_set - A = BS_*, Y = its animation and timer: start that state.
boss_set:	sta	e_alt, x
		lda	boss_time, y
		sta	e_timer, x
		tya
		jmp	boss_anim
boss_time:	db	BOSS_WALK, 72, 49, BOSS_LEAP

; ---------------------------------------------------------------------------
; boss_think - X = the body.

boss_think:	lda	e_state, x
		cmp	#ES_DYING
		bne	.alive
		lda	e_animend, x		; Dying: when the explosion ends, both go.
		beq	.r
		stz	e_state, x
		stz	e_state + 1, x
		lda	#BOSS_CLEAR
		sta	boss_clear
.r:		rts
.alive:		lda	e_alt, x
		cmp	#BS_FALL
		bne	!+
		jmp	.fall
!:		jsr	touch_hurts
		lda	e_struck, x		; Untouchable for a while after a hit.
		beq	.vuln
		dec	e_struck, x
		bra	.act
.vuln:		jsr	sword_vs_enemy
		bcc	.act
		lda	#BOSS_INVULN
		sta	e_struck, x
		inc	e_range, x
		lda	e_range, x
		cmp	#BOSS_HITS
		bcc	.act
		lda	#ES_DYING		; Ten hits: dead.
		sta	e_state, x
		sta	e_state + 1, x
		lda	#$50			; 5000 (hundreds, BCD)
		jsr	score_add
		lda	#BA_DEATH
		jmp	boss_anim

.act:		lda	e_alt, x
		cmp	#BS_RAIN
		bne	!+
		jmp	.rain
!:		cmp	#BS_STAFF
		bne	!+
		jmp	.staff
!:		cmp	#BS_LEAP
		bne	.walk
		jmp	.leap

.walk:		jsr	face_player
		jsr	boss_dist		; etmp = |dx|
		lda	<etmp + 1
		bne	.step
		lda	<etmp
		cmp	#40			; Close enough: stand.
		bcc	.timer
.step:		inc	e_sub, x		; 7 px in 8 frames.
		lda	e_sub, x
		and	#7
		beq	.timer
		lda	e_face, x
		bne	!+
		lda	#$FF
!:		jsr	add_x
		jsr	boss_clamp
.timer:		dec	e_timer, x
		bne	.r2
		jsr	boss_dist		; Far: leap at him.
		lda	<etmp + 1
		bne	.toleap
		lda	<etmp
		cmp	#BOSS_FAR
		bcc	!+
.toleap:	lda	#BS_LEAP
		ldy	#BA_LEAP
		jmp	boss_set
!:		lda	e_sub + 1, x		; Otherwise the two attacks in turn
		eor	#1			; (the staff only when he is in reach).
		sta	e_sub + 1, x
		beq	.torain
		lda	<etmp
		cmp	#BOSS_STAFF_RANGE
		bcs	.torain
		lda	#BS_STAFF
		ldy	#BA_STAFF
		jmp	boss_set
.torain:	lda	#BS_RAIN
		ldy	#BA_RAIN
		jsr	boss_set
		jmp	boss_fire
.r2:		rts

.towalk:	lda	#BS_WALK
		ldy	#BA_WALK
		jmp	boss_set

.rain:		dec	e_timer, x
		beq	.towalk
		rts

.staff:		lda	e_timer, x		; The staff is out 18-30 frames in.
		cmp	#49 - 18
		bcs	.st2
		cmp	#49 - 30
		bcc	.st2
		jsr	boss_dist
		lda	<etmp + 1
		bne	.st2
		lda	<etmp
		cmp	#BOSS_STAFF_RANGE
		bcs	.st2
		jsr	player_dist		; (and level with it)
		bcc	.st2
		phx
		lda	e_face, x
		bne	!+
		lda	#$FF
!:		ldy	#HIT_DAMAGE
		jsr	player_hit
		plx
.st2:		dec	e_timer, x
		beq	.towalk
		rts

.leap:		lda	e_face, x		; 2 px/frame at him, up 18 frames then down.
		asl	a
		dec	a			; -1 or 1
		asl	a			; -2 or 2
		jsr	add_x
		jsr	boss_clamp
		lda	e_timer, x
		cmp	#BOSS_LEAP - 18
		lda	#2
		bcc	!+
		lda	#$FE
!:		jsr	add_y
		dec	e_timer, x
		bne	!+
		lda	#<BOSS_FLOOR		; Landed.
		sta	e_yl, x
		lda	#>BOSS_FLOOR
		sta	e_yh, x
		jmp	.towalk
!:		rts

.fall:		lda	#2			; Dropping in.
		jsr	add_y
		lda	e_yl, x
		cmp	#<BOSS_FLOOR
		lda	e_yh, x
		sbc	#>BOSS_FLOOR
		bcc	!+
		lda	#<BOSS_FLOOR
		sta	e_yl, x
		lda	#>BOSS_FLOOR
		sta	e_yh, x
		jmp	.towalk
!:		rts

; boss_dist - etmp = |p_x - e_x| (X = the body).
boss_dist:	lda	<p_x
		sec
		sbc	e_xl, x
		sta	<etmp
		lda	<p_x + 1
		sbc	e_xh, x
		sta	<etmp + 1
		bpl	!+
		lda	<etmp
		eor	#$FF
		clc
		adc	#1
		sta	<etmp
		lda	<etmp + 1
		eor	#$FF
		adc	#0
		sta	<etmp + 1
!:		rts

; boss_clamp - keep it in the room.
boss_clamp:	lda	e_xl, x
		cmp	#<BOSS_LEFT
		lda	e_xh, x
		sbc	#>BOSS_LEFT
		bcs	!+
		lda	#<BOSS_LEFT
		sta	e_xl, x
		lda	#>BOSS_LEFT
		sta	e_xh, x
!:		lda	#<BOSS_RIGHT
		cmp	e_xl, x
		lda	#>BOSS_RIGHT
		sbc	e_xh, x
		bcs	!+
		lda	#<BOSS_RIGHT
		sta	e_xl, x
		lda	#>BOSS_RIGHT
		sta	e_xh, x
!:		rts

; boss2_think - X = the second part: on the body (slot X - 1).
boss2_think:	lda	e_state - 1, x
		bne	!+
		stz	e_state, x
		rts
!:		lda	e_xl - 1, x
		sta	e_xl, x
		lda	e_xh - 1, x
		sta	e_xh, x
		lda	e_yl - 1, x
		sta	e_yl, x
		lda	e_yh - 1, x
		sta	e_yh, x
		lda	e_face - 1, x
		sta	e_face, x
		rts

; ---------------------------------------------------------------------------
; boss_fire - X = the body: five fragments form above, in front of it.

boss_fire:	stz	<etmp + 1		; Fragment number.
.next:		ldy	#NUM_OBJ - 1		; Free projectile slot?
!:		lda	e_state, y
		beq	.slot
		dey
		cpy	#NUM_BIG
		bcs	!-
		rts
.slot:		phx
		lda	<etmp + 1
		sta	e_alt, y
		lda	e_face, x
		sta	e_face, y
		tax				; (X = face, for the offset sign)
		ldx	<etmp + 1
		lda	frag_dx, x
		plx
		pha
		lda	e_face, x
		bne	!+
		pla				; Facing left: in front is -dx.
		eor	#$FF
		inc	a
		pha
!:		pla
		pha
		clc
		adc	e_xl, x
		sta	e_xl, y
		pla
		and	#$80
		beq	!+
		lda	#$FF
!:		adc	e_xh, x
		sta	e_xh, y
		lda	e_yl, x
		sec
		sbc	#FRAG_ABOVE
		sta	e_yl, y
		lda	e_yh, x
		sbc	#0
		sta	e_yh, y
		lda	#EK_FRAG
		sta	e_kind, y
		lda	#$FF
		sta	e_shown, y
		lda	#FRAG_FORM
		sta	e_timer, y
		cla
		sta	e_sub, y
		phx
		tya
		tax
		jsr	map_kind
		jsr	start_walk		; (frag_form, looping)
		plx
		inc	<etmp + 1
		lda	<etmp + 1
		cmp	#5
		bcc	.next
		rts

frag_dx:	db	82, 86, 70, 74, 78
; Per frame, in half pixels: across (toward Rastan) and down.
frag_vx:	db	1, 2, 3, 3, 4
frag_vy:	db	4, 3, 3, 2, 1

; frag_think - X = a fragment: forming, then raining down in the fan.
frag_think:	jsr	sword_vs_enemy		; Knocked away.
		bcs	.gone
		lda	e_timer, x
		beq	.fly
		dec	e_timer, x
		bne	.r
		lda	#<anim_frag_fly
		ldy	#>anim_frag_fly
		jmp	enemy_set_anim
.fly:		inc	e_sub, x
		ldy	e_alt, x
		lda	frag_vx, y		; half pixels: + 1 on odd frames
		jsr	.half
		ldy	e_face, x
		bne	!+
		eor	#$FF
		inc	a
!:		jsr	add_x
		ldy	e_alt, x
		lda	frag_vy, y
		jsr	.half
		jsr	add_y
		lda	e_yl, x			; Below the floor: gone.
		cmp	#<(BOSS_FLOOR + 40)
		lda	e_yh, x
		sbc	#>(BOSS_FLOOR + 40)
		bcs	.gone
		jsr	body_vs_enemy
		bcc	.r
		phx
		lda	e_face, x
		bne	!+
		lda	#$FF
!:		ldy	#HIT_DAMAGE
		jsr	player_hit
		plx
.gone:		stz	e_state, x
.r:		rts
.half:		pha				; A/2, plus the odd half every other frame
		lsr	a
		sta	<ctmp
		pla
		and	#1
		beq	!+
		lda	e_sub, x
		and	#1
!:		clc
		adc	<ctmp
		rts
