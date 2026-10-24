; ***************************************************************************
;
; Rastan - the round 2 boss, the caped knight, and its orbs (approximate).
;
; Measured in the arcade (sim/scripts/boss2*.txt: started in round 2's boss
; room; the knight is arcade slot 17, type $13, created by $04449E): it comes
; into the room's door (x 256 of the room, anchor y 408) and stands there 56
; frames, drops to the floor (y 472) and jumps at Rastan (up 86 px, 2 px a
; frame toward him), lands (8 frames), and jumps up or down to his level
; (its anchor 17 px below his). Then, over and over: it walks at him (8 px a
; 9-frame step); within 52 px it swings (anims 214, 220-223: 19 frames; its
; sword, box $93: x 32 .. 48, y -28 .. -20, is out in 223: a type 3 hit, 12
; units and knocked back; crouching ducks it), then hops back (2 px a frame
; away, up 78 px, 35 frames), lands, and walks away two steps before turning
; on him again. Far from him (over about 100 px) it rises 96 px (anims
; 210-213, 63 frames) and comes down at him (206-209, gathering speed to
; 3 px a frame). Touching it is a type 3 hit. Ten of the sword's hits kill it
; (a blow in the air counts 3; untouchable 16 frames after each): anims
; 157-160, 15000 points, and the round is clear.
;
; Its orbs: every 300 frames (the first 206 frames after it comes), three fall
; from the brazier nearest Rastan (room x 100, 188 or 412; y 312): straight
; down at 2 px a frame, and 1/2 px a frame to either side at 1.5 down, through
; everything, to the bottom of the room. Touching one is a type 3 hit.
;
; The body (13 pieces, EK_BOSS) thinks; the rest of the pieces follow it
; (EK_BOSS2), as round 1's boss's do. The second part's spare fields hold the
; body's vertical speed: e_timer + 1 / e_sub + 1 (8.8 px a frame), e_range + 1
; the fraction of y, e_alt + 1 the gravity, e_dmg + 1 the speed across.
;
; ***************************************************************************

KN_ROOM		=	11264		; The boss room's left (map segment $2D).
KN_DOOR_X	=	KN_ROOM + 256
KN_DOOR_Y	=	408
KN_UP		=	408		; Its two levels: Rastan on a ledge (the
KN_FLOOR	=	472		; arcade's own heights, not the map's), or on the floor.
KN_COME		=	KN_ROOM + 16	; Rastan past this: it comes.
KN_REACH	=	52		; Swings within this,
KN_FAR		=	128		; floats at him beyond this (the arcade walked at 120).
KN_HITS		=	10
KN_INVULN	=	16
KN_ORB_FIRST	=	208		; (counted from its first frame: 206 in the arcade)
KN_ORB_EVERY	=	300
KN_ORB_Y	=	312
KN_ORB_END	=	506
KN_ROW		=	16		; weapon_hit's row for its sword.

KS_DOOR		=	0		; e_alt
KS_AIR		=	1
KS_LAND		=	2
KS_WALK		=	3
KS_SWING	=	4
KS_RISE		=	5

KA_STAND	=	0		; Animation pairs (kn_anim).
KA_AIR		=	1
KA_LAND		=	2
KA_WALK		=	3
KA_SWING	=	4
KA_RISE		=	5
KA_FLOAT	=	6
KA_DEATH	=	7

		.bss
kn_orbt:	ds	2		; Frames to the next orbs.
kn_away:	ds	1		; Steps to walk away from him before turning.
kn_hop:		ds	1		; In the air: 1 a hop back (then away from him).
kn_target:	ds	1		; The level it lands on (low byte: y $1xx).
		.code

; boss_spawn - once, when Rastan enters the room: the knight in the door.
boss_spawn:	lda	boss_done
		bne	.r
		lda	<p_x
		cmp	#<KN_COME
		lda	<p_x + 1
		sbc	#>KN_COME
		bcc	.r
		inc	boss_done
		lda	#^knight_pal		; Its colours: sprite palette 8.
		tam3
		php
		sei
		lda	#<(256 + 8 * 16)
		sta	VCE_CTA + 0
		lda	#>(256 + 8 * 16)
		sta	VCE_CTA + 1
		tia	knight_pal, VCE_CTW, 32
		plp
		ldx	#SPEC_FIRST
		lda	#EK_BOSS
		jsr	.place
		ldx	#SPEC_FIRST + 1
		lda	#EK_BOSS2
		jsr	.place
		ldx	#SPEC_FIRST
		stz	e_alt, x		; KS_DOOR
		stz	e_range, x		; hits
		stz	e_struck, x
		lda	#56
		sta	e_timer, x
		lda	#<KN_ORB_FIRST
		sta	kn_orbt
		lda	#>KN_ORB_FIRST
		sta	kn_orbt + 1
		lda	#KA_STAND
		jmp	kn_anim
.r:		rts
.place:		sta	e_kind, x
		lda	#<KN_DOOR_X
		sta	e_xl, x
		lda	#>KN_DOOR_X
		sta	e_xh, x
		lda	#<KN_DOOR_Y
		sta	e_yl, x
		lda	#>KN_DOOR_Y
		sta	e_yh, x
		stz	e_face, x
		lda	#$FF
		sta	e_shown, x
		lda	#ES_WALK
		sta	e_state, x
		rts

; kn_anim - A = KA_*: both parts' animations (X = the body).
kn_anim:	pha
		jsr	map_kind
		pla
		pha
		tay
		lda	kn_anims_l, y
		pha
		lda	kn_anims_h, y
		tay
		pla
		jsr	enemy_set_anim
		pla
		tay
		inx
		lda	kn2_anims_l, y
		pha
		lda	kn2_anims_h, y
		tay
		pla
		jsr	enemy_set_anim
		dex
		rts
kn_anims_l:	db	<anim_kn_stand, <anim_kn_air, <anim_kn_land, <anim_kn_walk
		db	<anim_kn_swing, <anim_kn_rise, <anim_kn_float, <anim_kn_death
kn_anims_h:	db	>anim_kn_stand, >anim_kn_air, >anim_kn_land, >anim_kn_walk
		db	>anim_kn_swing, >anim_kn_rise, >anim_kn_float, >anim_kn_death
kn2_anims_l:	db	<anim_kn2_stand, <anim_kn2_air, <anim_kn2_land, <anim_kn2_walk
		db	<anim_kn2_swing, <anim_kn2_rise, <anim_kn2_float, <anim_kn2_death
kn2_anims_h:	db	>anim_kn2_stand, >anim_kn2_air, >anim_kn2_land, >anim_kn2_walk
		db	>anim_kn2_swing, >anim_kn2_rise, >anim_kn2_float, >anim_kn2_death

; kn_jump - X = body: into the air with A = speed up (px/frame * 16, 0 for a
; fall), Y = gravity (1/256 px a frame per frame), kn_dx (e_dmg + 1) across.
kn_jump:	stz	e_range + 1, x		; (y fraction)
		pha
		tya
		sta	e_alt + 1, x
		pla
		sta	<ctmp		; vy = -A * 16 (8.8)
		lda	<etmp		; (etmp kept: callers' |dx|)
		pha
		lda	<etmp + 1
		pha
		lda	<ctmp
		sta	<etmp
		stz	<etmp + 1
		asl	<etmp
		rol	<etmp + 1
		asl	<etmp
		rol	<etmp + 1
		asl	<etmp
		rol	<etmp + 1
		asl	<etmp
		rol	<etmp + 1
		cla
		sec
		sbc	<etmp
		sta	e_sub + 1, x
		cla
		sbc	<etmp + 1
		sta	e_timer + 1, x
		pla
		sta	<etmp + 1
		pla
		sta	<etmp
		lda	#KS_AIR
		sta	e_alt, x
		rts

; ---------------------------------------------------------------------------
; boss_think - X = the body.

boss_think:	lda	e_state, x
		cmp	#ES_DYING
		bne	.alive
		lda	e_animend, x		; Dying: when its fall ends, both go.
		beq	.r
		stz	e_state, x
		stz	e_state + 1, x
		lda	#BOSS_CLEAR
		sta	boss_clear
.r:		rts
.alive:		jsr	kn_orbs
		lda	e_alt, x
		beq	.door
		jsr	touch_hurts
		lda	e_struck, x		; Untouchable for a while after a hit.
		beq	.vuln
		dec	e_struck, x
		bra	.act
.vuln:		jsr	sword_vs_enemy
		bcc	.act
		lda	#KN_INVULN
		sta	e_struck, x
		jsr	weapon_power
		clc
		adc	e_range, x
		sta	e_range, x
		cmp	#KN_HITS
		bcs	.dead
		phx
		lda	#SFX_HIT
		jsr	sound_sfx
		plx
		bra	.act
.dead:		lda	#ES_DYING
		sta	e_state, x
		sta	e_state + 1, x
		lda	#$50			; 15000: 150 hundreds (BCD).
		jsr	score_add
		lda	#$99
		jsr	score_add
		lda	#$01
		jsr	score_add
		lda	#KA_DEATH
		jmp	kn_anim

.door:		dec	e_timer, x		; In the door, then off it.
		beq	!+
		rts
!:
		stz	kn_hop			; Off the door: a fall to the floor.
		lda	#<KN_FLOOR
		sta	kn_target
		stz	e_dmg + 1, x
		cla
		ldy	#42
		jsr	kn_jump
		lda	#KA_AIR
		jmp	kn_anim

.act:		lda	e_alt, x
		cmp	#KS_AIR
		bne	!+
		jmp	kn_air
!:		cmp	#KS_LAND
		bne	!+
		dec	e_timer, x
		bne	.rts
		jmp	kn_towalk
!:		cmp	#KS_SWING
		bne	!+
		jmp	kn_swing
!:		cmp	#KS_RISE
		bne	kn_walk
		jmp	kn_rise
.rts:		rts

; kn_walk - X = body: at him, a step at a time; swing near, float when far,
; jump to his level.
kn_walk:	jsr	boss_dist		; etmp = |dx|
		jsr	kn_level
		cmp	e_yl, x
		bne	.level
		lda	<etmp + 1
		bne	.far
		lda	<etmp
		cmp	#KN_FAR
		bcs	.far
		lda	kn_away			; Walking away still?
		bne	.step
		jsr	face_player
		lda	<etmp
		cmp	#KN_REACH + 1
		bcs	.step
		lda	#KS_SWING		; Swing.
		sta	e_alt, x
		lda	#19
		sta	e_timer, x
		stz	e_struck + 1, x
		lda	#KA_SWING
		jmp	kn_anim
.step:		inc	e_sub, x		; 8 px every 9 frames.
		lda	e_sub, x
		cmp	#9
		bcc	!+
		stz	e_sub, x
		lda	kn_away
		beq	!+
		dec	kn_away
		bne	!+
		jsr	face_player
!:		lda	e_sub, x
		beq	.r
		lda	e_face, x
		bne	!+
		lda	#$FF
!:		jsr	add_x
		jmp	kn_clamp
.r:		rts
.far:		jsr	kn_level		; Float at him.
		sta	kn_target
		jsr	face_player
		lda	#KS_RISE
		sta	e_alt, x
		lda	#63
		sta	e_timer, x
		lda	#KA_RISE
		jmp	kn_anim
.level:		sta	kn_target		; A hop to his level, at him.
		jsr	face_player
		stz	kn_hop
		lda	#2
		jsr	kn_toward
		lda	#125			; Up 86 px: 7.8 px a frame, 0.355.
		ldy	#91
		jsr	kn_jump
		lda	#KA_AIR
		jmp	kn_anim

; kn_toward - e_dmg + 1 = A px a frame toward Rastan (0 when within 16 px).
kn_toward:	ldy	<etmp + 1
		bne	!+
		ldy	<etmp
		cpy	#16
		bcs	!+
		cla
!:		ldy	e_face, x
		bne	!+
		eor	#$FF
		inc	a
!:		sta	e_dmg + 1, x
		rts

kn_towalk:	lda	#KS_WALK
		sta	e_alt, x
		stz	e_sub, x
		lda	#KA_WALK
		jmp	kn_anim

; kn_swing - X = body: the sword is out in the swing's last pose.
kn_swing:	lda	e_pose, x
		cmp	#POSE_KN_OUT
		bne	.next
		lda	e_struck + 1, x
		bne	.next
		ldy	#KN_ROW
		jsr	weapon_hit
		bcc	.next
		inc	e_struck + 1, x
		phx
		lda	e_face, x
		bne	!+
		lda	#$FF
!:		ldy	#HIT_DAMAGE
		jsr	player_hit
		plx
.next:		dec	e_timer, x
		bne	.r
		lda	#1			; Hop back: away 2 px a frame, up 78 px.
		sta	kn_hop
		lda	e_yl, x
		sta	kn_target
		lda	e_face, x		; (A wall within 80 px behind it: over
		eor	#1			; him instead.)
		jsr	kn_room
		bcs	!+
		lda	e_face, x
		eor	#1
		sta	e_face, x
!:		lda	e_face, x
		bne	!+
		lda	#2
		bra	!++
!:		lda	#$FE
!:		sta	e_dmg + 1, x
		lda	#147			; 9.2 px a frame, 0.54.
		ldy	#138
		jsr	kn_jump
		lda	#KA_AIR
		jmp	kn_anim
.r:		rts

; kn_rise - X = body: rises 96 px (after 17 frames), then comes down at him.
kn_rise:	dec	e_timer, x
		beq	.down
		lda	e_timer, x
		cmp	#46
		beq	.up
		bcs	.r
		jmp	kn_fly
.up:		stz	e_dmg + 1, x
		lda	#67			; 4.2 px a frame, 0.09.
		ldy	#23
		jsr	kn_jump
		lda	#KS_RISE		; (still rising)
		sta	e_alt, x
		jmp	kn_fly
.down:		stz	kn_hop
		lda	#KS_AIR			; Down at him, 1/8 px a frame faster.
		sta	e_alt, x
		lda	#31
		sta	e_alt + 1, x
		lda	#KA_FLOAT
		jmp	kn_anim
.r:		rts

; kn_air - X = body: flying; land on a floor coming down.
kn_air:		lda	e_alt + 1, x		; (the float: gathering speed at him)
		cmp	#31
		bne	!+
		jsr	boss_dist
		jsr	face_player
		lda	<etmp + 1		; (stops 32 px from him)
		bne	.go
		lda	<etmp
		cmp	#32
		bcs	.go
		stz	e_dmg + 1, x
		bra	!+
.go:		lda	#3
		jsr	kn_toward
!:		jsr	kn_fly
		lda	e_timer + 1, x		; Coming down, at its level?
		bmi	.r
		lda	e_yh, x
		cmp	#1
		bcc	.r
		bne	!+
		lda	e_yl, x
		cmp	kn_target
		bcc	.r
!:		lda	kn_target		; Landed.
		sta	e_yl, x
		lda	#1
		sta	e_yh, x
		lda	#KS_LAND
		sta	e_alt, x
		lda	#8
		sta	e_timer, x
		lda	kn_hop			; After a hop back: two steps away first
		cmp	#1			; (if the room goes on that way).
		bne	!+
		lda	e_face, x
		eor	#1
		jsr	kn_room
		bcc	!+
		lda	#3
		sta	kn_away
		lda	e_face, x
		eor	#1
		sta	e_face, x
!:		lda	#KA_LAND
		jmp	kn_anim
.r:		rts

; kn_fly - X = body: x += e_dmg + 1, y += vy (8.8), vy += gravity.
kn_fly:		lda	e_dmg + 1, x
		jsr	add_x
		jsr	kn_clamp
		lda	e_range + 1, x
		clc
		adc	e_sub + 1, x
		sta	e_range + 1, x
		lda	e_timer + 1, x
		adc	#0
		jsr	add_y
		lda	e_sub + 1, x
		clc
		adc	e_alt + 1, x
		sta	e_sub + 1, x
		bcc	!+
		inc	e_timer + 1, x
!:		rts

; kn_room - A = a direction (0 left, 1 right): carry set if the room goes on
; at least 80 px that way from X (inside its walls, x 32 .. 480).
kn_room:	cmp	#0
		bne	.right
		lda	e_xl, x			; x - 80 >= room + 32?
		sec
		sbc	#<(KN_ROOM + 32 + 80)
		lda	e_xh, x
		sbc	#>(KN_ROOM + 32 + 80)
		rts
.right:		lda	#<(KN_ROOM + 480 - 80)	; x + 80 <= room + 480?
		cmp	e_xl, x
		lda	#>(KN_ROOM + 480 - 80)
		sbc	e_xh, x
		rts

; kn_level - A = (the low byte of) the level for Rastan's: KN_UP when he stands
; above y 423 (its anchor 17 below his), else KN_FLOOR; in the air or on a
; rope, its own.
kn_level:	lda	<p_state
		cmp	#ST_AIR
		beq	.own
		cmp	#ST_CLIMB
		beq	.own
		lda	<p_y
		cmp	#<(KN_UP - 17 + 32)
		lda	<p_y + 1
		sbc	#>(KN_UP - 17 + 32)
		bcs	.floor
		lda	#<KN_UP
		rts
.floor:		lda	#<KN_FLOOR
		rts
.own:		lda	e_yl, x
		rts

; kn_clamp - keep it in the room (x 32 .. 480 of it: inside its walls).
kn_clamp:	lda	e_xl, x
		cmp	#<(KN_ROOM + 32)
		lda	e_xh, x
		sbc	#>(KN_ROOM + 32)
		bcs	!+
		lda	#<(KN_ROOM + 32)
		sta	e_xl, x
		lda	#>(KN_ROOM + 32)
		sta	e_xh, x
!:		lda	#<(KN_ROOM + 480)
		cmp	e_xl, x
		lda	#>(KN_ROOM + 480)
		sbc	e_xh, x
		bcs	!+
		lda	#<(KN_ROOM + 480)
		sta	e_xl, x
		lda	#>(KN_ROOM + 480)
		sta	e_xh, x
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
; kn_orbs - X = body: its clock; three orbs at the brazier nearest Rastan.

kn_orbs:	lda	kn_orbt
		bne	!+
		dec	kn_orbt + 1
!:		dec	kn_orbt
		lda	kn_orbt
		ora	kn_orbt + 1
		bne	.r
		lda	#<KN_ORB_EVERY
		sta	kn_orbt
		lda	#>KN_ORB_EVERY
		sta	kn_orbt + 1
		cly				; The brazier nearest him: room x
		lda	<p_x			; < 144: the first, < 300: the second.
		sec
		sbc	#<KN_ROOM
		sta	<ex
		lda	<p_x + 1
		sbc	#>KN_ROOM
		bmi	.pick
		bne	.hi
		lda	<ex
		cmp	#144
		bcc	.pick
		iny
		bra	.pick
.hi:		iny
		lda	<ex
		cmp	#300 - 256
		bcc	.pick
		iny
.pick:		sty	<ex + 1
		stz	<etmp + 1		; Orb number.
.next:		ldy	#NUM_OBJ - 1		; Free projectile slot?
!:		lda	e_state, y
		beq	.slot
		dey
		cpy	#NUM_BIG
		bcs	!-
.r:		rts
.slot:		phx
		ldx	<ex + 1
		lda	kn_orb_x, x
		clc
		adc	#<KN_ROOM
		sta	e_xl, y
		lda	#>KN_ROOM
		adc	kn_orb_xh, x
		sta	e_xh, y
		lda	#<KN_ORB_Y
		sta	e_yl, y
		lda	#>KN_ORB_Y
		sta	e_yh, y
		lda	<etmp + 1
		sta	e_alt, y
		lda	#EK_FRAG
		sta	e_kind, y
		lda	#$FF
		sta	e_shown, y
		cla
		sta	e_face, y
		sta	e_sub, y
		tya
		tax
		jsr	map_kind
		jsr	start_walk		; (anim_orb, looping)
		plx
		jsr	map_kind		; (the body's group again)
		inc	<etmp + 1
		lda	<etmp + 1
		cmp	#3
		bcc	.next
		rts
kn_orb_x:	db	100, 188, 412 & $FF
kn_orb_xh:	db	0, 0, 1

; frag_think - X = an orb: falling (1/2 px a frame across, 1.5 down; or 2 down).
frag_think:	jsr	touch_hurts
		inc	e_sub, x
		lda	e_alt, x
		cmp	#1
		beq	.mid
		lda	e_sub, x		; Sides: 1/2 across, 3/2 down.
		and	#1
		beq	!+
		lda	e_alt, x		; (0 left, 2 right)
		dec	a
!:		jsr	add_x
		lda	e_sub, x
		and	#1
		inc	a
		bra	.down
.mid:		lda	#2
.down:		jsr	add_y
		lda	e_yl, x
		cmp	#<KN_ORB_END
		lda	e_yh, x
		sbc	#>KN_ORB_END
		bcc	!+
		stz	e_state, x
!:		rts
