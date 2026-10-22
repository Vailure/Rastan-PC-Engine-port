; ***************************************************************************
;
; Rastan - enemies (approximate): stage 1 lizardmen and blue club throwers.
;
; Measured in the arcade (sim/scripts/lizard.txt): lizardmen enter at the right
; edge, walk at 7/8 px/frame, swing their club twice when about 56px from
; Rastan (hit lands when the club is out, 3072/12288 health), back off,
; and come again. One sword hit kills them (explosion, 10 steps x 3 frames).
;
; Blue club throwers (sim/scripts/blue.txt) walk the same way but stop 88-143 px
; away and throw two clubs (at +8 and +27 frames of a 36-frame throw). The clubs
; fly at 1.5 px/frame; one throw goes high (20 px above the thrower's anchor,
; over a standing Rastan's head), the next low (13 px above, sinking to 6 px
; above, head height). A club hit costs 3072 like a lizardman's; Rastan's sword
; knocks clubs away. They die in one hit too, with the same explosion.
;
; Coordinates are world pixels; the anchor is 16px above the floor. Slots
; 0..NUM_EN-1 hold enemies, the rest projectiles (clubs).
;
; ***************************************************************************

		include	"enemies.inc"

NUM_EN		=	4		; The arcade keeps at most 4 alive.
NUM_OBJ		=	NUM_EN + 4	; ... plus up to 4 clubs in flight.
EN_SATB_FIRST	=	7 + 24 + 4	; SATB entries after the HUD's 7, Rastan's 24, the props' 4.
EN_VRAM		=	$5C00		; Resident enemy cells.
EN_PATTERN	=	EN_VRAM >> 5

ES_FREE		=	0
ES_WALK		=	1
ES_ATTACK	=	2
ES_RETREAT	=	3
ES_DYING	=	4

EK_LIZARD	=	0		; Kinds (e_kind).
EK_BLUE		=	1
EK_CLUB		=	2

ATTACK_RANGE	=	52
RETREAT_FRAMES	=	48

		.zp
ep:		ds	2		; Pose / animation pointer scratch.
ex:		ds	2		; Scratch coordinates.
ey:		ds	2
etmp:		ds	2
spawn_timer:	ds	1
spawn_step:	ds	1		; Index into spawn_gaps.
spawn_kind:	ds	1		; Alternates lizardman / blue thrower.
rng:		ds	1
lane_best:	ds	2		; Nearest lane so far: y, distance.
en_satb:	ds	1		; Entries written this frame.
en_satb_prev:	ds	1

		.bss
e_state:	ds	NUM_OBJ
e_xl:		ds	NUM_OBJ
e_xh:		ds	NUM_OBJ
e_yl:		ds	NUM_OBJ
e_yh:		ds	NUM_OBJ
e_face:		ds	NUM_OBJ		; 0 left, 1 right.
e_animl:	ds	NUM_OBJ
e_animh:	ds	NUM_OBJ
e_animi:	ds	NUM_OBJ
e_animt:	ds	NUM_OBJ
e_animend:	ds	NUM_OBJ
e_pose:		ds	NUM_OBJ
e_timer:	ds	NUM_OBJ
e_sub:		ds	NUM_OBJ		; Speed: skip every 8th step.
e_struck:	ds	NUM_OBJ		; Club hit already checked this swing.
e_kind:		ds	NUM_OBJ
e_range:	ds	NUM_OBJ		; Attack distance.
e_alt:		ds	NUM_OBJ		; Blue: next throw is low.

		.code

; ---------------------------------------------------------------------------
; enemies_init - load cells and palettes, clear slots.

enemies_init:	; Cells -> VRAM $5C00 (enemy_cells spans banks, map 2 at $6000).
		php				; VDC writes: IRQ held off (see stream_column).
		sei
		st0	#VDC_MAWR
		st1	#<EN_VRAM
		st2	#>EN_VRAM
		st0	#VDC_VWR
		lda	#^enemy_cells
		sta	<etmp
		tam3
		inc	a
		tam4
		lda	#<enemy_cells
		sta	<ep
		lda	#>enemy_cells
		sta	<ep + 1
		ldx	#ENEMY_CELLS
.cell:		cly
.w:		lda	[ep], y
		sta	VDC_DL
		iny
		lda	[ep], y
		sta	VDC_DH
		iny
		cpy	#128
		bne	.w
		lda	<ep			; ep += 128; past $8000 remap a bank on.
		clc
		adc	#128
		sta	<ep
		bcc	!+
		inc	<ep + 1
!:		lda	<ep + 1
		cmp	#$80
		bcc	!+
		sbc	#$20
		sta	<ep + 1
		inc	<etmp
		lda	<etmp
		tam3
		inc	a
		tam4
!:		dex
		bne	.cell

		; Sprite palettes 1.. (VCE colors 272..).
		lda	#^enemy_palettes
		tam3
		lda	#$10
		sta	VCE_CTA + 0
		lda	#1
		sta	VCE_CTA + 1
		tia	enemy_palettes, VCE_CTW, ENEMY_PALS * 32
		plp

enemies_reset:	ldx	#NUM_OBJ - 1
!:		stz	e_state, x
		dex
		bpl	!-
		lda	#SPAWN_FIRST
		sta	<spawn_timer
		stz	<spawn_step
		stz	<spawn_kind
		rts

; ---------------------------------------------------------------------------
; enemies_update

enemies_update:	jsr	try_spawn
		ldx	#NUM_OBJ - 1
.loop:		lda	e_state, x
		beq	.next
		phx
		jsr	enemy_think
		plx
		lda	e_state, x
		beq	.next
		jsr	enemy_anim
		jsr	despawn_check
.next:		dex
		bpl	.loop
		rts

; try_spawn - lizardmen enter at the right edge on an enemy lane (the
; arcade's spawn marker $3A, collision bit 4, in the cell at an enemy's anchor
; height, 16 px above its floor). Of the lanes in that column the one nearest
; Rastan's height is used; no lane, no lizardman. Measured with a passive
; Rastan: the first comes 65 frames into the round, then gaps of 49, 81, 65
; frames in turn, at most 4 alive.
SPAWN_FIRST	=	65
SPAWN_X		=	276		; scroll_x + 256 + 20: just past the right edge.

try_spawn:	dec	<spawn_timer
		bne	.no
		ldx	<spawn_step		; Next gap.
		lda	spawn_gaps, x
		sta	<spawn_timer
		inx
		cpx	#3
		bcc	!+
		clx
!:		stx	<spawn_step
		ldx	#NUM_EN - 1		; Free slot?
!:		lda	e_state, x
		beq	.slot
		dex
		bpl	!-
.no:		rts
.slot:		lda	<scroll_x
		clc
		adc	#<SPAWN_X
		sta	<cx
		lda	<scroll_x + 1
		adc	#>SPAWN_X
		sta	<cx + 1
		lda	<p_y			; Rastan's row at lane height: (p_y + 8) >> 3.
		clc
		adc	#8
		sta	<etmp
		lda	<p_y + 1
		adc	#0
		lsr	a
		ror	<etmp
		lsr	a
		ror	<etmp
		lsr	a
		ror	<etmp
		lda	#$FF			; Best distance so far: none.
		sta	<lane_best + 1
		stz	<etmp + 1		; Row 0..63 down the whole column.
.scan:		lda	<etmp + 1		; cy = row * 8
		asl	a
		asl	a
		asl	a
		sta	<cy
		cla
		rol	a
		sta	<cy + 1
		phx
		jsr	coll_at
		plx
		and	#$10
		beq	.next
		lda	<etmp + 1		; |row - Rastan's row|
		sec
		sbc	<etmp
		bcs	!+
		eor	#$FF
		inc	a
!:		cmp	<lane_best + 1
		bcs	.next
		sta	<lane_best + 1
		lda	<etmp + 1
		sta	<lane_best
.next:		inc	<etmp + 1
		lda	<etmp + 1
		cmp	#64
		bcc	.scan
		lda	<lane_best + 1
		cmp	#$FF
		beq	.no
		lda	<lane_best		; Anchor = lane row * 8.
		asl	a
		asl	a
		asl	a
		sta	e_yl, x
		cla
		rol	a
		sta	e_yh, x
		lda	<cx
		sta	e_xl, x
		lda	<cx + 1
		sta	e_xh, x
		stz	e_face, x
		stz	e_sub, x
		stz	e_alt, x
		; Kind: lizardmen only before world x 1500; from there blue throwers
		; and lizardmen take turns (round 1 census, tools/object_census.py).
		cla
		ldy	<cx + 1
		cpy	#>1500
		bcc	.kind
		bne	!+
		ldy	<cx
		cpy	#<1500
		bcc	.kind
!:		lda	<spawn_kind
		eor	#1
		sta	<spawn_kind
.kind:		sta	e_kind, x
		jmp	start_walk

spawn_gaps:	db	49, 81, 65

; ---------------------------------------------------------------------------
; enemy_think - X = slot.

enemy_think:	lda	e_kind, x
		cmp	#EK_CLUB
		bne	!+
		jmp	club_think
!:		lda	e_state, x
		cmp	#ES_DYING
		bne	!+
		lda	e_animend, x		; Explosion done: free the slot.
		beq	.r
		stz	e_state, x
.r:		rts
!:		jsr	sword_vs_enemy		; Rastan's sword kills in one hit.
		bcc	!+
		lda	#ES_DYING
		sta	e_state, x
		ldy	e_kind, x
		lda	kind_death_l, y
		pha
		lda	kind_death_h, y
		tay
		pla
		jmp	enemy_set_anim
!:		lda	e_state, x
		cmp	#ES_ATTACK
		bne	!+
		jmp	.attack
!:		cmp	#ES_RETREAT
		bne	!+
		jmp	.retreat

		; --- Walk toward Rastan.
!:		jsr	face_player
		jsr	player_dist		; etmp = |p_x - e_x|, carry: |dy| small
		lda	e_kind, x
		beq	.liz_near
		; Blue: Rastan level with it or up to 64 px below (ey = dy).
		lda	<ey
		clc
		adc	#24
		sta	<ey
		lda	<ey + 1
		adc	#0
		bne	.walk
		lda	<ey
		cmp	#24 + 64
		bcs	.walk
		bra	.near
.liz_near:	bcc	.walk
.near:		lda	<etmp + 1
		bne	.walk
		lda	<etmp
		cmp	e_range, x
		bcs	.walk
		lda	#ES_ATTACK
		sta	e_state, x
		stz	e_struck, x
		stz	e_timer, x
		ldy	e_kind, x
		lda	kind_attack_l, y
		pha
		lda	kind_attack_h, y
		tay
		pla
		jmp	enemy_set_anim
.walk:		lda	e_face, x		; Step toward the facing direction.
		jmp	enemy_step

.attack:	lda	e_kind, x
		beq	.club_swing
		; Blue: clubs leave the hand 8 and 27 frames into the throw.
		inc	e_timer, x
		lda	e_timer, x
		cmp	#8
		beq	.throw
		cmp	#27
		bne	.wait
.throw:		jsr	throw_club
		bra	.wait

.club_swing:	; The club is out in pose 6: hit Rastan once per swing if in range.
		lda	e_pose, x
		cmp	#6
		bne	.armed
		lda	e_struck, x
		bne	.wait
		inc	e_struck, x
		jsr	player_dist
		bcc	.wait
		lda	<etmp + 1
		bne	.wait
		lda	<etmp
		cmp	#ATTACK_RANGE + 8
		bcs	.wait
		phx
		lda	e_face, x		; Knock Rastan the way the club swings.
		beq	!+
		lda	#1
		bra	.hit
!:		lda	#$FF
.hit:		jsr	player_hit
		plx
		bra	.wait
.armed:		stz	e_struck, x
.wait:		lda	e_animend, x
		beq	.r2
		lda	e_alt, x		; Blue: high and low throws alternate.
		eor	#1
		sta	e_alt, x
		lda	#ES_RETREAT
		sta	e_state, x
		lda	#RETREAT_FRAMES
		sta	e_timer, x
		ldy	e_kind, x
		lda	kind_retreat_l, y
		pha
		lda	kind_retreat_h, y
		tay
		pla
		jmp	enemy_set_anim
.r2:		rts

.retreat:	dec	e_timer, x		; Back off, still facing Rastan.
		bne	!+
		jmp	start_walk
!:		jsr	face_player
		lda	e_face, x
		eor	#1
		jmp	enemy_step

; start_walk - X = slot: walk toward Rastan with this kind's walk and range.
start_walk:	lda	#ES_WALK
		sta	e_state, x
		ldy	e_kind, x
		lda	kind_range, y
		sta	e_range, x
		cpy	#EK_BLUE		; Blue: 88 + 0..55.
		bne	!+
		jsr	rand
		and	#$1F
		sta	<etmp
		jsr	rand
		and	#$17
		clc
		adc	<etmp
		adc	e_range, x
		sta	e_range, x
		ldy	e_kind, x
!:		lda	kind_walk_l, y
		pha
		lda	kind_walk_h, y
		tay
		pla
		jmp	enemy_set_anim

; rand - A = next value of an 8-bit LFSR (X, Y kept).
rand:		lda	<rng
		bne	!+
		lda	#$A5
!:		asl	a
		bcc	!+
		eor	#$1D
!:		sta	<rng
		rts

; Per-kind data: lizardman, blue thrower, club.
kind_walk_l:	db	<anim_liz_walk, <anim_blue_walk, <anim_club
kind_walk_h:	db	>anim_liz_walk, >anim_blue_walk, >anim_club
kind_attack_l:	db	<anim_liz_attack, <anim_blue_throw, 0
kind_attack_h:	db	>anim_liz_attack, >anim_blue_throw, 0
kind_retreat_l:	db	<anim_liz_walk, <anim_blue_walk2, 0
kind_retreat_h:	db	>anim_liz_walk, >anim_blue_walk2, 0
kind_death_l:	db	<anim_liz_death, <anim_blue_death, 0
kind_death_h:	db	>anim_liz_death, >anim_blue_death, 0
kind_range:	db	ATTACK_RANGE, 88, 0
kind_top:	db	36, 48, 8		; Body box: anchor - top .. anchor + 16,
kind_half:	db	16, 16, 8		; x +/- half (club: +/- 8 around its centre).

; ---------------------------------------------------------------------------
; throw_club - X = blue thrower: a club leaves its hand toward Rastan.
CLUB_DX		=	23			; Measured: hand 23 px ahead of the anchor.

throw_club:	ldy	#NUM_OBJ - 1		; Free projectile slot?
!:		lda	e_state, y
		beq	.slot
		dey
		cpy	#NUM_EN
		bcs	!-
		rts
.slot:		lda	e_face, x
		sta	e_face, y
		lda	e_face, x		; x = e_x -/+ 23
		bne	.right
		lda	e_xl, x
		sec
		sbc	#CLUB_DX
		sta	e_xl, y
		lda	e_xh, x
		sbc	#0
		sta	e_xh, y
		bra	.y
.right:		lda	e_xl, x
		clc
		adc	#CLUB_DX
		sta	e_xl, y
		lda	e_xh, x
		adc	#0
		sta	e_xh, y
.y:		lda	#20			; High: anchor - 20, straight.
		sta	<etmp
		lda	#0
		sta	e_timer, y
		lda	e_alt, x
		beq	!+
		lda	#13			; Low: anchor - 13, sinking 7 px.
		sta	<etmp
		lda	#7
		sta	e_timer, y
!:		lda	e_yl, x
		sec
		sbc	<etmp
		sta	e_yl, y
		lda	e_yh, x
		sbc	#0
		sta	e_yh, y
		lda	#EK_CLUB
		sta	e_kind, y
		lda	#0
		sta	e_sub, y
		phx
		tya
		tax
		jsr	start_walk
		plx
		rts

; club_think - X = club: fly 1.5 px/frame, hurt Rastan, break on his sword.
club_think:	jsr	sword_vs_enemy
		bcc	!+
		stz	e_state, x
		rts
!:		inc	e_sub, x		; 1, 2, 1, 2 ... px
		lda	e_sub, x
		and	#1
		inc	a
		sta	<etmp
		lda	e_face, x
		bne	.right
		lda	e_xl, x
		sec
		sbc	<etmp
		sta	e_xl, x
		bcs	.sink
		dec	e_xh, x
		bra	.sink
.right:		lda	e_xl, x
		clc
		adc	<etmp
		sta	e_xl, x
		bcc	.sink
		inc	e_xh, x
.sink:		lda	e_timer, x		; Low clubs sink 1 px every other frame.
		beq	.hit
		lda	e_sub, x
		and	#1
		beq	.hit
		dec	e_timer, x
		inc	e_yl, x
		bne	.hit
		inc	e_yh, x
.hit:		; Rastan's body: p_x +/- 12, p_y - 24 (crouched: - 6) .. p_y + 24.
		; The club (16x16, centred) hits if it overlaps.
		lda	e_xl, x			; |e_x - p_x| < 20
		sec
		sbc	<p_x
		sta	<ex
		lda	e_xh, x
		sbc	<p_x + 1
		bpl	!+
		eor	#$FF			; Negate (16-bit).
		pha
		lda	<ex
		eor	#$FF
		clc
		adc	#1
		sta	<ex
		pla
		adc	#0
!:		bne	.r
		lda	<ex
		cmp	#20
		bcs	.r
		lda	e_yl, x			; dy = e_y - p_y + 32 must be 0 .. 63
		sec				; (crouched: 18 .. 63)
		sbc	<p_y
		sta	<ey
		lda	e_yh, x
		sbc	<p_y + 1
		sta	<ey + 1
		lda	<ey
		clc
		adc	#32
		sta	<ey
		lda	<ey + 1
		adc	#0
		bne	.r
		lda	<ey
		cmp	#64
		bcs	.r
		ldy	<p_state
		cpy	#ST_CROUCH
		beq	.low
		cpy	#ST_CATK
		bne	.hurt
.low:		cmp	#18
		bcc	.r
.hurt:		phx
		lda	e_face, x
		beq	!+
		lda	#1
		bra	!++
!:		lda	#$FF
!:		jsr	player_hit
		plx
.gone:		stz	e_state, x
.r:		rts

; face_player - e_face = Rastan is to the right.
face_player:	lda	<p_x
		cmp	e_xl, x
		lda	<p_x + 1
		sbc	e_xh, x
		bcc	.left
		lda	#1
		sta	e_face, x
		rts
.left:		stz	e_face, x
		rts

; player_dist - etmp = |p_x - e_x|, ey = p_y + 8 - e_y; carry set if Rastan's
; anchor is within 24px vertically (it is 8px above a lizardman's on flat ground).
player_dist:	lda	<p_x
		sec
		sbc	e_xl, x
		sta	<etmp
		lda	<p_x + 1
		sbc	e_xh, x
		sta	<etmp + 1
		bpl	!+
		lda	<etmp			; Negate.
		eor	#$FF
		clc
		adc	#1
		sta	<etmp
		lda	<etmp + 1
		eor	#$FF
		adc	#0
		sta	<etmp + 1
!:		lda	<p_y			; dy = p_y + 8 - e_y
		clc
		adc	#8
		sta	<ey
		lda	<p_y + 1
		adc	#0
		sta	<ey + 1
		lda	<ey
		sec
		sbc	e_yl, x
		sta	<ey
		lda	<ey + 1
		sbc	e_yh, x
		sta	<ey + 1			; (ey = dy, for callers)
		bmi	.neg
		bne	.far
		lda	<ey			; 0 <= dy < 24
		cmp	#24
		bcs	.far
		sec
		rts
.neg:		cmp	#$FF			; -24 < dy < 0
		bne	.far
		lda	<ey
		cmp	#$E9
		bcc	.far
		sec
		rts
.far:		clc
		rts

; enemy_step - move one pixel in direction A (0 left, 1 right), skipping
; every 8th step (7/8 px/frame); stop at walls and ledges.
enemy_step:	pha
		inc	e_sub, x
		lda	e_sub, x
		and	#7
		bne	!+
		pla
		rts
!:		; Probe x = e_x +/- 12.
		pla
		pha
		lda	e_xl, x
		sta	<cx
		lda	e_xh, x
		sta	<cx + 1
		pla
		pha
		bne	.r
		lda	<cx
		sec
		sbc	#12
		sta	<cx
		bcs	.probe
		dec	<cx + 1
		bra	.probe
.r:		lda	<cx
		clc
		adc	#12
		sta	<cx
		bcc	.probe
		inc	<cx + 1
.probe:		; Wall: solid at anchor - 8.
		lda	e_yl, x
		sec
		sbc	#8
		sta	<cy
		lda	e_yh, x
		sbc	#0
		sta	<cy + 1
		phx
		jsr	coll_at
		plx
		and	#$0F
		cmp	#1
		beq	.blocked
		; Ledge: floor at anchor + 17.
		lda	e_yl, x
		clc
		adc	#17
		sta	<cy
		lda	e_yh, x
		adc	#0
		sta	<cy + 1
		phx
		jsr	coll_at
		jsr	is_floor
		plx
		bcc	.blocked
		pla
		bne	.right
		lda	e_xl, x
		bne	!+
		dec	e_xh, x
!:		dec	e_xl, x
		rts
.right:		inc	e_xl, x
		bne	!+
		inc	e_xh, x
!:		rts
.blocked:	pla
		rts

; sword_vs_enemy - carry set if Rastan's sword box overlaps this object's
; body (x - half .. x + half, y - top .. y + 16; kind_half, kind_top).
sword_vs_enemy:	phx
		jsr	sword_box
		plx
		bcs	!+
		rts
!:		ldy	e_kind, x
		; sb_x0 <= e_x + half ?
		lda	e_xl, x
		clc
		adc	kind_half, y
		sta	<ex
		lda	e_xh, x
		adc	#0
		sta	<ex + 1
		lda	<ex
		cmp	<sb_x0
		lda	<ex + 1
		sbc	<sb_x0 + 1
		bmi	.no
		; e_x - half <= sb_x1 ?
		lda	e_xl, x
		sec
		sbc	kind_half, y
		sta	<ex
		lda	e_xh, x
		sbc	#0
		sta	<ex + 1
		lda	<sb_x1
		cmp	<ex
		lda	<sb_x1 + 1
		sbc	<ex + 1
		bmi	.no
		; sb_y0 <= e_y + 16 ?
		lda	e_yl, x
		clc
		adc	#16
		sta	<ey
		lda	e_yh, x
		adc	#0
		sta	<ey + 1
		lda	<ey
		cmp	<sb_y0
		lda	<ey + 1
		sbc	<sb_y0 + 1
		bmi	.no
		; e_y - top <= sb_y1 ?
		lda	e_yl, x
		sec
		sbc	kind_top, y
		sta	<ey
		lda	e_yh, x
		sbc	#0
		sta	<ey + 1
		lda	<sb_y1
		cmp	<ey
		lda	<sb_y1 + 1
		sbc	<ey + 1
		bmi	.no
		sec
		rts
.no:		clc
		rts

; despawn_check - free enemies that drift far off-screen.
despawn_check:	lda	e_state, x
		cmp	#ES_DYING
		beq	.ok
		lda	e_xl, x			; x - scroll_x
		sec
		sbc	<scroll_x
		sta	<ex
		lda	e_xh, x
		sbc	<scroll_x + 1
		bmi	.left
		bne	.far			; >= 256 + 256
		rts
.left:		cmp	#$FF			; < -256
		bne	.free
		lda	<ex
		cmp	#$C0			; < -64
		bcs	.ok
.free:		stz	e_state, x
.ok:		rts
.far:		cmp	#2
		bcc	.ok
		stz	e_state, x
		rts

; ---------------------------------------------------------------------------
; Animation (same format as Rastan's: pose, frames; $FF end; 0 = hold).

; enemy_set_anim - A/Y = list, X = slot.
enemy_set_anim:	sta	e_animl, x
		sta	<ep
		tya
		sta	e_animh, x
		sta	<ep + 1
		stz	e_animi, x
		stz	e_animend, x
		lda	[ep]
		sta	e_pose, x
		ldy	#1
		lda	[ep], y
		sta	e_animt, x
		rts

; enemy_anim - advance one frame. Walking loops; others report the end.
enemy_anim:	lda	e_animt, x
		beq	.done
		dec	e_animt, x
		bne	.done
		lda	e_animl, x
		sta	<ep
		lda	e_animh, x
		sta	<ep + 1
		lda	e_animi, x
		clc
		adc	#2
		sta	e_animi, x
		tay
		lda	[ep], y
		cmp	#$FF
		bne	.set
		lda	e_state, x
		cmp	#ES_WALK
		beq	.loop
		cmp	#ES_RETREAT
		beq	.loop
		lda	#1
		sta	e_animend, x
		sta	e_animt, x
		lda	e_animi, x
		sec
		sbc	#2
		sta	e_animi, x
		rts
.loop:		stz	e_animi, x
		cly
		lda	[ep], y
.set:		sta	e_pose, x
		iny
		lda	[ep], y
		sta	e_animt, x
.done:		rts

; ---------------------------------------------------------------------------
; enemies_draw - SATB entries from EN_SATB_FIRST, after player_draw.

enemies_draw:	php				; VDC writes: IRQ held off (see stream_column).
		sei
		st0	#VDC_MAWR
		lda	#<(SATB_ADDR + EN_SATB_FIRST * 4)
		sta	VDC_DL
		lda	#>(SATB_ADDR + EN_SATB_FIRST * 4)
		sta	VDC_DH
		st0	#VDC_VWR
		stz	<en_satb
		ldx	#NUM_OBJ - 1
.slot:		lda	e_state, x
		beq	.next
		phx
		jsr	draw_one
		plx
.next:		dex
		bpl	.slot
		; Clear entries the last frame used beyond this frame's.
		lda	<en_satb
.clr:		cmp	<en_satb_prev
		bcs	.end
		st1	#0
		st2	#0
		st1	#0
		st2	#0
		st1	#0
		st2	#0
		st1	#0
		st2	#0
		inc	a
		bra	.clr
.end:		lda	<en_satb
		sta	<en_satb_prev
		plp
		rts

; draw_one - X = slot. Pieces were captured facing left (arcade X flip set);
; facing right mirrors dx (-dx - 16) and toggles the flip.
draw_one:	lda	e_pose, x
		asl	a
		tay
		lda	epose_table, y
		sta	<ep
		lda	epose_table + 1, y
		sta	<ep + 1
		; Screen anchor: ex = e_x - scroll_x, ey = e_y - scroll_y.
		lda	e_xl, x
		sec
		sbc	<scroll_x
		sta	<ex
		lda	e_xh, x
		sbc	<scroll_x + 1
		sta	<ex + 1
		lda	e_yl, x
		sec
		sbc	<scroll_y
		sta	<ey
		lda	e_yh, x
		sbc	<scroll_y + 1
		sta	<ey + 1
		lda	e_face, x
		sta	<etmp + 1
		lda	[ep]
		sta	<etmp			; piece count
		ldy	#1
.piece:		lda	<en_satb
		cmp	#64 - EN_SATB_FIRST
		bcs	.done			; Out of SATB entries.
		jsr	piece_pos		; cy = screen x, ctx = screen y; carry = visible
		bcc	.skip
		jsr	emit_piece
		bra	.next
.skip:		iny				; skip cell, attr
		iny
.next:		dec	<etmp
		bne	.piece
.done:		rts

; piece_pos - read dx, dy at [ep],y (y advanced past them); compute screen
; position; carry set if the piece is at least partly on screen.
piece_pos:	lda	[ep], y			; dx, mirrored when facing right
		iny
		ldx	<etmp + 1
		beq	!+
		eor	#$FF
		sec
		sbc	#15
!:		jsr	.sadd_ex
		sta	<cy
		stx	<cy + 1
		lda	[ep], y			; dy
		iny
		jsr	.sadd_ey
		sta	<ctx
		stx	<ctx + 1
		; Visible if -16 < x < 256 and -16 < y < 240.
		lda	<cy + 1
		beq	.xok
		cmp	#$FF
		bne	.no
		lda	<cy
		cmp	#$F1
		bcc	.no
.xok:		lda	<ctx + 1
		beq	.yok
		cmp	#$FF
		bne	.no
		lda	<ctx
		cmp	#$F1
		bcc	.no
		sec
		rts
.yok:		lda	<ctx
		cmp	#240
		bcs	.no
		sec
		rts
.no:		clc
		rts
.sadd_ex:	pha				; A (signed) + ex -> A/X
		clc
		adc	<ex
		tax
		pla
		and	#$80
		beq	!+
		lda	#$FF
!:		adc	<ex + 1
		sax
		rts
.sadd_ey:	pha
		clc
		adc	<ey
		tax
		pla
		and	#$80
		beq	!+
		lda	#$FF
!:		adc	<ey + 1
		sax
		rts

; emit_piece - write one SATB entry from cy/ctx and the cell/attr at [ep],y.
emit_piece:	lda	<ctx			; y + 64
		clc
		adc	#64
		sta	VDC_DL
		lda	<ctx + 1
		adc	#0
		and	#$03
		sta	VDC_DH
		lda	<cy			; x + 32
		clc
		adc	#32
		sta	VDC_DL
		lda	<cy + 1
		adc	#0
		and	#$03
		sta	VDC_DH
		lda	[ep], y			; pattern = EN_PATTERN + cell * 2
		iny
		asl	a
		sta	<cx
		cla
		rol	a
		sta	<cx + 1
		lda	<cx
		clc
		adc	#<EN_PATTERN
		sta	VDC_DL
		lda	<cx + 1
		adc	#>EN_PATTERN
		sta	VDC_DH
		lda	[ep], y			; attr: palette | in front
		and	#$0F
		ora	#$80
		sta	VDC_DL
		lda	[ep], y			; X flip (toggled when facing right), Y flip
		iny
		and	#$40
		beq	!+
		lda	#$08
!:		ldx	<etmp + 1
		beq	!+
		eor	#$08
!:		sta	<cx
		dey
		lda	[ep], y
		iny
		and	#$80
		ora	<cx
		sta	VDC_DH
		inc	<en_satb
		rts
