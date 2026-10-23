; ***************************************************************************
;
; Rastan - approximate player (milestone 2).
;
; Movement constants come from the arcade program (see README): walking at
; 1px/frame for 15 frames then 2px/frame, jumps driven by the arcade's own
; (dx, up) tables, falling replays the table backwards. Collision uses the
; arcade's per-tile collision codes for stage 1.
;
; Coordinates are world pixels. p_x/p_y is the arcade's player anchor:
; feet are at p_y + 24, so the floor probe is p_y + 25.
;
; ***************************************************************************

		include	"player.inc"

PLAYER_BANK	=	^player_data
COLL_BANK	=	^collision_data

SPR_BUF_A	=	$5000		; Two pattern buffers, 24 cells each:
SPR_BUF_B	=	$5600		; the pose's (up to 20), then the weapon's (up to 4).
MAX_CELLS	=	24
WEAPON_CELL	=	20		; First weapon cell in a buffer.
WEAPON_BANK	=	^weapon_cells	; Weapon cells (64), 128 bytes each, from $6000.
WTAB_BANK	=	^weapon_vtab	; Weapon piece lists (weapon_tab.inc, pce_player.py).

; Weapons (arcade $10D2FA): the sword, or one taken from an item for 3000
; frames (arcade timer $10D326). The weapon is drawn behind the body from
; the arcade's own weapon frames (see pce_player.py); the morning star
; reaches 32 px further forward, 16 px further up and down.
WPN_SWORD	=	1
WPN_AXE		=	2
WPN_STAR	=	3
WPN_FIRE	=	4
WEAPON_FRAMES	=	3000

; States.
ST_STAND	=	0
ST_WALK		=	1
ST_CROUCH	=	2
ST_AIR		=	3
ST_ATTACK	=	4
ST_CATK		=	5
ST_CLIMB	=	6
ST_HURT		=	7
ST_DEAD		=	8
ST_SWING	=	9		; Hanging from a swinging vine (vines.asm moves him).
ST_UATK		=	10		; UP+attack standing: a swing over his head.

PLAYER_HP	=	48		; Health bar units: arcade 12288 / 256.
HIT_DAMAGE	=	12		; A lizardman hit: arcade 3072.
WATER_DRAIN	=	7		; Water (code 6): a unit every 8 frames (arcade 32/frame).
; After a hit (the arcade's $0550A8 handlers): hurt 23 frames knocked back, or
; 11 not (a touch that drains), then 33 untouchable ($10D30E); in an attack
; neither: 16 untouchable. A drain also blocks the next one for 80 ($10D366).
INVULN_FRAMES	=	23 + 33
INVULN_DRAIN	=	11 + 33
INVULN_ATTACK	=	16
DRAIN_LATCH	=	80

START_X		=	48		; Arcade x 32 + 16 (stage 1 start).
START_Y		=	295		; Arcade y 112 + 183.

		.zp
p_x:		ds	2
p_y:		ds	2
p_face:		ds	1		; 0 right, 1 left.
p_state:	ds	1
p_walkt:	ds	1		; Frames walked (speed ramp).
p_jtab:		ds	2		; Current jump table.
p_jlen:		ds	1
p_jidx:		ds	1
p_jdir:		ds	1		; 0 none, 1 right, $FF left.
p_jfall:	ds	1		; 0 rising, 1 falling (table), 2 free fall.
p_anim:		ds	2		; Current animation (pose, frames) list.
p_animi:	ds	1		; Index into it (bytes).
p_animt:	ds	1		; Frames left on this pose (0 = hold).
p_animend:	ds	1		; Set when a one-shot animation finished.
p_jatk:		ds	1		; Air attack: 0 none, 1 swing, 2 down thrust, 3 up-swing.
p_pose:		ds	1
p_pose_up:	ds	1		; Pose currently uploaded ($FF none).
p_buf:		ds	1		; 0: buffer A shows, 1: B.
p_ncells:	ds	1
p_hold:		ds	1
p_nograb:	ds	1		; Frames before a rope can be caught again.
p_hp:		ds	1
p_invuln:	ds	1		; Frames of invulnerability left (sprite flickers).
p_kdir:		ds	1		; Knockback: 1 right, $FF left.
p_frame:	ds	1		; Frame counter (flicker).
sb_x0:		ds	2		; Sword hitbox (world), valid when sword_box sets carry.
sb_x1:		ds	2
sb_y0:		ds	2
sb_y1:		ds	2		; Freeze the animation (climbing, not moving).
p_weapon:	ds	1		; WPN_*.
p_wtime:	ds	2		; Frames left with a taken weapon.
p_var:		ds	1		; Weapon drawing variant: weapon - 1, or 3 + flame step.
p_var_up:	ds	1		; Variant shown with p_pose_up.
p_wcount:	ds	1		; Weapon pieces this frame.
p_door:		ds	1		; Nonzero: walked into a door ($7E) this frame.
p_vine:		ds	1		; Vine slot + 1 while ST_SWING.
p_vine_h:	ds	1		; Its swing's half-step (signed): the side it is on.
p_vine_last:	ds	1		; The vine let go of (slot + 1), until he lands.
cx:		ds	2		; Collision probe position.
cy:		ds	2
cp:		ds	2
ctx:		ds	2
cty:		ds	1
ctmp:		ds	1
dx:		ds	1		; Signed per-frame deltas.
dy:		ds	1
pad:		ds	1
padtrg:		ds	1

		.bss
p_bufpose:	ds	2		; Per buffer: pose whose body cells it holds ($FF none),
p_bufwpose:	ds	2		; pose and variant whose weapon cells it holds.
p_bufvar:	ds	2
p_wbuf:		ds	16		; Weapon pieces: dx, dy, cell, SATB flags.
p_latch:	ds	1		; Frames before a touch can drain again.

		.code

; ---------------------------------------------------------------------------
; player_init

player_init:	lda	#<START_X
		sta	<p_x
		lda	#>START_X
		sta	<p_x + 1
		lda	#<START_Y
		sta	<p_y
		lda	#>START_Y
		sta	<p_y + 1
		stz	<p_face
		stz	<p_jatk
		stz	<p_nograb
		stz	<p_buf
		jsr	player_invalidate
		lda	#WPN_SWORD
		sta	<p_weapon
		jsr	enter_stand

		; Sprite palette 0 (VCE colors 256-271).
		lda	#^sprite_palette
		tam3
		stz	VCE_CTA + 0
		lda	#1
		sta	VCE_CTA + 1
		tia	sprite_palette, VCE_CTW, 32
		rts

; ---------------------------------------------------------------------------
; player_update - read pad, run the state machine, move with collision.

player_update:	lda	#COLL_BANK		; Collision data at $A000.
		tam5
		inc	<p_frame
		lda	<p_invuln
		beq	!+
		dec	<p_invuln
!:		lda	p_latch
		beq	!+
		dec	p_latch
!:		lda	<p_weapon		; A taken weapon runs out.
		cmp	#WPN_SWORD
		beq	!+
		lda	<p_wtime
		bne	.wdec
		dec	<p_wtime + 1
.wdec:		dec	a
		sta	<p_wtime
		ora	<p_wtime + 1
		bne	!+
		lda	#WPN_SWORD
		sta	<p_weapon
!:
		lda	joynow
		sta	<pad
		lda	joytrg
		sta	<padtrg
		lda	<p_state
		cmp	#ST_DEAD
		beq	!+
		jsr	hazards
		bcc	!+
		rts				; Just died.
!:
		lda	<p_state
		asl	a
		tax
		jmp	[.states, x]

.states:	dw	st_ground		; ST_STAND
		dw	st_ground		; ST_WALK
		dw	st_crouch
		dw	st_air
		dw	st_attack
		dw	st_catk
		dw	st_climb
		dw	st_hurt
		dw	st_dead
		dw	st_swing
		dw	st_uatk

; --- Standing / walking.
st_ground:	bbr0	<padtrg, .no_jump	; JOY_B1: jump.
		jmp	start_jump
.no_jump:	bbr1	<padtrg, .no_atk	; JOY_B2: attack.
		bbr6	<pad, .up_atk		; JOY_D held: crouch attack.
		jmp	enter_catk
.up_atk:	bbr4	<pad, .stand_atk	; JOY_U held: over his head.
		jmp	enter_uatk
.stand_atk:	jmp	enter_attack
.no_atk:	bbr6	<pad, .no_crouch
		jmp	enter_crouch
.no_crouch:	bbr4	<pad, .no_up		; UP: grab a rope at the body.
		jsr	rope_grab
		bcc	.no_up
		rts
.no_up:		bbs5	<pad, .right
		bbs7	<pad, .left
		lda	<p_state		; No direction: stand.
		cmp	#ST_STAND
		beq	.check_floor
		jsr	enter_stand
		bra	.check_floor
.right:		stz	<p_face
		bra	.walk
.left:		lda	#1
		sta	<p_face
.walk:		lda	<p_state
		cmp	#ST_WALK
		beq	!+
		lda	#ST_WALK
		sta	<p_state
		stz	<p_walkt
		lda	#<anim_walk
		ldx	#>anim_walk
		jsr	set_anim
!:		ldx	#1			; Speed ramp: 1px for 15 frames, then 2.
		lda	<p_walkt
		cmp	#16
		bcc	!+
		ldx	#2
		bra	.step
!:		inc	<p_walkt
.step:		txa
		ldy	<p_face
		beq	!+
		eor	#$FF			; Negate for left.
		inc	a
!:		sta	<dx
		jsr	move_x
.check_floor:	jsr	floor_below
		bcs	.done
		jmp	start_fall
.done:		rts

; --- Crouching.
st_crouch:	bbr1	<padtrg, !+
		jmp	enter_catk
!:		bbr0	<padtrg, !+
		jmp	start_jump
!:		bbs6	<pad, !+
		jmp	enter_stand
!:		bbr5	<pad, !+		; Turn while crouched.
		stz	<p_face
!:		bbr7	<pad, ground_check
		lda	#1
		sta	<p_face
; ground_check - fall if the floor went away (the cave block crumbling).
ground_check:	jsr	floor_below
		bcs	!+
		jmp	start_fall
!:		rts

; --- Standing attack: no movement until the swing ends.
st_attack:	lda	<p_animend
		beq	ground_check
		jmp	enter_stand

st_catk:	lda	<p_animend
		beq	ground_check
		jmp	enter_crouch

; --- UP+attack standing: the sword goes over his head.
st_uatk:	lda	<p_animend
		beq	ground_check
		jmp	enter_stand

; --- In the air.
st_air:		bbr1	<padtrg, .no_atk	; Air attack (once per jump):
		lda	<p_jatk
		bne	.no_atk
		bbr6	<pad, .not_down		; DOWN: down thrust, held to landing.
		lda	#2
		sta	<p_jatk
		lda	#<anim_dthrust
		ldx	#>anim_dthrust
		jsr	set_anim
		bra	.no_atk
.not_down:	lda	#SFX_SWING
		jsr	sound_sfx
		bbr4	<pad, .swing		; UP: the swing over his head, as standing
		lda	#3			; (on the jump's legs), else a swing.
		sta	<p_jatk
		lda	#<anim_juattack
		ldx	#>anim_juattack
		jsr	set_anim
		bra	.no_atk
.swing:		inc	<p_jatk
		lda	#<anim_jatk
		ldx	#>anim_jatk
		jsr	set_anim
.no_atk:	lda	<p_jatk			; Back to the jump pose when done.
		beq	!+
		lda	<p_animend
		beq	!+
		stz	<p_jatk
		lda	#<anim_jump
		ldx	#>anim_jump
		jsr	set_anim

!:		jsr	rope_grab		; Catch ropes in the air.
		bcc	!+
		rts
!:		lda	<p_jfall
		cmp	#2
		beq	.free
		; Table entry = p_jtab + p_jidx * 2.
		lda	<p_jidx
		asl	a
		tay
		lda	[p_jtab], y		; dx magnitude
		ldx	<p_jdir
		beq	.nodx
		cpx	#1
		beq	!+
		eor	#$FF
		inc	a
!:		bra	.setdx
.nodx:		cla
.setdx:		sta	<dx
		iny
		lda	[p_jtab], y		; up
		ldx	<p_jfall
		bne	.falling
		eor	#$FF			; Rising: dy = -up.
		inc	a
		sta	<dy
		inc	<p_jidx
		lda	<p_jidx
		cmp	<p_jlen
		bcc	.move
		dec	<p_jidx			; Apex: replay the table backwards.
		lda	#1
		sta	<p_jfall
		bra	.move
.falling:	sta	<dy
		lda	<p_jidx
		beq	.to_free
		dec	<p_jidx
		bra	.move
.to_free:	lda	#2
		sta	<p_jfall
		bra	.move
.free:		lda	#4			; Terminal fall speed.
		sta	<dy
		lda	<p_jdir			; Keep drifting the last way.
		beq	!+
		lda	#2
		ldx	<p_jdir
		cpx	#1
		beq	!+
		lda	#$FE
!:		sta	<dx

.move:		jsr	move_x
		lda	<dy
		bmi	.up
		beq	.done
		jsr	move_down		; Lands (and changes state) on a floor.
		bra	.done
.up:		jsr	move_up
.done:		; Fell below the map (y >= 512): restart the stage.
		lda	<p_y + 1
		bmi	!+			; (above row 0: the castle's upper squares)
		cmp	#2
		bcc	!+
		jmp	player_died
!:		rts

; --- Hit: knocked back 1px/frame for the hurt animation, then stand (or die).
st_hurt:	lda	<p_kdir
		sta	<dx
		jsr	move_x
		jsr	floor_below		; Fall if knocked off a ledge.
		bcs	!+
		lda	#1
		sta	<dy
		jsr	move_down_nl
!:		lda	<p_animend
		beq	.done
		lda	<p_hp
		bne	!+
		jmp	enter_dead		; Out of health.
!:		jmp	enter_stand
.done:		rts

; --- Dying: the arcade's death animation, then lose a life.
st_dead:	lda	<p_animend
		beq	!+
		jmp	player_died
!:		rts

enter_dead:	lda	#VOICE_DIE		; His death cry (an ADPCM voice).
		jsr	voice_play
		lda	#ST_DEAD
		sta	<p_state
		stz	<p_jatk
		stz	<p_invuln
		lda	#<anim_death
		ldx	#>anim_death
		jmp	set_anim

; hazards - collision codes that hurt: 7 and 8 kill (arcade state 8), 6 is
; water that drains health (arcade: 32 of 12288 a frame). Probes the feet
; (p_y + 25) and the body (p_y + 8) at p_x. Carry set if Rastan just died.
hazards:	lda	<dbg_god		; Debug menu: invincible.
		beq	!+
		clc
		rts
!:		lda	#25
		jsr	hazard_probe
		bcs	.die
		lda	#8
		jsr	hazard_probe
		bcs	.die
		cmp	#6
		bne	.ok
		lda	<p_frame		; In the water: drain.
		and	#WATER_DRAIN
		bne	.ok
		lda	<p_hp
		beq	.ok
		dec	a
		sta	<p_hp
		bne	.ok
.die:		jsr	enter_dead
		sec
		rts
.ok:		clc
		rts

; hazard_probe - code at (p_x, p_y + A) in A; carry set if it kills (7, 8).
hazard_probe:	clc
		adc	<p_y
		sta	<cy
		lda	<p_y + 1
		adc	#0
		sta	<cy + 1
		lda	<p_x
		sta	<cx
		lda	<p_x + 1
		sta	<cx + 1
		jsr	coll_at
		and	#$0F
		cmp	#7
		beq	.kill
		cmp	#8
		beq	.kill
		clc
		rts
.kill:		sec
		rts

; player_hit - an enemy hits Rastan: A = knockback direction (1 right, $FF
; left), Y = health units. Ignored while untouchable or already hurt. In an
; attack he keeps on with it (16 frames untouchable); else he is knocked back.
player_hit:
	.if	GOD_MODE			; Test builds: enemies can't hurt him.
		rts
	.endif
		ldx	<dbg_god		; Debug menu: invincible.
		bne	.no
		ldx	<p_invuln
		bne	.no
		ldx	<p_state
		cpx	#ST_HURT
		beq	.no
		cpx	#ST_DEAD
		beq	.no
		sta	<p_kdir
		jsr	player_attacking
		bcc	!+
		lda	#DRAIN_LATCH
		sta	p_latch
		tya
		jmp	hit_in_attack
!:		tya
		jsr	hp_sub
		lda	#INVULN_FRAMES
		sta	<p_invuln
		lda	#<anim_hurt
		ldx	#>anim_hurt
		bra	enter_hurt
.no:		rts

; enter_hurt - A/X = the hurt animation.
enter_hurt:	pha
		lda	#ST_HURT
		sta	<p_state
		stz	<p_jatk
		pla
		jmp	set_anim

; player_touch - X's body touches Rastan's: A = its touch type (the arcade's
; ($29,A4)): 1, 2 drain 4, 8 units (hurt 11 frames, not knocked back; not
; again for 80 frames), 3 on knock him back for 4 per step (12 for 3).
player_touch:
	.if	GOD_MODE
		rts
	.endif
		cmp	#3
		bcc	.drain
		asl	a			; 4 units a step.
		asl	a
		tay
		lda	<p_x			; Knocked away from it.
		cmp	e_xl, x
		lda	<p_x + 1
		sbc	e_xh, x
		lda	#1
		bcs	!+
		lda	#$FF
!:		jmp	player_hit
.drain:		ldy	<dbg_god
		bne	.no
		ldy	<p_invuln
		bne	.no
		ldy	p_latch
		bne	.no
		ldy	<p_state
		cpy	#ST_HURT
		beq	.no
		cpy	#ST_DEAD
		beq	.no
		asl	a
		asl	a
		tay
		lda	#DRAIN_LATCH
		sta	p_latch
		jsr	player_attacking
		tya
		bcs	hit_in_attack
		jsr	hp_sub
		lda	#INVULN_DRAIN
		sta	<p_invuln
		stz	<p_kdir			; (not knocked back)
		lda	#<anim_hurt_short
		ldx	#>anim_hurt_short
		bra	enter_hurt
.no:		rts

; hit_in_attack - A = units: hit while attacking, he keeps on (dies at 0).
hit_in_attack:	jsr	hp_sub
		lda	#INVULN_ATTACK
		sta	<p_invuln
		lda	<p_hp
		bne	!+
		jmp	enter_dead
!:		rts

; hp_sub - p_hp -= A (not below 0), with the arcade's hurt sound ($0C).
hp_sub:		sta	<ctmp
		phx
		lda	#SFX_HURT
		jsr	sound_sfx
		plx
		lda	<p_hp
		sec
		sbc	<ctmp
		bcs	!+
		cla
!:		sta	<p_hp
		rts

; weapon_power - A = what a hit of Rastan's takes off (the arcade's $10D310,
; $0549DE; $044804 adds 1 for 2, 3 for 8): 3 in a down thrust, with the axe or
; the fire sword, or in any attack in the air; else 1.
weapon_power:	lda	<p_jatk
		bne	.three			; (in the air: any attack)
		lda	<p_weapon
		cmp	#WPN_AXE
		beq	.three
		cmp	#WPN_FIRE
		beq	.three
		lda	#1
		rts
.three:		lda	#3
		rts

; player_attacking - carry set while Rastan attacks (the arcade's $10D108).
player_attacking:
		lda	<p_state
		cmp	#ST_ATTACK
		beq	.yes
		cmp	#ST_CATK
		beq	.yes
		cmp	#ST_UATK
		beq	.yes
		cmp	#ST_AIR
		bne	.no
		lda	<p_jatk
		beq	.no
.yes:		sec
		rts
.no:		clc
		rts

; player_drain - A = health units lost without being knocked back (a bat).
player_drain:
	.if	GOD_MODE
		rts
	.endif
		ldx	<dbg_god
		bne	.no
		ldx	<p_state
		cpx	#ST_DEAD
		beq	.no
		jsr	hp_sub
		lda	<p_hp
		bne	.no
		jmp	enter_dead
.no:		rts

; sword_box - carry set and sb_* set if Rastan's weapon hits this frame: the
; arcade's rules ($054982: $10D2F8 = 1) and boxes (write_boxes in pce_player.py,
; per pose and weapon). It hits
;  - in a swing (standing, crouched, in the air) from its 3rd frame through
;    the 11th (atk3, atk4, atk5: the blade out, not drawn back), and in the
;    swing over his head from its 2nd frame through the 12th;
;  - all through a down thrust, and all through any attack with the fire sword;
;  - held up, as he rises in a jump (not while hurt: $10D2F0).
sword_box:	lda	<p_state
		cmp	#ST_ATTACK
		beq	.swing
		cmp	#ST_CATK
		beq	.swing
		cmp	#ST_UATK
		beq	.uatk
		cmp	#ST_AIR
		bne	.none
		lda	<p_jatk
		beq	.rise
		cmp	#2
		beq	.on			; Down thrust: all through.
		cmp	#3
		beq	.uatk			; The up-swing: as standing.
		jsr	.fire
		bcs	.on
		lda	<p_animi		; Jump swing: jatk3, jatk4, then 8 of
		cmp	#4			; jatk5's 10 frames.
		bcc	.none
		cmp	#8
		bcc	.on
		bne	.none
		lda	<p_animt
		cmp	#3
		bcs	.on
.none:		clc
		rts
.rise:		lda	<p_jfall		; Rising: the sword held up.
		bne	.none
		bra	.on
.swing:		jsr	.fire
		bcs	.on
		lda	<p_animi		; atk3, atk4, atk5 (entries 2-4).
		cmp	#4
		bcc	.none
		cmp	#10
		bcs	.none
		bra	.on
.uatk:		jsr	.fire
		bcs	.on
		lda	<p_animi		; uatk1 from its 2nd frame, uatk2, uatk3
		beq	.u1			; for 4 of its 8 frames.
		cmp	#2
		beq	.on
		cmp	#4
		bne	.none
		lda	<p_animt
		cmp	#5
		bcs	.on
		bra	.none
.u1:		lda	<p_animt
		cmp	#4
		bcs	.none
.on:		ldy	<p_pose			; The pose's weapon box.
		lda	pose_wslot, y
		beq	.none
		dec	a
		ldy	<p_weapon
		clc
		adc	wbox_base - 1, y
		tay
		lda	<p_face
		bne	.left
		lda	wbox_x0, y		; Facing right: p_x + x0 .. p_x + x1.
		jsr	box_add_px
		sta	<sb_x0
		stx	<sb_x0 + 1
		lda	wbox_x1, y
		jsr	box_add_px
		sta	<sb_x1
		stx	<sb_x1 + 1
		bra	.y
.left:		lda	wbox_x1, y		; Left: p_x - x1 .. p_x - x0.
		eor	#$FF
		inc	a
		jsr	box_add_px
		sta	<sb_x0
		stx	<sb_x0 + 1
		lda	wbox_x0, y
		eor	#$FF
		inc	a
		jsr	box_add_px
		sta	<sb_x1
		stx	<sb_x1 + 1
.y:		lda	wbox_y0, y		; y = p_y + y0 .. p_y + y1 (signed)
		jsr	box_add_py
		sta	<sb_y0
		stx	<sb_y0 + 1
		lda	wbox_y1, y
		jsr	box_add_py
		sta	<sb_y1
		stx	<sb_y1 + 1
		sec
		rts
.fire:		lda	<p_weapon		; Carry set: the fire sword.
		cmp	#WPN_FIRE
		beq	!+
		clc
!:		rts
box_add_px:	phy				; A (signed) + p_x -> A/X
		pha
		clc
		adc	<p_x
		tax
		pla
		and	#$80
		beq	!+
		lda	#$FF
!:		adc	<p_x + 1
		sax
		ply
		rts
box_add_py:	phy				; A (signed) + p_y -> A/X
		pha
		clc
		adc	<p_y
		tax
		pla
		and	#$80
		beq	!+
		lda	#$FF
!:		adc	<p_y + 1
		sax
		ply
		rts
wbox_base:	db	0, WBOX_SLOTS, 2 * WBOX_SLOTS, 3 * WBOX_SLOTS

; body_box - sb_* = Rastan's body box (the arcade's, $10D248: per pose, x
; mirrored facing left, y from y0 to 26 below the anchor).
body_box:	ldy	<p_pose
		lda	<p_face
		bne	.left
		lda	pbody_x0, y
		jsr	box_add_px
		sta	<sb_x0
		stx	<sb_x0 + 1
		lda	pbody_x1, y
		jsr	box_add_px
		sta	<sb_x1
		stx	<sb_x1 + 1
		bra	.y
.left:		lda	pbody_x1, y
		eor	#$FF
		inc	a
		jsr	box_add_px
		sta	<sb_x0
		stx	<sb_x0 + 1
		lda	pbody_x0, y
		eor	#$FF
		inc	a
		jsr	box_add_px
		sta	<sb_x1
		stx	<sb_x1 + 1
.y:		lda	pbody_y0, y
		jsr	box_add_py
		sta	<sb_y0
		stx	<sb_y0 + 1
		lda	#PBODY_Y1
		jsr	box_add_py
		sta	<sb_y1
		stx	<sb_y1 + 1
		rts

; --- On a vine: LEFT/RIGHT turn; I lets go, on the side he faces only.
st_swing:	bbr5	<pad, !+
		stz	<p_face
!:		bbr7	<pad, !+
		lda	#1
		sta	<p_face
!:		bbr0	<padtrg, .done
		ldx	<p_face
		lda	<p_vine_h
		beq	.done
		cpx	#0
		bne	.left
		tax				; Facing right: on the right (h > 0)?
		bmi	.done
		bra	.go
.left:		tax
		bpl	.done
.go:		lda	<p_vine
		sta	<p_vine_last
		stz	<p_vine
		lda	#VINE_NOGRAB
		sta	<p_nograb
		jmp	start_jump
.done:		rts

; enter_swing - caught a vine (vines.asm has set p_vine).
enter_swing:	lda	#ST_SWING
		sta	<p_state
		stz	<p_jatk
		lda	#<anim_swing
		ldx	#>anim_swing
		jmp	set_anim

; --- On a rope: UP climbs, DOWN slides, I jumps off.
st_climb:	lda	#1
		sta	<p_hold
		bbr5	<pad, !+		; Face where the stick points.
		stz	<p_face
!:		bbr7	<pad, !+
		lda	#1
		sta	<p_face
!:		bbr0	<padtrg, !+
		stz	<p_hold
		lda	#16
		sta	<p_nograb
		jmp	start_jump
!:		bbr4	<pad, .down
		lda	#$E8			; Rope above the hands (p_y - 24)?
		jsr	rope_probe
		bcc	.done
		stz	<p_hold
		lda	<p_y
		bne	!+
		dec	<p_y + 1
!:		dec	<p_y
.done:		rts
.down:		bbr6	<pad, .done
		stz	<p_hold
		jsr	floor_below
		bcc	!+
		jmp	enter_stand
!:		lda	#8			; Rope continues below?
		jsr	rope_probe
		bcs	!+
		stz	<p_hold
		jmp	start_fall
!:		inc	<p_y
		bne	!+
		inc	<p_y + 1
!:		rts

; rope_probe - carry set if there is rope at (p_x, p_y + A) (A signed).
rope_probe:	sta	<ctmp
		clc
		adc	<p_y
		sta	<cy
		lda	<ctmp
		and	#$80
		beq	!+
		lda	#$FF
!:		adc	<p_y + 1
		sta	<cy + 1
		lda	<p_x
		sta	<cx
		lda	<p_x + 1
		sta	<cx + 1
		jsr	coll_at
		and	#$0F
		cmp	#2
		beq	!+
		clc
		rts
!:		sec
		rts

; rope_grab - if a rope is within 5px of p_x at hand height (p_y - 8),
; snap onto it and start climbing. Carry set if grabbed.
rope_grab:	lda	<p_nograb
		beq	!+
		dec	<p_nograb
		clc
		rts
!:		lda	<p_y
		sec
		sbc	#8
		sta	<cy
		lda	<p_y + 1
		sbc	#0
		sta	<cy + 1
		ldx	#2
.try:		lda	.offs, x
		clc
		adc	<p_x
		sta	<cx
		lda	.offs, x
		and	#$80
		beq	!+
		lda	#$FF
!:		adc	<p_x + 1
		sta	<cx + 1
		phx
		jsr	coll_at
		plx
		and	#$0F
		cmp	#2
		beq	.grab
		dex
		bpl	.try
		clc
		rts
.grab:		lda	<cx			; p_x = rope tile x + 4
		and	#$F8
		ora	#4
		sta	<p_x
		lda	<cx + 1
		sta	<p_x + 1
		lda	#ST_CLIMB
		sta	<p_state
		stz	<p_jatk
		lda	#<anim_climb
		ldx	#>anim_climb
		jsr	set_anim
		sec
		rts
.offs:		db	-5, 0, 5

; ---------------------------------------------------------------------------
; State entry.

enter_stand:	lda	#ST_STAND
		sta	<p_state
		lda	#<anim_idle
		ldx	#>anim_idle
		jmp	set_anim

enter_crouch:	lda	#ST_CROUCH
		sta	<p_state
		lda	#<anim_crouch
		ldx	#>anim_crouch
		jmp	set_anim

enter_attack:	pha
		lda	#SFX_SWING
		jsr	sound_sfx
		pla
		lda	#ST_ATTACK
		sta	<p_state
		lda	#<anim_attack
		ldx	#>anim_attack
		jmp	set_anim

enter_uatk:	lda	#SFX_SWING
		jsr	sound_sfx
		lda	#ST_UATK
		sta	<p_state
		lda	#<anim_uattack
		ldx	#>anim_uattack
		jmp	set_anim

enter_catk:	lda	#SFX_SWING
		jsr	sound_sfx
		lda	#ST_CATK
		sta	<p_state
		lda	#<anim_catk
		ldx	#>anim_catk
		jmp	set_anim

; start_jump: UP held = high jump; a direction held = forward jump.
start_jump:	lda	#VOICE_JUMP		; The arcade's grunt (an ADPCM voice
		jsr	voice_play		; there, not an FM effect).
		stz	<p_jdir
		bbr5	<pad, !+
		stz	<p_face
		lda	#1
		sta	<p_jdir
!:		bbr7	<pad, !+
		lda	#1
		sta	<p_face
		lda	#$FF
		sta	<p_jdir
!:		bbs4	<pad, .high
		lda	<p_jdir
		bne	.low_fwd
		lda	#<jump_low
		ldx	#>jump_low
		ldy	#JUMP_LOW_LEN
		bra	.go
.low_fwd:	lda	#<jump_low_fwd
		ldx	#>jump_low_fwd
		ldy	#JUMP_LOW_FWD_LEN
		bra	.go
.high:		lda	<p_jdir
		bne	.high_fwd
		lda	#<jump_high
		ldx	#>jump_high
		ldy	#JUMP_HIGH_LEN
		bra	.go
.high_fwd:	lda	#<jump_high_fwd
		ldx	#>jump_high_fwd
		ldy	#JUMP_HIGH_FWD_LEN
.go:		sta	<p_jtab
		stx	<p_jtab + 1
		sty	<p_jlen
		stz	<p_jidx
		stz	<p_jfall
		bra	enter_air

; start_fall: walked off a ledge - descend the low table from its apex.
start_fall:	lda	#<jump_low
		sta	<p_jtab
		lda	#>jump_low
		sta	<p_jtab + 1
		lda	#JUMP_LOW_LEN
		sta	<p_jlen
		dec	a
		sta	<p_jidx
		lda	#1
		sta	<p_jfall
		stz	<p_jdir
enter_air:	lda	#ST_AIR
		sta	<p_state
		stz	<p_jatk
		lda	#<anim_jump
		ldx	#>anim_jump
		jmp	set_anim

; player_invalidate - forget what the pattern buffers hold.
player_invalidate:
		lda	#$FF
		sta	<p_pose_up
		sta	p_bufpose
		sta	p_bufpose + 1
		sta	p_bufwpose
		sta	p_bufwpose + 1
		rts

; player_set_weapon - A = weapon; a taken one lasts WEAPON_FRAMES.
player_set_weapon:
		pha
		lda	#SFX_ITEM
		jsr	sound_sfx
		pla
		sta	<p_weapon
		lda	#<WEAPON_FRAMES
		sta	<p_wtime
		lda	#>WEAPON_FRAMES
		sta	<p_wtime + 1
		rts

player_init_pos:
		stz	<p_door
		stz	<p_vine
		stz	<p_vine_last
		lda	#WPN_SWORD		; A life starts with the sword.
		sta	<p_weapon
		lda	#PLAYER_HP
		sta	<p_hp
		stz	<p_invuln
		stz	p_latch
		stz	<p_nograb
		stz	<p_jatk
		stz	<p_face
		lda	#<START_X
		sta	<p_x
		lda	#>START_X
		sta	<p_x + 1
		lda	#<START_Y
		sta	<p_y
		lda	#>START_Y
		sta	<p_y + 1
		jmp	enter_stand

; ---------------------------------------------------------------------------
; move_x - move by signed dx one pixel at a time, stopping at walls and at
; the left edge of the screen.

move_x:		lda	<dx
		beq	.done
		bmi	.left
.right:		jsr	wall_right
		bcs	.done
		inc	<p_x
		bne	!+
		inc	<p_x + 1
!:		dec	<dx
		bne	.right
.done:		rts
.left:		; Left limit: scroll_x + 16.
		lda	<scroll_x
		clc
		adc	#16
		sta	<ctmp
		lda	<scroll_x + 1
		adc	#0
		cmp	<p_x + 1
		bcc	.lok
		bne	.done
		lda	<ctmp
		cmp	<p_x
		bcs	.done
.lok:		jsr	wall_left
		bcs	.done
		lda	<p_x
		bne	!+
		dec	<p_x + 1
!:		dec	<p_x
		inc	<dx
		bne	.left
		rts

; move_down - dy pixels down, landing on floors.
move_down:	jsr	floor_below
		bcs	.land
		inc	<p_y
		bne	!+
		inc	<p_y + 1
!:		dec	<dy
		bne	move_down
		rts
.land:		lda	<p_jatk			; Down thrust lands crouched.
		stz	<p_jatk
		cmp	#2
		bne	!+
		jmp	enter_crouch
!:
		lda	<pad
		and	#JOY_L + JOY_R
		beq	!+
		lda	#ST_STAND		; set_anim via st_ground next frame
		sta	<p_state
		lda	#<anim_idle
		ldx	#>anim_idle
		jmp	set_anim
!:		jmp	enter_stand

; move_down_nl - dy pixels down, stopping on floors without changing state.
move_down_nl:	jsr	floor_below
		bcs	.done
		inc	<p_y
		bne	!+
		inc	<p_y + 1
!:		dec	<dy
		bne	move_down_nl
.done:		rts

; move_up - dy (negative) pixels up. Rastan jumps through platforms, but a
; solid cell (code 1) over his head (p_y - 25) stops the rise: the jump turns
; into its fall (the arcade: he can't jump up through the castle's ledges).
move_up:	lda	<p_y			; cy = p_y - 25, cx = p_x
		sec
		sbc	#25
		sta	<cy
		lda	<p_y + 1
		sbc	#0
		sta	<cy + 1
		lda	<p_x
		sta	<cx
		lda	<p_x + 1
		sta	<cx + 1
		jsr	coll_at
		and	#$0F
		cmp	#1
		beq	.bump
		lda	<p_y
		bne	!+
		dec	<p_y + 1
!:		dec	<p_y
		inc	<dy
		bne	move_up
		rts
.bump:		rts				; Head on a ceiling: no higher this frame (the
						; jump goes on: the arcade glides along it).

; ---------------------------------------------------------------------------
; Collision probes. Carry set = blocked / floor found.

floor_below:	lda	<p_y			; cy = p_y + 25
		clc
		adc	#25
		sta	<cy
		lda	<p_y + 1
		adc	#0
		sta	<cy + 1
		lda	<p_x			; cx = p_x - 6
		sec
		sbc	#6
		sta	<cx
		lda	<p_x + 1
		sbc	#0
		sta	<cx + 1
		jsr	coll_at
		jsr	is_floor
		bcs	.yes
		lda	<cx			; cx += 12
		clc
		adc	#12
		sta	<cx
		bcc	!+
		inc	<cx + 1
!:		jsr	coll_at
		jmp	is_floor
.yes:		rts

; wall_right / wall_left: probe x = p_x +/- 10 at four heights.
wall_right:	lda	<p_x
		clc
		adc	#10
		sta	<cx
		lda	<p_x + 1
		adc	#0
		sta	<cx + 1
		bra	wall_column
wall_left:	lda	<p_x
		sec
		sbc	#10
		sta	<cx
		lda	<p_x + 1
		sbc	#0
		sta	<cx + 1
wall_column:	ldx	#3
.loop:		lda	.heights, x		; cy = p_y + height (signed)
		clc
		adc	<p_y
		sta	<cy
		lda	.heights, x
		bmi	.neg
		lda	<p_y + 1
		adc	#0
		bra	!+
.neg:		lda	<p_y + 1
		adc	#$FF
!:		sta	<cy + 1
		phx
		jsr	coll_at
		plx
		and	#$0F
		cmp	#1
		beq	.blocked
		cmp	#$0E			; A door: a wall that takes him through.
		beq	.door
		dex
		bpl	.loop
		clc
		rts
.door:		sta	<p_door
.blocked:	sec
		rts
.heights:	db	20, 4, -12, -20		; (not the top of the head: he glides under ceilings)

; is_floor - carry set if collision code A is something to stand on.
is_floor:	and	#$0F
		cmp	#8
		bcs	.no
		tax
		lda	.tab, x
		lsr	a
		rts
.no:		clc
		rts
.tab:		db	0, 1, 0, 1, 1, 0, 0, 1

; coll_at - collision code at world (cx, cy). Outside the world's squares:
; 0 above the top or below the bottom row of squares and above row 0
; (open sky), 1 elsewhere (walls). 1 inside a solid prop, and on a passage
; ($80) that a shaft has sealed: at or below row_top + SEAL_DEPTH.
; Data (MPR5 $A000, tools/pce_player.py): square ids at (x >> 9, (y >> 9) + 2),
; 256 bytes per square (block columns of 16), 16-byte 4x4 patterns.
SEAL_DEPTH	=	480
coll_at:	phx				; (X and Y kept)
		phy
		jsr	coll_world
		ply
		plx
		rts
coll_world:	lda	<prop_solid		; A solid prop (the cave block) first.
		beq	.map
		jsr	prop_coll
		bcc	.map
		lda	#1
		rts
.map:		lda	<cy + 1			; Square row (y >> 9) + 2: 0..2.
		cmp	#$80
		ror	a
		clc
		adc	#2
		cmp	#3
		bcs	.empty			; Below row 0, or far above.
		tax
		lda	<cx + 1			; Square column x >> 9: 0..23.
		bmi	.solid
		lsr	a
		cmp	#24
		bcs	.solid
		clc
		adc	.rows, x
		tay
		lda	$A000, y		; Square id.
		cmp	#$FF
		bne	.square
		cpx	#2			; None: sky above row 0, else wall.
		bcc	.empty
.solid:		lda	#1
		rts
.empty:		cla
		rts
.rows:		db	0, 24, 48

.square:	inc	a			; cp = $A100 + id * 256 + block column * 16 + block row
		ora	#$A0
		sta	<cp + 1
		lda	<cx			; block column = (cx >> 5) & 15
		sta	<ctx
		lda	<cx + 1
		lsr	a
		ror	<ctx
		lsr	a
		ror	<ctx
		lsr	a
		ror	<ctx			; ctx = cx >> 3 (low 8 bits)
		lda	<cy
		sta	<cty
		lda	<cy + 1
		lsr	a
		ror	<cty
		lsr	a
		ror	<cty
		lsr	a
		ror	<cty			; cty = cy >> 3 (low 8 bits)
		lda	<ctx
		asl	a			; (ctx >> 2) & 15 = block column, * 16
		asl	a
		and	#$F0
		sta	<cp
		lda	<cty
		lsr	a
		lsr	a
		and	#$0F
		ora	<cp
		sta	<cp
		lda	[cp]			; Pattern number.
		sta	<cp
		stz	<cp + 1
		asl	<cp
		rol	<cp + 1
		asl	<cp
		rol	<cp + 1
		asl	<cp
		rol	<cp + 1
		asl	<cp
		rol	<cp + 1
		lda	<cty
		and	#3
		asl	a
		asl	a
		sta	<ctmp
		lda	<ctx
		and	#3
		ora	<ctmp
		ora	<cp
		clc
		adc	#<($A000 + COLL_PATTERNS)
		sta	<cp
		lda	<cp + 1
		adc	#>($A000 + COLL_PATTERNS)
		sta	<cp + 1
		lda	[cp]
		bmi	.passage
		rts
.passage:	sta	<ctmp			; Sealed: cy >= row_top + SEAL_DEPTH?
		lda	<row_top
		clc
		adc	#<SEAL_DEPTH
		sta	<cp
		lda	<row_top + 1
		adc	#>SEAL_DEPTH
		bvs	.open			; (no rows streamed yet)
		sta	<cp + 1
		lda	<cy
		cmp	<cp
		lda	<cy + 1
		sbc	<cp + 1
		bvc	!+
		eor	#$80
!:		bmi	.open
		lda	#1
		rts
.open:		lda	<ctmp
		rts

; ---------------------------------------------------------------------------
; Animation.

; set_anim - A/X = animation list.
set_anim:	sta	<p_anim
		stx	<p_anim + 1
		stz	<p_hold
		stz	<p_animi
		stz	<p_animend
		ldy	#0
		lda	[p_anim], y
		sta	<p_pose
		iny
		lda	[p_anim], y
		sta	<p_animt
		rts

; anim_tick - advance one frame. Looping animations (walk) wrap; others end.
anim_tick:	lda	<p_hold
		bne	.done
		lda	<p_animt
		beq	.done			; 0 = hold.
		dec	<p_animt
		bne	.done
		lda	<p_animi		; Next entry.
		clc
		adc	#2
		sta	<p_animi
		tay
		lda	[p_anim], y
		cmp	#$FF
		bne	.set
		lda	<p_state		; End: walk/climb loop, others report.
		cmp	#ST_WALK
		beq	.loop
		cmp	#ST_CLIMB
		beq	.loop
		lda	#1
		sta	<p_animend
		dec	<p_animi		; Stay on the last pose.
		dec	<p_animi
		lda	#1
		sta	<p_animt
		rts
.loop:		stz	<p_animi
		cly
		lda	[p_anim], y
.set:		sta	<p_pose
		iny
		lda	[p_anim], y
		sta	<p_animt
.done:		rts

; ---------------------------------------------------------------------------
; Camera: follows Rastan's x 136 px from the screen's left (in a horizontal
; square only forwards; in a shaft both ways) and keeps his feet between
; screen y 80 and 176; then camera_clamp holds it in the box of the region
; of the next line to stream (stage_regions.inc).

camera_update:	lda	<p_x			; cv = p_x - 136
		sec
		sbc	#136
		sta	<cv
		lda	<p_x + 1
		sbc	#0
		sta	<cv + 1
		ldx	<cam_region
		lda	region_free, x
		bne	.setx
		lda	<scroll_x		; Forwards only: cv = max(cv, scroll_x).
		sta	<cl
		lda	<scroll_x + 1
		sta	<cl + 1
		jsr	smax
.setx:		lda	<cv
		sta	<scroll_x
		lda	<cv + 1
		sta	<scroll_x + 1

		; feet = p_y + 24: scroll_y in [feet - 176, feet - 80].
		lda	<scroll_y
		sta	<cv
		lda	<scroll_y + 1
		sta	<cv + 1
		lda	<p_y
		clc
		adc	#<(24 - 176)
		sta	<cl
		lda	<p_y + 1
		adc	#>(24 - 176)
		sta	<cl + 1
		jsr	smax
		jsr	cam_rest		; (the lava hall: lower, carry set)
		bcs	.sety
		lda	<p_y
		clc
		adc	#<(24 - 80)
		sta	<cl
		lda	<p_y + 1
		adc	#>(24 - 80)
		sta	<cl + 1
		jsr	smin
.sety:		lda	<cv
		sta	<scroll_y
		lda	<cv + 1
		sta	<scroll_y + 1
		; (fall through)

; camera_clamp - scroll_x, scroll_y into the box of cam_region. The BAT holds
; 512 px each way, so the camera also stays inside the last 512 px streamed:
; scroll_x >= col_last - STAGE_COL_REACH and scroll_y <= row_top + STAGE_ROW_REACH.


camera_clamp:	ldx	<cam_region
		lda	<scroll_x
		sta	<cv
		lda	<scroll_x + 1
		sta	<cv + 1
		lda	region_x0_l, x
		sta	<cl
		lda	region_x0_h, x
		sta	<cl + 1
		jsr	smax
		lda	<p_x + 1		; In the castle (p_x >= CASTLE_X, $2000),
		cmp	#>CASTLE_X		; not back past its wall: the arcade
		bcc	!+			; loads the room whole at the gate and
		stz	<cl			; its camera stays in it.
		lda	#>CASTLE_X
		sta	<cl + 1
		jsr	smax
!:		lda	<col_last		; Not back past the last column streamed
		clc				; minus the BAT's 512 px (less a margin).
		adc	#<-STAGE_COL_REACH
		sta	<cl
		lda	<col_last + 1
		adc	#>-STAGE_COL_REACH
		bvs	!+			; (no columns yet: $8000 - reach underflows)
		sta	<cl + 1
		jsr	smax
!:
		lda	region_x1_l, x
		sta	<cl
		lda	region_x1_h, x
		sta	<cl + 1
		jsr	smin
		lda	<p_x + 1		; Outside the castle, the camera stops
		cmp	#>CASTLE_X		; at its wall (the arcade's does at the
		bcs	!+			; gate): it never shows the castle's
		lda	#<(CASTLE_X - 256)	; rooms, whose palettes are not loaded.
		sta	<cl
		lda	#>(CASTLE_X - 256)
		sta	<cl + 1
		jsr	smin
!:		lda	<cv
		sta	<scroll_x
		lda	<cv + 1
		sta	<scroll_x + 1
		lda	<scroll_y
		sta	<cv
		lda	<scroll_y + 1
		sta	<cv + 1
		lda	<row_top
		clc
		adc	#<STAGE_ROW_REACH
		sta	<cl
		lda	<row_top + 1
		adc	#>STAGE_ROW_REACH
		sta	<cl + 1
		bvs	!+			; (no rows yet: $7FFF + reach overflows)
		jsr	smin
!:		lda	region_y1_l, x
		sta	<cl
		lda	region_y1_h, x
		sta	<cl + 1
		jsr	smin
		lda	region_y0_l, x
		sta	<cl
		lda	region_y0_h, x
		sta	<cl + 1
		jsr	smax
		lda	<cv
		sta	<scroll_y
		lda	<cv + 1
		sta	<scroll_y + 1
		rts

; cam_rest - in the lava hall (Rastan in CAM_REST_X0..X1) the arcade holds the
; camera low, its fire filling the bottom of the screen: cv (scroll_y) sinks a
; pixel a frame toward CAM_REST_Y, but no lower than keeps his head 8 px below
; the top (cv <= p_y - 36). Carry set if it applied.
cam_rest:	lda	<p_x
		cmp	#<CAM_REST_X0
		lda	<p_x + 1
		sbc	#>CAM_REST_X0
		bcc	.no
		lda	<p_x
		cmp	#<CAM_REST_X1
		lda	<p_x + 1
		sbc	#>CAM_REST_X1
		bcs	.no
		lda	#<CAM_REST_Y		; Sink: cv = min(cv + 1, CAM_REST_Y) ...
		sta	<cl
		lda	#>CAM_REST_Y
		sta	<cl + 1
		inc	<cv
		bne	!+
		inc	<cv + 1
!:		jsr	smin
		lda	<p_y			; ... and cv <= p_y - 36.
		sec
		sbc	#36
		sta	<cl
		lda	<p_y + 1
		sbc	#0
		sta	<cl + 1
		jsr	smin
		sec
		rts
.no:		clc
		rts

; smax - cv = max(cv, cl); smin - cv = min(cv, cl) (signed 16-bit). Keep X.
smax:		lda	<cv
		cmp	<cl
		lda	<cv + 1
		sbc	<cl + 1
		bvc	!+
		eor	#$80
!:		bpl	scopy_done
scopy:		lda	<cl
		sta	<cv
		lda	<cl + 1
		sta	<cv + 1
scopy_done:	rts
smin:		lda	<cl
		cmp	<cv
		lda	<cl + 1
		sbc	<cv + 1
		bvc	!+
		eor	#$80
!:		bmi	scopy
		rts

		include	"stage_regions.inc"

; ---------------------------------------------------------------------------
; player_draw - upload a new pose into the idle buffer, then write the SATB.
; Runs after the frame's logic; the SATB DMA at the next VBLANK picks it up,
; together with the scroll registers written then.

player_draw:	php				; VDC writes: IRQ held off (see stream_line).
		sei
		jsr	anim_tick
		; Weapon variant: weapon - 1; the fire sword's flame steps every 2 frames.
		lda	<p_weapon
		dec	a
		cmp	#WPN_FIRE - 1
		bcc	!+
		lda	<p_frame
		lsr	a
		and	#3
		clc
		adc	#WPN_FIRE - 1
!:		sta	<p_var
		; This pose's weapon pieces into p_wbuf.
		lda	#WTAB_BANK
		tam3
		lda	<p_var
		asl	a
		tay
		lda	weapon_vtab, y
		sta	<ctx
		lda	weapon_vtab + 1, y
		sta	<ctx + 1
		lda	<p_pose
		asl	a
		tay
		lda	[ctx], y
		sta	<cp
		iny
		lda	[ctx], y
		sta	<cp + 1
		lda	[cp]
		sta	<p_wcount
		asl	a
		asl	a
		tax
		beq	.wdone
		ldy	#1
!:		lda	[cp], y
		sta	p_wbuf - 1, y
		iny
		dex
		bne	!-
.wdone:
		; Changed: show it from the hidden buffer, uploading what that buffer lacks.
		stz	<cty			; Body cells to upload: no.
		lda	<p_pose
		cmp	<p_pose_up
		bne	.new
		lda	<p_var
		cmp	<p_var_up
		beq	.map
.new:		lda	<p_pose
		sta	<p_pose_up
		lda	<p_var
		sta	<p_var_up
		lda	<p_buf
		eor	#1
		sta	<p_buf
		tax
		lda	<p_pose
		cmp	p_bufpose, x
		beq	!+
		sta	p_bufpose, x
		inc	<cty			; Body cells: yes (below, once mapped).
!:		cmp	p_bufwpose, x
		bne	.wup
		lda	<p_var
		cmp	p_bufvar, x
		beq	.map
.wup:		lda	<p_pose
		sta	p_bufwpose, x
		lda	<p_var
		sta	p_bufvar, x
		jsr	upload_weapon
.map:		; Map the pose record (pose table at the start of player_data).
		lda	#PLAYER_BANK
		tam3
		lda	<p_pose
		asl	a
		clc
		adc	<p_pose			; *3
		tay
		lda	player_data, y		; bank offset
		clc
		adc	#PLAYER_BANK
		pha
		lda	player_data + 1, y
		sta	<cp
		lda	player_data + 2, y
		sta	<cp + 1
		pla
		tam3
		inc	a
		tam4
		lda	[cp]
		sta	<p_ncells

		lda	<cty
		beq	.satb
		st0	#VDC_MAWR		; Body cells into the (new) shown buffer.
		stz	VDC_DL
		lda	#>SPR_BUF_A
		ldx	<p_buf
		beq	!+
		lda	#>SPR_BUF_B
!:		sta	VDC_DH
		st0	#VDC_VWR
		; Pattern data starts at cp + 1 + ncells*2.
		lda	<p_ncells
		asl	a
		inc	a
		clc
		adc	<cp
		sta	<ctx
		lda	<cp + 1
		adc	#0
		sta	<ctx + 1
		ldx	<p_ncells
.cell:		cly
.word:		lda	[ctx], y
		sta	VDC_DL
		iny
		lda	[ctx], y
		sta	VDC_DH
		iny
		cpy	#128
		bne	.word
		lda	<ctx
		clc
		adc	#128
		sta	<ctx
		bcc	!+
		inc	<ctx + 1
!:		dex
		bne	.cell

.satb:		; (No flicker while untouchable: the arcade draws him every frame,
		; lizard.snp 668-723; the HUD's icon flashes.)
		; SATB entries 0..ncells-1, the weapon's, then clear what the last frame used.
		st0	#VDC_MAWR
		lda	#<(SATB_ADDR + HUD_ENTRIES * 4)	; After the HUD's entries.
		sta	VDC_DL
		lda	#>(SATB_ADDR + HUD_ENTRIES * 4)
		sta	VDC_DH
		st0	#VDC_VWR
		; base pattern = buffer >> 5
		lda	#(SPR_BUF_A >> 5) & $FF
		ldx	<p_buf
		beq	!+
		lda	#(SPR_BUF_B >> 5) & $FF
!:		sta	<ctmp
		ldx	#0			; cell index
		ldy	#1			; offset of (dx, dy) pairs
.ent:		cpx	<p_ncells
		bcc	!+
		jmp	.weapon
!:		; y = p_y + dy - scroll_y + 64
		iny
		lda	[cp], y			; dy
		dey
		sta	<cty
		clc
		adc	<p_y
		sta	<ctx
		lda	<cty
		and	#$80
		beq	!+
		lda	#$FF
!:		adc	<p_y + 1
		sta	<ctx + 1
		lda	<ctx
		sec
		sbc	<scroll_y
		sta	<ctx
		lda	<ctx + 1
		sbc	<scroll_y + 1
		sta	<ctx + 1
		lda	<ctx
		clc
		adc	#64
		sta	VDC_DL
		lda	<ctx + 1
		adc	#0
		and	#$03
		sta	VDC_DH
		; x = p_x + dx (or -dx-16 when facing left) - scroll_x + 32
		lda	[cp], y			; dx
		ldy	<p_face
		beq	!+
		eor	#$FF			; -dx - 16 = ~dx - 15
		sec
		sbc	#15
!:		sta	<cty
		clc
		adc	<p_x
		sta	<ctx
		lda	<cty
		and	#$80
		beq	!+
		lda	#$FF
!:		adc	<p_x + 1
		sta	<ctx + 1
		lda	<ctx
		sec
		sbc	<scroll_x
		sta	<ctx
		lda	<ctx + 1
		sbc	<scroll_x + 1
		sta	<ctx + 1
		lda	<ctx
		clc
		adc	#32
		sta	VDC_DL
		lda	<ctx + 1
		adc	#0
		and	#$03
		sta	VDC_DH
		; pattern = base + cell * 2 (16x16 cell = 64 words = 2 units of 32)
		txa
		asl	a
		clc
		adc	<ctmp
		sta	VDC_DL
		lda	#(SPR_BUF_A >> 13)
		adc	#0
		sta	VDC_DH
		; attributes: palette 0, in front of BG, H-flip when facing left
		lda	#$80
		sta	VDC_DL
		lda	<p_face
		beq	!+
		lda	#$08
!:		sta	VDC_DH
		inx
		txa				; y = 1 + cell*2
		asl	a
		inc	a
		tay
		jmp	.ent
.weapon:	; Weapon pieces (behind the body): p_wbuf, cells WEAPON_CELL...
		cly
.went:		cpy	<p_wcount
		bne	!+
		jmp	.clear
!:		phy
		tya
		asl	a
		asl	a
		tay				; Y = piece * 4
		lda	p_wbuf + 1, y		; y = p_y + dy - scroll_y + 64
		sta	<cty
		clc
		adc	<p_y
		sta	<ctx
		lda	<cty
		and	#$80
		beq	!+
		lda	#$FF
!:		adc	<p_y + 1
		sta	<ctx + 1
		lda	<ctx
		sec
		sbc	<scroll_y
		sta	<ctx
		lda	<ctx + 1
		sbc	<scroll_y + 1
		sta	<ctx + 1
		lda	<ctx
		clc
		adc	#64
		sta	VDC_DL
		lda	<ctx + 1
		adc	#0
		and	#$03
		sta	VDC_DH
		lda	p_wbuf, y		; x = p_x + dx (left: -dx - 16) - scroll_x + 32
		phy
		ldy	<p_face
		beq	!+
		eor	#$FF
		sec
		sbc	#15
!:		ply
		sta	<cty
		clc
		adc	<p_x
		sta	<ctx
		lda	<cty
		and	#$80
		beq	!+
		lda	#$FF
!:		adc	<p_x + 1
		sta	<ctx + 1
		lda	<ctx
		sec
		sbc	<scroll_x
		sta	<ctx
		lda	<ctx + 1
		sbc	<scroll_x + 1
		sta	<ctx + 1
		lda	<ctx
		clc
		adc	#32
		sta	VDC_DL
		lda	<ctx + 1
		adc	#0
		and	#$03
		sta	VDC_DH
		pla				; pattern = base + (WEAPON_CELL + piece) * 2
		pha
		clc
		adc	#WEAPON_CELL
		asl	a
		clc
		adc	<ctmp
		sta	VDC_DL
		lda	#(SPR_BUF_A >> 13)
		adc	#0
		sta	VDC_DH
		lda	#$80			; palette 0, in front of BG; flips (+ X when facing left)
		sta	VDC_DL
		lda	p_wbuf + 3, y
		ldy	<p_face
		beq	!+
		eor	#$08
!:		sta	VDC_DH
		ply
		iny
		inx
		jmp	.went
.clear:		txa				; The props' and objects' entries
		clc				; follow his (enemies_draw clears what
		adc	#HUD_ENTRIES		; the last frame used beyond them all).
		sta	<satb_n
		plp
		rts

; upload_weapon - p_wbuf's cells into buffer p_buf from cell WEAPON_CELL on.
upload_weapon:	lda	<p_wcount
		beq	.r
		lda	#WEAPON_BANK
		tam3
		st0	#VDC_MAWR
		stz	VDC_DL
		lda	#>(SPR_BUF_A + WEAPON_CELL * 64)
		ldx	<p_buf
		beq	!+
		lda	#>(SPR_BUF_B + WEAPON_CELL * 64)
!:		sta	VDC_DH
		st0	#VDC_VWR
		ldx	<p_wcount
		ldy	#2			; cell byte of piece 0
.cell:		lda	p_wbuf, y		; source = $6000 + cell * 128
		lsr	a
		pha
		cla
		ror	a
		sta	ram_tia + 1
		pla
		ora	#$60
		sta	ram_tia + 2
		jsr	ram_tia
		iny
		iny
		iny
		iny
		dex
		bne	.cell
.r:		rts
