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

SPR_BUF_A	=	$5000		; Two pattern buffers, 24 cells each.
SPR_BUF_B	=	$5600
MAX_CELLS	=	24

; States.
ST_STAND	=	0
ST_WALK		=	1
ST_CROUCH	=	2
ST_AIR		=	3
ST_ATTACK	=	4
ST_CATK		=	5
ST_CLIMB	=	6

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
p_jatk:		ds	1		; Air attack: 0 none, 1 swing/up thrust, 2 down thrust.
p_pose:		ds	1
p_pose_up:	ds	1		; Pose currently uploaded ($FF none).
p_buf:		ds	1		; 0: buffer A shows, 1: B.
p_ncells:	ds	1
p_hold:		ds	1
p_nograb:	ds	1		; Frames before a rope can be caught again.		; Freeze the animation (climbing, not moving).
p_prev_cells:	ds	1
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
		stz	<p_prev_cells
		lda	#$FF
		sta	<p_pose_up
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
		lda	joynow
		sta	<pad
		lda	joytrg
		sta	<padtrg

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

; --- Standing / walking.
st_ground:	bbr0	<padtrg, .no_jump	; JOY_B1: jump.
		jmp	start_jump
.no_jump:	bbr1	<padtrg, .no_atk	; JOY_B2: attack.
		bbr6	<pad, .stand_atk	; JOY_D held: crouch attack.
		jmp	enter_catk
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
!:		bbr7	<pad, !+
		lda	#1
		sta	<p_face
!:		rts

; --- Standing attack: no movement until the swing ends.
st_attack:	lda	<p_animend
		beq	!+
		jmp	enter_stand
!:		rts

st_catk:	lda	<p_animend
		beq	!+
		jmp	enter_crouch
!:		rts

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
.not_down:	inc	<p_jatk			; UP: up thrust, else swing.
		bbr4	<pad, .swing
		lda	#<anim_uthrust
		ldx	#>anim_uthrust
		jsr	set_anim
		bra	.no_atk
.swing:		lda	#<anim_jatk
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
.done:		; Fell below the map: restart the stage.
		lda	<p_y + 1
		cmp	#2
		bcc	!+
		jmp	stage_start
!:		rts

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
		and	#$7F
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
		and	#$7F
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

enter_attack:	lda	#ST_ATTACK
		sta	<p_state
		lda	#<anim_attack
		ldx	#>anim_attack
		jmp	set_anim

enter_catk:	lda	#ST_CATK
		sta	<p_state
		lda	#<anim_catk
		ldx	#>anim_catk
		jmp	set_anim

; start_jump: UP held = high jump; a direction held = forward jump.
start_jump:	stz	<p_jdir
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

player_init_pos:
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

; move_up - dy (negative) pixels up. Rastan jumps through platforms.
move_up:	lda	<p_y
		bne	!+
		dec	<p_y + 1
!:		dec	<p_y
		inc	<dy
		bne	move_up
		rts

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
		and	#$7F
		cmp	#1
		beq	.blocked
		dex
		bpl	.loop
		clc
		rts
.blocked:	sec
		rts
.heights:	db	20, 4, -12, -28

; is_floor - carry set if collision code A is something to stand on.
is_floor:	and	#$7F
		cmp	#8
		bcs	.no
		tax
		lda	.tab, x
		lsr	a
		rts
.no:		clc
		rts
.tab:		db	0, 1, 0, 1, 1, 0, 0, 1

; coll_at - collision code at world (cx, cy); 0 outside the map, 1 past
; the end of the stage. Data (MPR5 $A000): 16 bytes per block column, then
; 16-byte 4x4 patterns at COLL_PATTERNS.
coll_at:	lda	<cy + 1
		cmp	#2			; Also rejects negative ($FF).
		bcs	.empty
		sta	<ctx + 1
		lda	<cy			; cty = cy >> 3
		lsr	<ctx + 1
		ror	a
		lsr	<ctx + 1
		ror	a
		lsr	<ctx + 1
		ror	a
		sta	<cty
		lda	<cx + 1			; ctx = cx >> 3
		bmi	.empty
		sta	<ctx + 1
		lda	<cx
		lsr	<ctx + 1
		ror	a
		lsr	<ctx + 1
		ror	a
		lsr	<ctx + 1
		ror	a
		sta	<ctx
		and	#$FC			; cp = (ctx & ~3) << 2 = block column * 16
		sta	<cp
		lda	<ctx + 1
		sta	<cp + 1
		asl	<cp
		rol	<cp + 1
		asl	<cp
		rol	<cp + 1
		lda	<cp + 1
		cmp	#>(COLL_PATTERNS)	; Past the last block column?
		bcs	.solid
		lda	<cty
		lsr	a
		lsr	a
		ora	<cp
		sta	<cp
		lda	<cp + 1
		ora	#$A0
		sta	<cp + 1
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
		rts
.empty:		cla
		rts
.solid:		lda	#1
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
; Camera: scroll forward when Rastan passes screen x 136; keep his feet
; between screen y 80 and 176.

camera_update:	lda	<p_x			; tmp = p_x - 136
		sec
		sbc	#136
		sta	<ctx
		lda	<p_x + 1
		sbc	#0
		sta	<ctx + 1
		bmi	.vert
		cmp	<scroll_x + 1		; if tmp > scroll_x: scroll_x = tmp
		bcc	.vert
		bne	.setx
		lda	<ctx
		cmp	<scroll_x
		bcc	.vert
		beq	.vert
.setx:		lda	<ctx			; Clamp to MAX_SCROLL_X.
		sta	<scroll_x
		lda	<ctx + 1
		sta	<scroll_x + 1
		cmp	#>MAX_SCROLL_X
		bcc	.vert
		bne	.clampx
		lda	<scroll_x
		cmp	#<MAX_SCROLL_X
		bcc	.vert
.clampx:	lda	#<MAX_SCROLL_X
		sta	<scroll_x
		lda	#>MAX_SCROLL_X
		sta	<scroll_x + 1

.vert:		; feet = p_y + 24; low = feet - 176, high = feet - 80.
		lda	<p_y
		clc
		adc	#<(24 - 176)
		sta	<ctx
		lda	<p_y + 1
		adc	#>(24 - 176)
		sta	<ctx + 1		; scroll_y must be >= ctx
		bmi	.lowok
		cmp	<scroll_y + 1
		bcc	.lowok
		bne	.sety_low
		lda	<ctx
		cmp	<scroll_y
		bcc	.lowok
		beq	.lowok
.sety_low:	lda	<ctx
		sta	<scroll_y
		lda	<ctx + 1
		sta	<scroll_y + 1
.lowok:		lda	<p_y			; scroll_y must be <= feet - 80
		clc
		adc	#<(24 - 80)
		sta	<ctx
		lda	<p_y + 1
		adc	#>(24 - 80)
		sta	<ctx + 1
		bpl	!+
		stz	<ctx			; Clamp at 0.
		stz	<ctx + 1
!:		lda	<scroll_y + 1
		cmp	<ctx + 1
		bcc	.clampy
		bne	.sety_high
		lda	<scroll_y
		cmp	<ctx
		bcc	.clampy
		beq	.clampy
.sety_high:	lda	<ctx
		sta	<scroll_y
		lda	<ctx + 1
		sta	<scroll_y + 1
.clampy:	lda	<scroll_y + 1		; Clamp to MAX_SCROLL_Y.
		beq	.done
		lda	<scroll_y
		cmp	#<MAX_SCROLL_Y
		bcc	.done
		lda	#<MAX_SCROLL_Y
		sta	<scroll_y
.done:		rts

; ---------------------------------------------------------------------------
; player_draw - upload a new pose into the idle buffer, then write the SATB.
; Runs after the frame's logic; the SATB DMA at the next VBLANK picks it up,
; together with the scroll registers written then.

player_draw:	jsr	anim_tick
		; Map the pose record (pose table at the start of player_data).
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

		lda	<p_pose
		cmp	<p_pose_up
		beq	.satb
		sta	<p_pose_up
		lda	<p_buf			; Upload into the hidden buffer.
		eor	#1
		sta	<p_buf
		st0	#VDC_MAWR
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

.satb:		; SATB entries 0..ncells-1, then clear what the last pose used.
		st0	#VDC_MAWR
		lda	#<SATB_ADDR
		sta	VDC_DL
		lda	#>SATB_ADDR
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
		jmp	.clear
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
.clear:		cpx	<p_prev_cells		; Zero leftover entries.
		bcs	.end
		st1	#0
		st2	#0
		st1	#0
		st2	#0
		st1	#0
		st2	#0
		st1	#0
		st2	#0
		inx
		bra	.clear
.end:		lda	<p_ncells
		sta	<p_prev_cells
		rts
