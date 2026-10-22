; ***************************************************************************
;
; Rastan - weapon items and their bats (approximate), round 1.
;
; Measured in the arcade (sim/scripts/item*.txt, round 1 census): four items
; hang in the air, each appearing when Rastan reaches 164 px left of it, with
; a bat 20 px below. Touching one (or hitting it with the weapon, as the up
; thrust does in the cave) takes it: the axe (twice), the fire sword or the
; morning star, for 3000 frames. A death brings the items back.
;
; The bat first flies off away from Rastan, curving down (about 75 frames),
; hovers over him (about 280 frames), then dives onto him and clings, biting: 1024 of 12288
; health (4 bar units) when it brushes him in flight, 2048 (8 units) every
; 45 frames while clinging, with no knockback. One hit kills it.
;
; ***************************************************************************

NUM_ITEMS	=	4
ITEM_AHEAD	=	164		; Spawns when p_x >= item x - 164 ...
ITEM_WINDOW	=	196		; ... and p_x < item x + 32.
BAT_DROP	=	20		; The bat starts this far below the item.
BAT_FLEE	=	72		; Frames flying off.
BAT_HOVER	=	255		; Frames hovering before the dive.
BAT_HEIGHT	=	64		; Hovers this far above Rastan's anchor.
BAT_BITE	=	45		; Frames between bites.
BAT_BRUSH_HP	=	4
BAT_BITE_HP	=	8

BP_FLEE		=	0		; Bat phases (e_range).
BP_HOVER	=	1
BP_DIVE		=	2
BP_CLING	=	3

; Items: world x, y, weapon, animation.
item_x_l:	db	<1004, <2893, <3854, <6829
item_x_h:	db	>1004, >2893, >3854, >6829
item_y_l:	db	<340, <164, <364, <276
item_y_h:	db	>340, >164, >364, >276
item_weapon:	db	WPN_AXE, WPN_FIRE, WPN_AXE, WPN_STAR
item_anim_l:	db	<anim_item_axe, <anim_item_fire, <anim_item_axe, <anim_item_star
item_anim_h:	db	>anim_item_axe, >anim_item_fire, >anim_item_axe, >anim_item_star
item_bit:	db	1, 2, 4, 8

; ---------------------------------------------------------------------------
; item_spawn - the next item (and its bat) when Rastan comes near it.

item_spawn:	lda	e_state + ITEM_SLOT	; One item at a time.
		bne	.r
		cly
.loop:		lda	items_done
		and	item_bit, y
		bne	.next
		lda	item_x_l, y		; p_x - (x - 164) in 0 .. 195?
		sec
		sbc	#<ITEM_AHEAD
		sta	<etmp
		lda	item_x_h, y
		sbc	#>ITEM_AHEAD
		sta	<etmp + 1
		lda	<p_x
		sec
		sbc	<etmp
		sta	<etmp
		lda	<p_x + 1
		sbc	<etmp + 1
		bne	.next
		lda	<etmp
		cmp	#ITEM_WINDOW
		bcc	.spawn
.next:		iny
		cpy	#NUM_ITEMS
		bne	.loop
.r:		rts

.spawn:		lda	items_done
		ora	item_bit, y
		sta	items_done
		sty	<etmp + 1
		; The item.
		ldx	#ITEM_SLOT
		jsr	.place
		lda	#EK_ITEM
		sta	e_kind, x
		lda	item_weapon, y
		sta	e_alt, x
		lda	#ES_WALK		; (a looping animation)
		sta	e_state, x
		jsr	map_kind
		ldy	<etmp + 1
		lda	item_anim_h, y
		pha
		lda	item_anim_l, y
		ply
		jsr	enemy_set_anim
		; The bat, below it, flying off away from Rastan (if the last one
		; is not still around).
		lda	e_state + BAT_SLOT
		bne	.r
		ldy	<etmp + 1
		ldx	#BAT_SLOT
		jsr	.place
		lda	e_yl, x
		clc
		adc	#BAT_DROP
		sta	e_yl, x
		bcc	!+
		inc	e_yh, x
!:		lda	#EK_BAT
		sta	e_kind, x
		stz	e_range, x		; BP_FLEE
		stz	e_timer, x
		stz	e_struck, x
		lda	<p_x			; Rastan left of it: fly right.
		cmp	e_xl, x
		lda	<p_x + 1
		sbc	e_xh, x
		cla
		bcs	!+
		inc	a
!:		sta	e_alt, x
		jsr	map_kind
		lda	#<anim_bat
		ldy	#>anim_bat
		jsr	enemy_set_anim
		lda	#ES_WALK
		sta	e_state, x
		rts

.place:		lda	item_x_l, y		; X = slot, Y = item.
		sta	e_xl, x
		lda	item_x_h, y
		sta	e_xh, x
		lda	item_y_l, y
		sta	e_yl, x
		lda	item_y_h, y
		sta	e_yh, x
		stz	e_face, x		; Drawn as captured.
		stz	e_sub, x
		lda	#$FF
		sta	e_shown, x
		rts

; ---------------------------------------------------------------------------
; item_think - X = item: taken by touch or by the weapon.

item_think:	jsr	body_vs_enemy
		bcs	.take
		jsr	sword_vs_enemy
		bcc	.r
.take:		lda	e_alt, x
		phx
		jsr	player_set_weapon
		plx
		stz	e_state, x
.r:		rts

; ---------------------------------------------------------------------------
; bat_think - X = bat.

bat_think:	jsr	sword_vs_enemy		; One hit kills it.
		bcc	!+
		stz	e_state, x
		rts
!:		lda	e_struck, x		; Bite cooldown.
		beq	!+
		dec	e_struck, x
!:		inc	e_timer, x
		lda	e_range, x
		cmp	#BP_HOVER
		beq	.hover
		cmp	#BP_DIVE
		beq	.dive
		cmp	#BP_CLING
		bne	.flee
		jmp	.cling

.flee:		; 1.5 px/frame away from Rastan, sinking 1 px/frame, then 1/2.
		lda	e_timer, x
		and	#1
		inc	a
		ldy	e_alt, x
		bne	!+
		eor	#$FF
		inc	a
!:		jsr	add_x
		lda	e_timer, x
		cmp	#40
		bcc	.sink
		and	#1
		beq	!+
.sink:		lda	#1
		jsr	add_y
!:		lda	e_timer, x
		cmp	#BAT_FLEE
		bcc	.r
		lda	#BP_HOVER
		bra	.phase

.hover:		; Drift over Rastan: 1 px/frame across, 1/2 up or down.
		jsr	bat_brush
		jsr	target_rastan
		lda	<ey
		sec
		sbc	#BAT_HEIGHT
		sta	<ey
		bcs	!+
		dec	<ey + 1
!:		lda	#1
		jsr	approach_x
		lda	e_timer, x
		and	#1
		beq	!+
		lda	#1
		jsr	approach_y
!:		lda	e_timer, x
		cmp	#BAT_HOVER
		bcc	.r
		lda	#BP_DIVE
.phase:		sta	e_range, x
		stz	e_timer, x
.r:		rts

.dive:		; 1 px/frame onto him; clings when it gets there.
		jsr	bat_brush
		jsr	target_rastan
		lda	#1
		jsr	approach_x
		pha
		lda	#1
		jsr	approach_y
		sta	<etmp
		pla
		ora	<etmp			; Both there?
		bne	.r
		lda	#BP_CLING
		bra	.phase

.cling:		jsr	target_rastan
		lda	<ex
		sta	e_xl, x
		lda	<ex + 1
		sta	e_xh, x
		lda	<ey
		sta	e_yl, x
		lda	<ey + 1
		sta	e_yh, x
		lda	e_timer, x
		cmp	#BAT_BITE
		bcc	.r
		stz	e_timer, x
		lda	#BAT_BITE_HP
		phx
		jsr	player_drain
		plx
		rts

; bat_brush - in flight, touching Rastan bites him (once per BAT_BITE frames).
bat_brush:	lda	e_struck, x
		bne	.r
		jsr	body_vs_enemy
		bcc	.r
		lda	#BAT_BITE
		sta	e_struck, x
		lda	#BAT_BRUSH_HP
		phx
		jsr	player_drain
		plx
.r:		rts

; target_rastan - ex/ey = where a clinging bat sits: (p_x - 3, p_y).
target_rastan:	lda	<p_x
		sec
		sbc	#3
		sta	<ex
		lda	<p_x + 1
		sbc	#0
		sta	<ex + 1
		lda	<p_y
		sta	<ey
		lda	<p_y + 1
		sta	<ey + 1
		rts

; add_x / add_y - X's coordinate += A (signed).
add_x:		pha
		clc
		adc	e_xl, x
		sta	e_xl, x
		pla
		and	#$80
		beq	!+
		lda	#$FF
!:		adc	e_xh, x
		sta	e_xh, x
		rts

add_y:		pha
		clc
		adc	e_yl, x
		sta	e_yl, x
		pla
		and	#$80
		beq	!+
		lda	#$FF
!:		adc	e_yh, x
		sta	e_yh, x
		rts

; approach_x - move X's x toward ex by at most A px. Leaves A = 0 when it
; got there, nonzero otherwise (approach_y: toward ey).
approach_x:	sta	<etmp
		lda	<ex
		sec
		sbc	e_xl, x
		sta	<etmp + 1
		lda	<ex + 1
		sbc	e_xh, x
		jsr	clamp_step
		pha
		jsr	add_x
		pla
		eor	<etmp + 1		; Zero if the whole distance was covered.
		rts

approach_y:	sta	<etmp
		lda	<ey
		sec
		sbc	e_yl, x
		sta	<etmp + 1
		lda	<ey + 1
		sbc	e_yh, x
		jsr	clamp_step
		pha
		jsr	add_y
		pla
		eor	<etmp + 1
		rts

; clamp_step - distance A:etmp+1 (16-bit, signed), max step etmp:
; A = the step (signed). etmp+1 = the distance's low byte when it is within
; reach, else something different from the step.
clamp_step:	bmi	.neg
		bne	.far			; >= 256
		lda	<etmp + 1
		cmp	<etmp
		bcc	.near			; distance < step
		beq	.near
.far:		lda	<etmp
		eor	#$FF			; (any value unlike the step)
		sta	<etmp + 1
		eor	#$FF
		rts
.near:		lda	<etmp + 1
		rts
.neg:		cmp	#$FF
		bne	.farn
		lda	<etmp + 1
		eor	#$FF
		inc	a			; |distance|
		cmp	<etmp
		bcc	.near
		beq	.near
.farn:		lda	<etmp			; -step
		eor	#$FF
		inc	a
		pha
		eor	#$FF
		sta	<etmp + 1		; (unlike -step)
		pla
		rts
