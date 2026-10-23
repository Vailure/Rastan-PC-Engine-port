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

		include	"objects.inc"

NUM_EN		=	4		; Slots 0-3: walkers (the arcade keeps at most 4 alive),
					; 4: item, 5: its bat, 6-8: specials (boulders, ...),
NUM_BIG		=	9		; 9-16: projectiles.
NUM_OBJ		=	NUM_BIG + 8
; SATB: the HUD's 12 entries, then Rastan's, the props' and the objects', packed
; (satb_n: the next free one), so that a frame where Rastan needs few cells
; leaves the rest to the objects.
EN_VRAM		=	$5C00		; Object cell buffers, $5C00-$76BF (107 cells):
WALK_CELLS	=	11		; walkers,
ITEM_CELLS	=	4		; item and bat,
SPEC_CELLS	=	13		; specials (the gargoyle's wings take 13),
PROJ_CELLS	=	2		; projectiles.
EN_VRAM_END	=	EN_VRAM + (4 * WALK_CELLS + 2 * ITEM_CELLS + 3 * SPEC_CELLS + 8 * PROJ_CELLS) * 64
UPLOAD_BUDGET	=	14		; Cells uploaded per VBLANK (about 11k cycles).

ES_FREE		=	0
ES_WALK		=	1
ES_ATTACK	=	2
ES_RETREAT	=	3
ES_DYING	=	4
ES_HIDDEN	=	5		; Thinks but is not drawn.

EK_LIZARD	=	0		; Kinds (e_kind).
EK_BLUE		=	1
EK_CLUB		=	2
EK_ITEM		=	3		; A weapon item (slot ITEM_SLOT),
EK_BAT		=	4		; and the bat that comes with it (BAT_SLOT).
EK_CHIM		=	5		; Chimera,
EK_FIRE		=	6		; and its fireballs.
EK_ROCK		=	7		; Boulder.
EK_GARG		=	8		; Gargoyle: body,
EK_WINGS	=	9		; and wings.
EK_WOMAN	=	10		; The woman warrior.
EK_SWORD	=	11		; Castle soldiers: sword,
EK_MACE		=	12		; mace.
EK_JET		=	13		; Fire jet.
EK_BOSS		=	14		; The boss: its first 13 pieces (thinks),
EK_BOSS2	=	15		; the rest (follows),
EK_FRAG		=	16		; and its fire.
EK_VINE		=	17		; A swinging vine.
SOLDIER_RANGE	=	60

ITEM_SLOT	=	NUM_EN		; Big slots after the walkers'.
BAT_SLOT	=	NUM_EN + 1

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
lane_top:	ds	1		; High byte of the top of Rastan's 512 px square.
en_satb:	ds	1		; Entries written this frame.
en_satb_prev:	ds	1		; SATB entries in use at the end of the last frame.
en_cap:		ds	1		; Entries left for the objects this frame.
satb_n:		ds	1		; Next free SATB entry (player_draw, props_draw).
en_rot:		ds	1		; The walkers' drawing order turns (enemies_draw).
en_wk:		ds	1
en_full:	ds	1		; Pieces left undrawn for want of SATB entries.
up_left:	ds	1		; objects_upload: cells left this VBLANK,
up_next:	ds	1		; slot to start from next time,
up_count:	ds	1		; slots left to look at.
up_piece:	ds	1
dr_pat:		ds	2		; draw_one: pattern of the next piece.

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
e_shown:	ds	NUM_OBJ		; Pose whose cells are in the slot's buffer ($FF none).
e_plan:		ds	NUM_OBJ		; Pose its buffer will hold next frame (enemies_draw).
items_done:	ds	1		; Items spawned this life (bit per item).
rocks_done:	ds	1		; Boulders spawned this life.
gargs_done:	ds	1		; Gargoyles spawned this life.
woman_done:	ds	1		; The woman warrior spawned this life.
jet_wait:	ds	3		; Frames before each fire jet may erupt again.
vines_done:	ds	1		; Vines present (bits, vines.asm).
trap_t:		ds	1		; The floor spears' clock (traps.asm).
vine_t:		ds	1		; The vines' swing clock (vines.asm).
boss_done:	ds	1		; The boss has come this life.
boss_clear:	ds	1		; Frames to the round clear (0: not counting).
ram_tia:	ds	8		; tia src, VDC_DL, 128 / rts (source patched per cell).

		.code

; ---------------------------------------------------------------------------
; enemies_init - load cells and palettes, clear slots.

enemies_init:	lda	#64			; (the first frame clears every entry
		sta	<en_satb_prev		; after the HUD's and Rastan's)
		lda	#HUD_ENTRIES
		sta	<satb_n
		ldx	#7			; The RAM copy of "tia cell, VDC_DL, 128".
!:		lda	.tia, x
		sta	ram_tia, x
		dex
		bpl	!-
		jsr	enemies_load
		jmp	enemies_reset
.tia:		db	$E3			; tia
		dw	$6000			; (source: the cell, mapped in MPR3)
		dw	VDC_DL
		dw	128
		db	$60			; rts

; enemies_load - the objects' sprite palettes (cells come with each pose):
; the arcade's colour bank 48, or with obj_b64 set its bank 64 (a restart at
; checkpoint 4 or 5: tools/object_specs.py GROUP_BANK).
enemies_load:	jsr	traps_load
		php
		sei
		lda	#^obj_palettes
		tam3
		lda	#<obj_palettes
		sta	<ep
		lda	#>obj_palettes
		sta	<ep + 1
		lda	obj_b64
		beq	!+
		lda	#<obj_palettes_b64
		sta	<ep
		lda	#>obj_palettes_b64
		sta	<ep + 1
!:		clx
.pal:		lda	obj_pal_slots, x	; VCE address 256 + slot * 16
		asl	a
		asl	a
		asl	a
		asl	a
		sta	VCE_CTA + 0
		lda	#1
		adc	#0
		sta	VCE_CTA + 1
		cly
!:		lda	[ep], y
		sta	VCE_CTW + 0
		iny
		lda	[ep], y
		sta	VCE_CTW + 1
		iny
		cpy	#32
		bne	!-
		lda	<ep
		clc
		adc	#32
		sta	<ep
		bcc	!+
		inc	<ep + 1
!:		inx
		cpx	#OBJ_PAL_COUNT
		bne	.pal
		plp
		; (fall through: the cells in the buffers must be uploaded again)

; obj_invalidate - forget what is in the slot buffers (the debug menu borrows them).
obj_invalidate:	lda	#$FF
		ldx	#NUM_OBJ - 1
!:		sta	e_shown, x
		dex
		bpl	!-
		rts

enemies_reset:	ldx	#NUM_OBJ - 1
!:		stz	e_state, x
		lda	#$FF
		sta	e_shown, x
		dex
		bpl	!-
		stz	items_done
		stz	rocks_done
		stz	gargs_done
		stz	woman_done
		stz	jet_wait
		stz	boss_done
		stz	boss_clear
		stz	jet_wait + 1
		stz	jet_wait + 2
		stz	vines_done
		stz	trap_t
		stz	vine_t
		lda	#SPAWN_FIRST
		sta	<spawn_timer
		stz	<spawn_step
		stz	<spawn_kind
		rts

; ---------------------------------------------------------------------------
; enemies_update

enemies_update:	lda	<dbg_noenemy		; Debug menu: no walkers (items still come).
		bne	!+
		jsr	try_spawn
!:		jsr	item_spawn
		jsr	rock_spawn
		jsr	garg_spawn
		jsr	woman_spawn
		jsr	jets_spawn
		jsr	vines_tick
		jsr	vines_spawn
		jsr	traps_update
		lda	<bg_set			; In the castle: the first room's hanging
		beq	!+			; column (src/column.asm).
		jsr	column_update
		jsr	wall_update		; (and the lava hall's sealing wall)
		jsr	weights_update		; (and shaft 2's spiked weights)
!:		jsr	boss_spawn
		lda	boss_clear		; The boss is dead: the round is clear soon.
		beq	!+
		dec	boss_clear
		bne	!+
		jmp	round_clear
!:		ldx	#NUM_OBJ - 1
.loop:		lda	e_state, x
		beq	.next
		jsr	map_kind		; Its group's poses and anims at $8000.
		phx
		jsr	enemy_think
		plx
		lda	e_state, x
		beq	.next
		jsr	map_kind		; (think may have changed it)
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
		lda	<p_y			; Rastan's row at lane height in his 512 px
		clc				; square: ((p_y + 8) & 511) >> 3; the
		adc	#8			; square's top y: lane_top.
		sta	<etmp
		lda	<p_y + 1
		adc	#0
		pha
		and	#$FE
		sta	<lane_top
		pla
		lsr	a
		ror	<etmp
		lsr	<etmp
		lsr	<etmp
		lda	#$FF			; Best distance so far: none.
		sta	<lane_best + 1
		stz	<etmp + 1		; Row 0..63 down the whole column.
.scan:		lda	<etmp + 1		; cy = top + row * 8
		asl	a
		asl	a
		asl	a
		sta	<cy
		cla
		rol	a
		ora	<lane_top
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
		lda	<lane_best		; Anchor = top + lane row * 8.
		asl	a
		asl	a
		asl	a
		sta	e_yl, x
		cla
		rol	a
		ora	<lane_top
		sta	e_yh, x
		lda	<cx
		sta	e_xl, x
		lda	<cx + 1
		sta	e_xh, x
		stz	e_face, x
		stz	e_sub, x
		stz	e_alt, x
		; Kind (round 1 census, tools/census_all.py): lizardmen only before
		; world x 1500; then blue throwers and lizardmen take turns; from
		; x 2400 throwers, chimeras and lizardmen in turn; in the castle (x 8200)
		; sword and mace soldiers.
		cla
		ldy	<cx + 1
		cpy	#>1500
		bcc	.kind
		bne	!+
		ldy	<cx
		cpy	#<1500
		bcc	.kind
!:		ldy	<spawn_kind
		iny
		lda	<cx			; x >= 8200 (the castle): sword and mace soldiers.
		cmp	#<8200
		lda	<cx + 1
		sbc	#>8200
		bcc	!+
		cpy	#2
		bcc	.castle
		cly
.castle:	sty	<spawn_kind
		lda	spawn_castle, y
		bra	.kind
!:		lda	<cx			; x >= 2400: a cycle of 3.
		cmp	#<2400
		lda	<cx + 1
		sbc	#>2400
		bcs	.three
		cpy	#2
		bcc	!+
		cly
!:		sty	<spawn_kind
		lda	spawn_two, y
		bra	.kind
.three:		cpy	#3
		bcc	!+
		cly
!:		sty	<spawn_kind
		lda	spawn_three, y
.kind:		sta	e_kind, x
		lda	#$FF
		sta	e_shown, x
		jmp	start_walk

spawn_gaps:	db	49, 81, 65
spawn_two:	db	EK_LIZARD, EK_BLUE
spawn_three:	db	EK_BLUE, EK_CHIM, EK_LIZARD
spawn_castle:	db	EK_SWORD, EK_MACE

; ---------------------------------------------------------------------------
; enemy_think - X = slot.

enemy_think:	lda	e_kind, x
		cmp	#EK_CLUB
		bne	!+
		jmp	club_think
!:		cmp	#EK_ITEM
		bne	!+
		jmp	item_think
!:		cmp	#EK_BAT
		bne	!+
		jmp	bat_think
!:		cmp	#EK_FIRE
		bne	!+
		jmp	fire_think
!:		cmp	#EK_ROCK
		bne	!+
		jmp	rock_think
!:		cmp	#EK_JET
		bne	!+
		jmp	jet_think
!:		cmp	#EK_VINE
		bne	!+
		jmp	vine_think
!:		cmp	#EK_BOSS
		bne	!+
		jmp	boss_think
!:		cmp	#EK_BOSS2
		bne	!+
		jmp	boss2_think
!:		cmp	#EK_FRAG
		bne	!+
		jmp	frag_think
!:		cmp	#EK_GARG
		beq	!+
		cmp	#EK_WINGS
		bne	!++
!:		jmp	garg_think
!:		lda	e_state, x
		cmp	#ES_DYING
		bne	!+
		lda	e_animend, x		; Explosion done: free the slot.
		beq	.r
		stz	e_state, x
.r:		rts
!:		jsr	sword_vs_enemy		; Rastan's sword kills in one hit.
		bcc	!+
		jmp	kill_enemy
!:		lda	e_kind, x
		cmp	#EK_CHIM
		bne	!+
		jmp	chim_think
!:		cmp	#EK_WOMAN
		bne	!+
		jmp	woman_think
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
		lda	e_kind, x		; Melee kinds (all but the thrower):
		eor	#EK_BLUE		; Rastan level with it (carry; eor keeps it).
		bne	.liz_near
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
		lda	kind_attack2_h, y	; Soldiers: a high or a low swing, at
		beq	.high			; random (the arcade: bit 2 of the slot's
		jsr	rand			; byte $21); e_alt = low.
		and	#4
		ldy	e_kind, x
		stz	e_alt, x
		cmp	#0
		beq	.high
		inc	e_alt, x
		lda	kind_attack2_l, y
		pha
		lda	kind_attack2_h, y
		tay
		pla
		jmp	enemy_set_anim
.high:		lda	kind_attack_l, y
		pha
		lda	kind_attack_h, y
		tay
		pla
		jmp	enemy_set_anim
.walk:		lda	e_face, x		; Step toward the facing direction.
		jmp	enemy_step

.attack:	ldy	e_kind, x
		cpy	#EK_BLUE
		bne	.club_swing
		; Blue: clubs leave the hand 8 and 27 frames into the throw.
		inc	e_timer, x
		lda	e_timer, x
		cmp	#8
		beq	.throw
		cmp	#27
		bne	.wait
.throw:		jsr	throw_club
		bra	.wait

.club_swing:	; The weapon is out in the kind's hit pose: the arcade arms its box
		lda	kind_attack2_h, y	; for the pose's first 3 frames ($042F92) and
		beq	.hi			; tests it each frame until it hits, once a
		lda	e_alt, x		; swing. (Soldiers' low swings: their own
		beq	.hi			; pose and weapon_hit's rows 13, 14.)
		lda	kind_hitpose2 - 11, y
		iny
		iny
		bra	.pose
.hi:		lda	kind_hitpose, y
.pose:		cmp	e_pose, x
		bne	.armed
		lda	e_struck, x
		bne	.wait
		lda	e_animt, x
		cmp	#4
		bcc	.wait
		jsr	weapon_hit
		bcc	.wait
		inc	e_struck, x
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

; kill_enemy - X: points, then its death animation (ES_DYING frees it after).
kill_enemy:	phx
		lda	#SFX_ENEMY
		jsr	sound_sfx
		plx
		lda	#ES_DYING
		sta	e_state, x
		ldy	e_kind, x
		lda	kind_score, y		; Points (hundreds, BCD).
		jsr	score_add
		ldy	e_kind, x
		lda	kind_death_l, y
		pha
		lda	kind_death_h, y
		tay
		pla
		jmp	enemy_set_anim

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
!:		cpy	#EK_CHIM		; Chimera: walk 16..206 frames, then breathe once.
		bne	!+
		jsr	rand
		and	#$7F
		clc
		adc	#16
		sta	e_timer, x
		jsr	rand
		and	#$3F
		adc	e_timer, x
		sta	e_timer, x
		stz	e_alt, x
!:		tma4				; The walk list is in the kind's group
		pha				; bank: callers that spawn (the lane
		jsr	map_kind		; spawner, a thrower's club) may have
		ldy	e_kind, x		; another one at $8000.
		lda	kind_walk_l, y
		pha
		lda	kind_walk_h, y
		tay
		pla
		jsr	enemy_set_anim
		pla
		tam4
		rts

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
kind_walk_l:	db	<anim_liz_walk, <anim_blue_walk, <anim_club, 0, <anim_bat, <anim_chim_walk, <anim_fireball
		db	<anim_boulder, <anim_garg_body, <anim_garg_wings, <anim_woman_walk, <anim_sword_walk
		db	<anim_mace_walk, <anim_jet_column, <anim_boss_walk, <anim_boss2_walk, <anim_frag_form
		db	<anim_vine_swing
kind_walk_h:	db	>anim_liz_walk, >anim_blue_walk, >anim_club, 0, >anim_bat, >anim_chim_walk, >anim_fireball
		db	>anim_boulder, >anim_garg_body, >anim_garg_wings, >anim_woman_walk, >anim_sword_walk
		db	>anim_mace_walk, >anim_jet_column, >anim_boss_walk, >anim_boss2_walk, >anim_frag_form
		db	>anim_vine_swing
kind_attack_l:	db	<anim_liz_attack, <anim_blue_throw, 0, 0, 0, 0, 0, 0, 0, 0, 0, <anim_sword_attack
		db	<anim_mace_attack
kind_attack_h:	db	>anim_liz_attack, >anim_blue_throw, 0, 0, 0, 0, 0, 0, 0, 0, 0, >anim_sword_attack
		db	>anim_mace_attack
kind_retreat_l:	db	<anim_liz_walk, <anim_blue_walk2, 0, 0, 0, 0, 0, 0, 0, 0, 0, <anim_sword_walk
		db	<anim_mace_walk
kind_retreat_h:	db	>anim_liz_walk, >anim_blue_walk2, 0, 0, 0, 0, 0, 0, 0, 0, 0, >anim_sword_walk
		db	>anim_mace_walk
kind_hitpose:	db	POSE_LIZ_CLUB_OUT, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, POSE_SWORD_OUT, POSE_MACE_OUT
kind_hitpose2:	db	POSE_SWORD_LOW, POSE_MACE_LOW		; (kinds 11, 12)
kind_attack2_l:	db	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, <anim_sword_low, <anim_mace_low, 0, 0, 0, 0, 0
kind_attack2_h:	db	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, >anim_sword_low, >anim_mace_low, 0, 0, 0, 0, 0
kind_death_l:	db	<anim_liz_death, <anim_blue_death, 0, 0, 0, <anim_chim_death, 0, 0, 0, 0, <anim_woman_death
		db	<anim_sword_death, <anim_mace_death, 0, 0, 0, 0, 0
kind_death_h:	db	>anim_liz_death, >anim_blue_death, 0, 0, 0, >anim_chim_death, 0, 0, 0, 0, >anim_woman_death
		db	>anim_sword_death, >anim_mace_death, 0, 0, 0, 0, 0
kind_range:	db	ATTACK_RANGE, 88, 0, 0, 0, 0, 0, 0, 0, 0, 0, SOLDIER_RANGE, SOLDIER_RANGE, 0, 0, 0, 0, 0
kind_keep:	db	0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 1, 1, 1, 0, 1	; No off-screen despawn.
; Arcade: lizardman 300, blue thrower 200, bat 200, chimera 300.
; Castle soldiers: the arcade gave 900 for a sword and a mace soldier dying together.
kind_score:	db	$03, $02, 0, 0, $02, $03, 0, 0, 0, 0, $03, $03, $06, 0, 0, 0, 0, 0
kind_bank:	db	GRP_SECT1_BANK, GRP_SECT1_BANK, GRP_SECT1_BANK, GRP_ITEMS_BANK, GRP_ITEMS_BANK
		db	GRP_CHIMERA_BANK, GRP_CHIMERA_BANK, GRP_ROCKS_BANK, GRP_GARGOYLE_BANK, GRP_GARGOYLE_BANK
		db	GRP_WOMAN_BANK, GRP_CASTLE_BANK, GRP_CASTLE_BANK, GRP_JETS_BANK
		db	GRP_BOSS_BANK, GRP_BOSS_BANK, GRP_BOSS_BANK, GRP_VINE_BANK
kind_ptab_l:	db	<grp_sect1_ptab, <grp_sect1_ptab, <grp_sect1_ptab, <grp_items_ptab, <grp_items_ptab
		db	<grp_chimera_ptab, <grp_chimera_ptab, <grp_rocks_ptab, <grp_gargoyle_ptab, <grp_gargoyle_ptab
		db	<grp_woman_ptab, <grp_castle_ptab, <grp_castle_ptab, <grp_jets_ptab
		db	<grp_boss_ptab, <grp_boss_ptab, <grp_boss_ptab, <grp_vine_ptab
kind_ptab_h:	db	>grp_sect1_ptab, >grp_sect1_ptab, >grp_sect1_ptab, >grp_items_ptab, >grp_items_ptab
		db	>grp_chimera_ptab, >grp_chimera_ptab, >grp_rocks_ptab, >grp_gargoyle_ptab, >grp_gargoyle_ptab
		db	>grp_woman_ptab, >grp_castle_ptab, >grp_castle_ptab, >grp_jets_ptab
		db	>grp_boss_ptab, >grp_boss_ptab, >grp_boss_ptab, >grp_vine_ptab
; Body box: x = anchor + cx +/- half, y = anchor - top .. anchor + bot
; (the item and bat boxes from their sprites' extent).
kind_top:	db	36, 48, 8, 2, 25, 30, 6, 20, 40, 32, 38, 40, 40, 16, 54, 0, 8, 0
kind_bot:	db	16, 16, 16, 30, 7, 16, 6, 12, 47, 16, 16, 16, 16, 40, 34, 0, 8, 0
kind_half:	db	16, 16, 8, 20, 16, 30, 6, 15, 23, 48, 15, 16, 16, 16, 24, 0, 8, 0
kind_cx:	db	0, 0, 0, -8, -2, 0, 4, -3, -1, -1, 0, 0, 0, 0, 0, 0, 0, 0

; ---------------------------------------------------------------------------
; throw_club - X = blue thrower: a club leaves its hand toward Rastan.
CLUB_DX		=	23			; Measured: hand 23 px ahead of the anchor.

throw_club:	ldy	#NUM_OBJ - 1		; Free projectile slot?
!:		lda	e_state, y
		beq	.slot
		dey
		cpy	#NUM_BIG
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
		lda	#$FF
		sta	e_shown, y
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
.hit:		; The arcade's boxes (inclusive, $044CBA): the club's ($03: x -3 ..
		; 3, y -8 .. 8) against Rastan's for slots 18 on ($10D22C: x - 4 ..
		; x + 4, y - 24 .. y + 26; crouched from y): |e_x - p_x| <= 7 and
		; e_y - p_y in -32 .. 34 (crouched -8 .. 34). (Checked against the
		; arcade's hit list on all 772 club-frames of blue.snp.)
		lda	e_xl, x			; |e_x - p_x| < 8
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
		cmp	#8
		bcs	.r
		lda	e_yl, x			; dy = e_y - p_y + 32 must be 0 .. 66
		sec				; (crouched: 24 .. 66)
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
		cmp	#67
		bcs	.r
		ldy	<p_state
		cpy	#ST_CROUCH
		beq	.low
		cpy	#ST_CATK
		bne	.hurt
.low:		cmp	#24
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

; weapon_hit - X = slot, Y = its row (its kind; 13, 14 the low swings):
; carry set if the weapon's box overlaps Rastan's body. The arcade's boxes (inclusive; $044CBA): the weapon's at
; $044CE0 + 4 * index, mirrored facing left (lizardman $38: x 4 .. 48, y -20
; .. -12; sword soldier $3A: 4 .. 52, -19 .. -13; mace soldier $AE: 4 .. 60,
; -19 .. -13); Rastan's x - 12 .. x + 12, y - 24 .. y + 26, crouched y ..
; y + 26 ($10D248). As ranges of dx = p_x - e_x (facing right; mirrored
; facing left) and dy = p_y - e_y: lo .. lo + width. On flat ground dy is
; about -8, so crouching ducks all three (the arcade: a crouching Rastan
; is never hit by a lizardman).
weapon_hit:	lda	<p_x
		sec
		sbc	e_xl, x
		sta	<etmp
		lda	<p_x + 1
		sbc	e_xh, x
		sta	<etmp + 1
		lda	e_face, x		; Facing left: dx = -dx.
		bne	!+
		cla
		sec
		sbc	<etmp
		sta	<etmp
		cla
		sbc	<etmp + 1
		sta	<etmp + 1
!:		lda	kind_hx_lo, y		; dx - lo in 0 .. width?
		jsr	.sub
		bne	.no
		lda	kind_hx_w, y
		cmp	<etmp
		bcc	.no
		lda	<p_y			; dy = p_y - e_y
		sec
		sbc	e_yl, x
		sta	<etmp
		lda	<p_y + 1
		sbc	e_yh, x
		sta	<etmp + 1
		lda	kind_hy_lo, y		; dy - lo in 0 .. width (crouched: less)?
		jsr	.sub
		bne	.no
		lda	<p_state
		cmp	#ST_CROUCH
		beq	.low
		cmp	#ST_CATK
		beq	.low
		lda	kind_hy_w, y
		bra	.cmp
.low:		lda	kind_hy_wc, y
.cmp:		cmp	<etmp
		bcc	.no
		sec
		rts
.no:		clc
		rts
.sub:		sta	<ey			; etmp -= A (signed); A = high byte.
		stz	<ey + 1
		bit	<ey
		bpl	!+
		dec	<ey + 1
!:		lda	<etmp
		sec
		sbc	<ey
		sta	<etmp
		lda	<etmp + 1
		sbc	<ey + 1
		sta	<etmp + 1
		rts

; (lizardman, ..., sword soldier, mace soldier, then their low swings: the
; sword's $3C, 4 .. 52, -3 .. 3; the mace's $B0, 4 .. 60, -3 .. 3, which
; reach a crouching Rastan; the others do not swing)
kind_hx_lo:	db	-8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, -8, -8, -8, -8
kind_hx_w:	db	68, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 72, 80, 72, 80
kind_hy_lo:	db	-46, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, -45, -45, -29, -29
kind_hy_w:	db	58, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 56, 56, 56, 56
kind_hy_wc:	db	34, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 32, 32, 32, 32

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
; body box (kind_cx, kind_half, kind_top, kind_bot).
sword_vs_enemy:	phx
		jsr	sword_box
		plx
		bcs	box_vs_enemy
		rts

; body_vs_enemy - carry set if Rastan's body (p_x +/- 12, p_y - 24 ..
; p_y + 24) overlaps this object's body box.
body_vs_enemy:	lda	<p_x
		sec
		sbc	#12
		sta	<sb_x0
		lda	<p_x + 1
		sbc	#0
		sta	<sb_x0 + 1
		lda	<p_x
		clc
		adc	#12
		sta	<sb_x1
		lda	<p_x + 1
		adc	#0
		sta	<sb_x1 + 1
		lda	<p_y
		sec
		sbc	#24
		sta	<sb_y0
		lda	<p_y + 1
		sbc	#0
		sta	<sb_y0 + 1
		lda	<p_y
		clc
		adc	#24
		sta	<sb_y1
		lda	<p_y + 1
		adc	#0
		sta	<sb_y1 + 1
		; (fall through)

; box_vs_enemy - carry set if the box sb_* overlaps X's body box.
box_vs_enemy:	ldy	e_kind, x
		lda	kind_cx, y		; etmp = e_x + cx (signed)
		pha
		clc
		adc	e_xl, x
		sta	<etmp
		pla
		and	#$80
		beq	!+
		lda	#$FF
!:		adc	e_xh, x
		sta	<etmp + 1
		; sb_x0 <= centre + half ?
		lda	<etmp
		clc
		adc	kind_half, y
		sta	<ex
		lda	<etmp + 1
		adc	#0
		sta	<ex + 1
		lda	<ex
		cmp	<sb_x0
		lda	<ex + 1
		sbc	<sb_x0 + 1
		bmi	.no
		; centre - half <= sb_x1 ?
		lda	<etmp
		sec
		sbc	kind_half, y
		sta	<ex
		lda	<etmp + 1
		sbc	#0
		sta	<ex + 1
		lda	<sb_x1
		cmp	<ex
		lda	<sb_x1 + 1
		sbc	<ex + 1
		bmi	.no
		; sb_y0 <= e_y + bot ?
		lda	e_yl, x
		clc
		adc	kind_bot, y
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

; despawn_check - free enemies that drift far off-screen (not kind_keep kinds).
despawn_check:	lda	e_state, x
		cmp	#ES_DYING
		beq	.ok
		ldy	e_kind, x		; Gargoyles and jets end by themselves.
		lda	kind_keep, y
		bne	.ok
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
; enemies_draw - SATB entries from satb_n, after player_draw and props_draw.

enemies_draw:	php				; VDC writes: IRQ held off (see stream_line).
		sei
		jsr	plan_uploads
		st0	#VDC_MAWR
		lda	<satb_n			; SATB_ADDR + satb_n * 4 ($7F00: low byte 0)
		asl	a
		asl	a
		sta	VDC_DL
		lda	#>SATB_ADDR
		sta	VDC_DH
		st0	#VDC_VWR
		stz	<en_satb
		lda	#64
		sec
		sbc	<satb_n
		sta	<en_cap
		ldx	#NUM_OBJ - 1		; Projectiles, specials, item and bat
.slot:		jsr	draw_slot		; first, in a fixed order,
		dex
		cpx	#NUM_EN
		bcs	.slot
		lda	<en_rot			; then the walkers and the hurry-up swarm
		inc	a			; (src/swarm.asm, as a fifth), the first of
		cmp	#NUM_EN + 1		; them changing every frame. The SATB holds
		bcc	!+			; 64 entries and the VDC shows 16 sprite
		cla				; cells a line: where they crowd, the one
!:		sta	<en_rot			; drawn last loses its entries or its cells,
		lda	#NUM_EN + 1		; and this way the loss takes turns (flicker)
		sta	<en_wk			; instead of always cutting the same one -
.walker:	lda	<en_rot			; the bats, drawn last, used to vanish
		clc				; behind a crowd of soldiers.
		adc	<en_wk
		cmp	#NUM_EN + 1
		bcc	!+
		sbc	#NUM_EN + 1
!:		cmp	#NUM_EN
		bne	!+
		jsr	swarm_draw
		bra	.wnext
!:		tax
		jsr	draw_slot
.wnext:		dec	<en_wk
		bne	.walker
		jsr	traps_draw		; The castle's floor spears.
		; Clear entries the last frame used beyond this frame's.
		lda	<en_satb
		clc
		adc	<satb_n
		sta	<en_satb		; (now: all entries in use)
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

; draw_slot - X = slot: its SATB entries, if it is shown. Keeps X.
draw_slot:	lda	e_state, x
		beq	.r
		cmp	#ES_HIDDEN
		beq	.r
		lda	e_plan, x		; Nothing in its buffer next frame: not drawn.
		cmp	#$FF
		beq	.r
		jsr	map_kind
		phx
		jsr	draw_one
		plx
.r:		rts

; draw_one - X = slot. Pieces were captured facing left (arcade X flip set);
; facing right mirrors dx (-dx - 16) and toggles the flip.
draw_one:	lda	slot_pat_l, x		; Pattern of the buffer's first cell.
		sta	<dr_pat
		lda	slot_pat_h, x
		sta	<dr_pat + 1
		lda	e_plan, x
		jsr	pose_ptr
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
		beq	.done			; (an empty pose: nothing to draw)
		sta	<etmp			; piece count
		ldy	#1
.piece:		lda	<en_satb
		cmp	<en_cap
		bcc	!+
		inc	<en_full		; Out of SATB entries (counted for
		bra	.done			; tools/audit.py).
!:
		jsr	piece_pos		; cy = screen x, ctx = screen y; carry = visible
		bcc	.skip
		jsr	emit_piece
		bra	.next
.skip:		iny				; skip cell, attr
		iny
		lda	<dr_pat			; (its cell still has its place)
		clc
		adc	#2
		sta	<dr_pat
		bcc	.next
		inc	<dr_pat + 1
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
		iny				; pattern = buffer + piece * 2
		lda	<dr_pat
		sta	VDC_DL
		lda	<dr_pat + 1
		sta	VDC_DH
		lda	<dr_pat
		clc
		adc	#2
		sta	<dr_pat
		bcc	!+
		inc	<dr_pat + 1
!:
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

; ---------------------------------------------------------------------------
; Object slots' cell buffers and pose uploads.

; map_kind - X = slot: map its kind's group bank at $8000 (MPR4).
map_kind:	ldy	e_kind, x
		lda	kind_bank, y
		tam4
		rts

; pose_ptr - A = pose of slot X's kind (bank mapped): ep = the pose.
pose_ptr:	asl	a
		pha
		ldy	e_kind, x
		lda	kind_ptab_l, y
		sta	<ep
		lda	kind_ptab_h, y
		sta	<ep + 1
		ply
		lda	[ep], y
		pha
		iny
		lda	[ep], y
		sta	<ep + 1
		pla
		sta	<ep
		rts

; objects_upload - in VBLANK, before the display starts: upload the cells of
; poses that changed, up to UPLOAD_BUDGET cells, starting where it stopped last
; time. An object that does not fit keeps showing its old pose until it does.
objects_upload:	php
		sei
		tma4
		pha
		lda	#UPLOAD_BUDGET
		sta	<up_left
		lda	#NUM_OBJ
		sta	<up_count
		ldx	<up_next
.loop:		lda	e_state, x
		beq	.next
		lda	e_plan, x
		cmp	e_shown, x
		beq	.next
		cmp	#$FF
		beq	.next
		jsr	upload_one
.next:		inx
		cpx	#NUM_OBJ
		bcc	!+
		clx
!:		dec	<up_count
		bne	.loop
		inx				; Start after this one next time.
		cpx	#NUM_OBJ
		bcc	!+
		clx
!:		stx	<up_next
		pla
		tam4
		plp
		rts

; plan_uploads - which slots get their new pose's cells at the next VBLANK:
; the same order and budget objects_upload uses. The SATB written now (and
; DMA'd at that VBLANK, just before the upload) then shows each slot with the
; pose its buffer holds, so a frame never mixes an old layout with new cells.
plan_uploads:	tma4
		pha
		lda	#UPLOAD_BUDGET
		sta	<up_left
		lda	#NUM_OBJ
		sta	<up_count
		ldx	<up_next
.loop:		lda	e_shown, x		; Default: what it holds now.
		sta	e_plan, x
		lda	e_state, x
		beq	.next
		lda	e_pose, x
		cmp	e_shown, x
		beq	.next
		jsr	map_kind
		lda	e_pose, x
		jsr	pose_ptr
		lda	[ep]			; Cells it needs: fit this VBLANK?
		cmp	<up_left
		beq	!+
		bcs	.next
!:		eor	#$FF
		sec
		adc	<up_left
		sta	<up_left
		lda	e_pose, x
		sta	e_plan, x
.next:		inx
		cpx	#NUM_OBJ
		bcc	!+
		clx
!:		dec	<up_count
		bne	.loop
		pla
		tam4
		rts

; upload_one - X = slot: its planned pose's cells into its buffer.
upload_one:	jsr	map_kind
		lda	e_plan, x
		jsr	pose_ptr
		lda	[ep]			; Cells this pose needs.
		bne	!+
		lda	e_plan, x		; (an empty pose: nothing to upload)
		sta	e_shown, x
		rts
!:		cmp	<up_left
		beq	!+
		bcs	.later
!:		sta	<up_piece
		lda	<up_left
		sec
		sbc	<up_piece
		sta	<up_left
		st0	#VDC_MAWR
		lda	slot_vram_l, x
		sta	VDC_DL
		lda	slot_vram_h, x
		sta	VDC_DH
		st0	#VDC_VWR
		ldy	#3			; First piece's cell byte.
.piece:		lda	[ep], y			; cell bits 0-7
		sta	<etmp
		iny
		lda	[ep], y			; attr: cell bits 8-9 in bits 4-5
		iny
		iny
		iny				; (next piece's cell byte)
		and	#$30			; bank = OBJ_CELL_BANK + cell >> 6
		lsr	a
		lsr	a
		sta	<etmp + 1
		lda	<etmp
		rol	a
		rol	a
		rol	a
		and	#3
		ora	<etmp + 1
		clc
		adc	#OBJ_CELL_BANK
		tam3
		lda	<etmp			; address = $6000 + (cell & 63) * 128
		and	#63
		lsr	a
		ora	#$60
		sta	ram_tia + 2
		cla
		ror	a
		sta	ram_tia + 1
		jsr	ram_tia
		dec	<up_piece
		bne	.piece
		lda	e_plan, x
		sta	e_shown, x
.later:		rts

; Slot buffers (cells from EN_VRAM: 0, 11, 22, 33, 44, 48, 52, 65, 78, 91, 93, 95, 97, 99, 101, 103, 105):
; VRAM word addresses and sprite pattern numbers (address / 32).
slot_vram_l:	db	<(EN_VRAM + 0 * 64), <(EN_VRAM + 11 * 64), <(EN_VRAM + 22 * 64), <(EN_VRAM + 33 * 64), <(EN_VRAM + 44 * 64), <(EN_VRAM + 48 * 64)
		db	<(EN_VRAM + 52 * 64), <(EN_VRAM + 65 * 64), <(EN_VRAM + 78 * 64), <(EN_VRAM + 91 * 64), <(EN_VRAM + 93 * 64), <(EN_VRAM + 95 * 64)
		db	<(EN_VRAM + 97 * 64), <(EN_VRAM + 99 * 64), <(EN_VRAM + 101 * 64), <(EN_VRAM + 103 * 64), <(EN_VRAM + 105 * 64)
slot_vram_h:	db	>(EN_VRAM + 0 * 64), >(EN_VRAM + 11 * 64), >(EN_VRAM + 22 * 64), >(EN_VRAM + 33 * 64), >(EN_VRAM + 44 * 64), >(EN_VRAM + 48 * 64)
		db	>(EN_VRAM + 52 * 64), >(EN_VRAM + 65 * 64), >(EN_VRAM + 78 * 64), >(EN_VRAM + 91 * 64), >(EN_VRAM + 93 * 64), >(EN_VRAM + 95 * 64)
		db	>(EN_VRAM + 97 * 64), >(EN_VRAM + 99 * 64), >(EN_VRAM + 101 * 64), >(EN_VRAM + 103 * 64), >(EN_VRAM + 105 * 64)
slot_pat_l:	db	<((EN_VRAM + 0 * 64) >> 5), <((EN_VRAM + 11 * 64) >> 5), <((EN_VRAM + 22 * 64) >> 5), <((EN_VRAM + 33 * 64) >> 5), <((EN_VRAM + 44 * 64) >> 5), <((EN_VRAM + 48 * 64) >> 5)
		db	<((EN_VRAM + 52 * 64) >> 5), <((EN_VRAM + 65 * 64) >> 5), <((EN_VRAM + 78 * 64) >> 5), <((EN_VRAM + 91 * 64) >> 5), <((EN_VRAM + 93 * 64) >> 5), <((EN_VRAM + 95 * 64) >> 5)
		db	<((EN_VRAM + 97 * 64) >> 5), <((EN_VRAM + 99 * 64) >> 5), <((EN_VRAM + 101 * 64) >> 5), <((EN_VRAM + 103 * 64) >> 5), <((EN_VRAM + 105 * 64) >> 5)
slot_pat_h:	db	>((EN_VRAM + 0 * 64) >> 5), >((EN_VRAM + 11 * 64) >> 5), >((EN_VRAM + 22 * 64) >> 5), >((EN_VRAM + 33 * 64) >> 5), >((EN_VRAM + 44 * 64) >> 5), >((EN_VRAM + 48 * 64) >> 5)
		db	>((EN_VRAM + 52 * 64) >> 5), >((EN_VRAM + 65 * 64) >> 5), >((EN_VRAM + 78 * 64) >> 5), >((EN_VRAM + 91 * 64) >> 5), >((EN_VRAM + 93 * 64) >> 5), >((EN_VRAM + 95 * 64) >> 5)
		db	>((EN_VRAM + 97 * 64) >> 5), >((EN_VRAM + 99 * 64) >> 5), >((EN_VRAM + 101 * 64) >> 5), >((EN_VRAM + 103 * 64) >> 5), >((EN_VRAM + 105 * 64) >> 5)
