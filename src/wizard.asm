; ***************************************************************************
;
; Rastan - the round 3 boss, the wizard, and its fire (approximate).
;
; Measured in the arcade (sim/scripts/boss3.txt: started in round 3's boss
; room, Rastan passive; boss3_kill.txt: Rastan coming at it; the wizard is
; arcade slot 17, type $14, its code around $04D650 with its state in
; $10CF10-$10CF46): it appears at x 256 of the room (y 384) and stands 57
; frames, drops to the floor (y 448), then walks at Rastan 8 px a 9-frame step
; (anims 41-44), stopping 72 px from him (88-97 when he has his back to a
; wall; it backs off when he comes nearer: the port, below 64). It casts (anims 37-40, 4 frames each) 309 frames after it lands,
; then 137, 257, 257, 137, ... frames apart: 17 frames into the cast a fan of
; five fireballs leaves its hand toward Rastan, 2 px a frame, straight ahead,
; at 27, 45, 63 degrees up and straight up (slots 18-22, anims 237-239),
; through everything. When Rastan swings at it from near, it turns
; intangible and flickers, still, for about 133 frames, and may then appear
; elsewhere in the room.
;
; Not found: what lets Rastan's sword hurt it (no capture of a hit; its ten
; hit points, ($3A,A4), never changed). The port: the sword hurts it while it
; is solid; a hit makes it flicker (intangible, still) for 133 frames, then
; it appears 192 px the other side of Rastan (in the room) and casts at
; once. Ten of the sword's hits kill it (a blow in the air counts 3): the
; walkers' burst, 20000 points (not measured), and the round is clear.
;
; The body (13 pieces, EK_WIZ) thinks; the rest follow it (EK_WIZ2, the
; knight's kn2_think). Its colours: sprite palette 8 (the wizard) and 13 (its
; fire), loaded when it comes (wizard_pal, FIXED_PALS in object_specs.py).
;
; ***************************************************************************

WZ_ROOM		=	11264		; The boss room's left (map segment $44).
WZ_IN_X		=	WZ_ROOM + 256
WZ_IN_Y		=	384
WZ_FLOOR	=	448
WZ_NEAR		=	64		; Keeps between these from Rastan.
WZ_FAR		=	72
WZ_HITS		=	10
WZ_GONE		=	133		; Frames intangible after a hit.
WZ_CAST_FIRST	=	309		; (frames after landing)
WZ_FIRE_AT	=	17		; The fan leaves this far into the cast.
WZ_HIDE_Y	=	192		; (where it flickers to: above the view)

WS_IN		=	0		; e_alt
WS_DROP		=	1
WS_WALK		=	2
WS_CAST		=	3
WS_GONE		=	4

WA_STAND	=	0		; Animation pairs (wz_anim).
WA_WALK		=	1
WA_CAST		=	2
WA_DEATH	=	3

		.bss
wz_castt:	ds	2		; Frames to the next cast.
wz_casti:	ds	1		; Its place in the cycle of gaps.
wz_hits:	ds	1
		.code

; wz_spawn - once, when Rastan is in the room: the wizard where it appears.
wz_spawn:	lda	boss_done
		bne	.r
		lda	<p_x
		cmp	#<(WZ_ROOM + 16)
		lda	<p_x + 1
		sbc	#>(WZ_ROOM + 16)
		bcc	.r
		inc	boss_done
		lda	#^wizard_pal		; Its colours: sprite palettes 8 and 13.
		tam3
		php
		sei
		lda	#<(256 + 8 * 16)
		sta	VCE_CTA + 0
		lda	#>(256 + 8 * 16)
		sta	VCE_CTA + 1
		tia	wizard_pal, VCE_CTW, 32
		lda	#<(256 + 13 * 16)
		sta	VCE_CTA + 0
		lda	#>(256 + 13 * 16)
		sta	VCE_CTA + 1
		tia	wizard_pal13, VCE_CTW, 32
		plp
		ldx	#SPEC_FIRST
		lda	#EK_WIZ
		jsr	.place
		ldx	#SPEC_FIRST + 1
		lda	#EK_WIZ2
		jsr	.place
		ldx	#SPEC_FIRST
		stz	e_alt, x		; WS_IN
		stz	wz_hits
		stz	wz_casti
		lda	#57
		sta	e_timer, x
		lda	#WA_STAND
		jmp	wz_anim
.r:		rts
.place:		sta	e_kind, x
		lda	#<WZ_IN_X
		sta	e_xl, x
		lda	#>WZ_IN_X
		sta	e_xh, x
		lda	#<WZ_IN_Y
		sta	e_yl, x
		lda	#>WZ_IN_Y
		sta	e_yh, x
		stz	e_face, x
		lda	#$FF
		sta	e_shown, x
		lda	#ES_WALK
		sta	e_state, x
		rts

; wz_anim - A = WA_*: both parts' animations (X = the body).
wz_anim:	pha
		jsr	map_kind
		pla
		pha
		tay
		lda	wz_anims_l, y
		pha
		lda	wz_anims_h, y
		tay
		pla
		jsr	enemy_set_anim
		pla
		tay
		inx
		lda	wz2_anims_l, y
		pha
		lda	wz2_anims_h, y
		tay
		pla
		jsr	enemy_set_anim
		dex
		rts
wz_anims_l:	db	<anim_wz_stand, <anim_wz_walk, <anim_wz_cast, <anim_wz_death
wz_anims_h:	db	>anim_wz_stand, >anim_wz_walk, >anim_wz_cast, >anim_wz_death
wz2_anims_l:	db	<anim_wz2_stand, <anim_wz2_walk, <anim_wz2_cast, <anim_wz2_death
wz2_anims_h:	db	>anim_wz2_stand, >anim_wz2_walk, >anim_wz2_cast, >anim_wz2_death

; Gaps between casts, in turn (boss3.txt: 137, 257, 257, 137, ...).
wz_gap_l:	db	<137, <257, <257, <137
wz_gap_h:	db	>137, >257, >257, >137

; ---------------------------------------------------------------------------
; wz_think - X = the body.

wz_think:	lda	e_state, x
		cmp	#ES_DYING
		bne	.alive
		lda	e_animend, x		; Dying: when the burst ends, both go.
		beq	.r
		stz	e_state, x
		stz	e_state + 1, x
		lda	#BOSS_CLEAR
		sta	boss_clear
.r:		rts
.alive:		lda	e_alt, x
		cmp	#WS_IN
		bne	!+
		dec	e_timer, x		; Standing where it appeared, then down.
		bne	.r
		lda	#WS_DROP
		sta	e_alt, x
		lda	#WA_WALK
		jmp	wz_anim
!:		cmp	#WS_DROP
		bne	!+
		lda	#2			; Down to the floor (2 px a frame).
		jsr	add_y
		lda	e_yl, x
		cmp	#<WZ_FLOOR
		lda	e_yh, x
		sbc	#>WZ_FLOOR
		bcc	.r
		lda	#<WZ_FLOOR
		sta	e_yl, x
		lda	#>WZ_FLOOR
		sta	e_yh, x
		lda	#<WZ_CAST_FIRST
		sta	wz_castt
		lda	#>WZ_CAST_FIRST
		sta	wz_castt + 1
		lda	#WS_WALK
		sta	e_alt, x
		rts
!:		cmp	#WS_GONE
		bne	.solid
		jmp	wz_gone

.solid:		jsr	sword_vs_enemy		; Solid: the sword hurts it.
		bcc	.act
		jsr	weapon_power
		clc
		adc	wz_hits
		sta	wz_hits
		cmp	#WZ_HITS
		bcs	.dead
		phx
		lda	#SFX_HIT
		jsr	sound_sfx
		plx
		lda	#WS_GONE		; Gone for a while.
		sta	e_alt, x
		lda	#WZ_GONE
		sta	e_timer, x
		rts
.dead:		lda	#ES_DYING
		sta	e_state, x
		sta	e_state + 1, x
		lda	#$99			; 20000: 200 hundreds (BCD).
		jsr	score_add
		lda	#$99
		jsr	score_add
		lda	#$02
		jsr	score_add
		lda	#WA_DEATH
		jmp	wz_anim

.act:		lda	wz_castt		; Its clock, from cast to cast.
		bne	!+
		dec	wz_castt + 1
!:		dec	wz_castt
		lda	e_alt, x
		cmp	#WS_CAST
		beq	wz_cast
		lda	wz_castt
		ora	wz_castt + 1
		bne	wz_walk
wz_start_cast:	lda	#WS_CAST
		sta	e_alt, x
		stz	e_timer, x
		jsr	face_player
		ldy	wz_casti		; The next gap.
		lda	wz_gap_l, y
		sta	wz_castt
		lda	wz_gap_h, y
		sta	wz_castt + 1
		iny
		tya
		and	#3
		sta	wz_casti
		lda	#WA_CAST
		jmp	wz_anim

; wz_cast - X = body: the fan 17 frames in, walking again at its end.
wz_cast:	inc	e_timer, x
		lda	e_timer, x
		cmp	#WZ_FIRE_AT
		bne	!+
		jsr	wz_fan
		lda	#WS_WALK
		sta	e_alt, x
		lda	#WA_WALK
		jmp	wz_anim
!:		rts

; wz_walk - X = body: 8 px every 9 frames toward Rastan, or away from him
; when he is nearer than WZ_NEAR; still between WZ_NEAR and WZ_FAR.
wz_walk:	jsr	face_player
		jsr	kn_dist			; etmp = |dx| (src/knight.asm)
		inc	e_sub, x
		lda	e_sub, x
		cmp	#9
		bcc	.r
		stz	e_sub, x
		lda	<etmp + 1
		bne	.toward
		lda	<etmp
		cmp	#WZ_FAR + 1
		bcs	.toward
		cmp	#WZ_NEAR
		bcs	.r
		lda	e_face, x		; Away.
		eor	#1
		bra	.step
.toward:	lda	e_face, x
.step:		tay
		lda	#8
		cpy	#0
		bne	!+
		lda	#-8
!:		jsr	add_x
		jmp	wz_clamp
.r:		rts

; wz_clamp - X = body: inside the room (x 32 .. 480).
wz_clamp:	lda	e_xl, x
		cmp	#<(WZ_ROOM + 32)
		lda	e_xh, x
		sbc	#>(WZ_ROOM + 32)
		bcs	!+
		lda	#<(WZ_ROOM + 32)
		sta	e_xl, x
		lda	#>(WZ_ROOM + 32)
		sta	e_xh, x
		rts
!:		lda	#<(WZ_ROOM + 480)
		cmp	e_xl, x
		lda	#>(WZ_ROOM + 480)
		sbc	e_xh, x
		bcs	!+
		lda	#<(WZ_ROOM + 480)
		sta	e_xl, x
		lda	#>(WZ_ROOM + 480)
		sta	e_xh, x
!:		rts

; wz_gone - X = body: intangible, flickering (every other frame above the
; view); then 192 px the other side of Rastan, casting at once.
wz_gone:	lda	e_timer, x
		and	#1
		beq	.floor
		lda	#<WZ_HIDE_Y
		sta	e_yl, x
		lda	#>WZ_HIDE_Y
		bra	.y
.floor:		lda	#<WZ_FLOOR
		sta	e_yl, x
		lda	#>WZ_FLOOR
.y:		sta	e_yh, x
		dec	e_timer, x
		bne	.r
		lda	#<WZ_FLOOR		; Back: elsewhere.
		sta	e_yl, x
		lda	#>WZ_FLOOR
		sta	e_yh, x
		lda	<p_x			; The other side of him: room x < 256,
		sec				; to his right; else to his left.
		sbc	#<WZ_ROOM
		lda	<p_x + 1
		sbc	#>WZ_ROOM
		beq	.right
		lda	#-192
		ldy	#$FF
		bra	.place
.right:		lda	#192
		cly
.place:		clc
		adc	<p_x
		sta	e_xl, x
		tya
		adc	<p_x + 1
		sta	e_xh, x
		jsr	wz_clamp
		jmp	wz_start_cast
.r:		rts

; ---------------------------------------------------------------------------
; wz_fan - X = body: five fireballs from its hand, toward Rastan.

wz_fan:		stz	<etmp + 1		; Fireball number (its direction).
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
		phy
		ldy	<etmp + 1		; x = body x -/+ its offset (facing).
		lda	wf_x0, y
		ply
		sta	<ex
		lda	e_face, x
		bne	.right
		lda	e_xl, x
		sec
		sbc	<ex
		sta	e_xl, y
		lda	e_xh, x
		sbc	#0
		bra	.x
.right:		lda	e_xl, x
		clc
		adc	<ex
		sta	e_xl, y
		lda	e_xh, x
		adc	#0
.x:		sta	e_xh, y
		phy
		ldy	<etmp + 1
		lda	wf_y0, y
		ply
		sta	<ex
		lda	e_yl, x
		sec
		sbc	<ex
		sta	e_yl, y
		lda	e_yh, x
		sbc	#0
		sta	e_yh, y
		lda	#EK_WFIRE
		sta	e_kind, y
		lda	#$FF
		sta	e_shown, y
		cla
		sta	e_sub, y
		tya
		tax
		jsr	map_kind
		jsr	start_walk		; (anim_wfire, looping)
		plx
		jsr	map_kind		; (the body's group again)
		inc	<etmp + 1
		lda	<etmp + 1
		cmp	#5
		bcs	!+
		jmp	.next
!:		rts
; Where each leaves from (px ahead of and above the anchor), and its steps:
; across (px on even, odd frames), up (the same).
wf_x0:		db	36, 36, 35, 30, 16
wf_y0:		db	0, 14, 27, 40, 44
wf_dx0:		db	2, 2, 1, 1, 0
wf_dx1:		db	2, 2, 2, 1, 0
wf_dy0:		db	0, 1, 1, 2, 2
wf_dy1:		db	0, 1, 2, 2, 2

; wf_think - X = a fireball: on its line until it leaves the room.
wf_think:	jsr	touch_hurts
		inc	e_sub, x
		ldy	e_alt, x
		lda	e_sub, x
		lsr	a
		bcs	.odd
		lda	wf_dx0, y
		sta	<ex
		lda	wf_dy0, y
		bra	.move
.odd:		lda	wf_dx1, y
		sta	<ex
		lda	wf_dy1, y
.move:		eor	#$FF			; Up.
		inc	a
		jsr	add_y
		lda	<ex
		ldy	e_face, x
		bne	!+
		eor	#$FF
		inc	a
!:		jsr	add_x
		lda	e_yh, x			; Gone above y 256, or out of the room.
		cmp	#>256
		bcc	.gone
		lda	e_xl, x
		cmp	#<(WZ_ROOM + 8)
		lda	e_xh, x
		sbc	#>(WZ_ROOM + 8)
		bcc	.gone
		lda	#<(WZ_ROOM + 504)
		cmp	e_xl, x
		lda	#>(WZ_ROOM + 504)
		sbc	e_xh, x
		bcs	.r
.gone:		stz	e_state, x
.r:		rts
