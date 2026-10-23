; ***************************************************************************
;
; Rastan - round 2's snakes (approximate).
;
; Measured in the arcade (sim/scripts/snake.txt, the census of the round 2
; checkpoint runs; its code at $0473B8 and the walkers' at $0407BE): a snake
; enters on an enemy lane like a lizardman and crawls 7/8 px a frame. Level
; with Rastan and 57 px or nearer, it turns to him and strikes three times
; (anims 181, 184, 185 for 3, 6, 9 frames each; its weapon, box $5F, x 16 ..
; 32, y -20 .. -12, is armed for 185's first 3 frames: a type 2 hit, the 8-unit
; drain; crouching ducks it). Then it crawls on, and at 48 .. 51 px it turns
; away ($0474A8) and flees twice as fast until 104 px away ($04742E), then
; crawls off. At a wall or a ledge it turns. Touching it drains 4 units (type
; 1); one hit kills it (200 points).
;
; The arcade decides to strike at the lanes' markers ($3A), with a random
; byte; the port strikes whenever Rastan is near and a 16-frame rest is over.
;
; ***************************************************************************

SNAKE_STRIKE	=	58		; Strikes at Rastan this near (level with it).
SNAKE_TURN	=	48		; After a strike: turns away at 48 .. 51 px,
SNAKE_FAR	=	104		; and flees fast until this far.
SNAKE_REST	=	16		; Frames between strikes.
SNAKE_STRIKES	=	3
SNAKE_ROW	=	15		; weapon_hit's row for the strike.

SN_FLEE		=	1		; e_alt bits: fleeing fast,
SN_STRUCK	=	2		; has struck.

; snake_think - X = a snake, alive (enemy_think handled the sword and dying).
snake_think:	jsr	touch_hurts
		lda	e_state, x
		cmp	#ES_ATTACK
		bne	.walk
		; Striking: the weapon is out in the first 3 frames of the reach.
		lda	e_pose, x
		cmp	#POSE_SNAKE_OUT
		bne	.next
		lda	e_animt, x
		cmp	#6
		bcc	.next
		lda	e_struck, x
		bne	.next
		ldy	#SNAKE_ROW
		jsr	weapon_hit
		bcc	.next
		inc	e_struck, x
		phx
		lda	#2
		jsr	player_touch
		plx
.next:		lda	e_animend, x
		beq	.r
		stz	e_struck, x
		dec	e_timer, x
		beq	.done
		lda	#<anim_snake_strike
		ldy	#>anim_snake_strike
		jmp	enemy_set_anim
.done:		jsr	start_walk
		lda	#SNAKE_REST
		sta	e_timer, x
		lda	e_alt, x
		ora	#SN_STRUCK
		sta	e_alt, x
.r:		rts

.walk:		jsr	player_dist		; etmp = |dx|, carry: level with it
		cla
		rol	a
		sta	<ex			; (1: level)
		lda	e_timer, x
		beq	!+
		dec	e_timer, x
!:		lda	<etmp + 1
		bne	.far
		lda	e_alt, x
		bit	#SN_FLEE
		beq	.crawl
		lda	<etmp			; Fleeing: slows down far enough away.
		cmp	#SNAKE_FAR
		bcs	.far
		bra	.move
.far:		lda	e_alt, x
		and	#$FF - SN_FLEE
		sta	e_alt, x
		bra	.move
.crawl:		bit	#SN_STRUCK		; After a strike, at 48 .. 51: turn away.
		beq	.strike
		lda	<etmp
		cmp	#SNAKE_TURN
		bcc	.strike
		cmp	#SNAKE_TURN + 4
		bcs	.strike
		lda	e_face, x
		eor	#1
		sta	e_face, x
		lda	#SN_STRUCK | SN_FLEE
		sta	e_alt, x
		bra	.move
.strike:	lda	<ex			; Level with Rastan, rested, near?
		beq	.move
		lda	e_timer, x
		bne	.move
		lda	<etmp
		cmp	#SNAKE_STRIKE
		bcs	.move
		jsr	face_player
		lda	#ES_ATTACK
		sta	e_state, x
		lda	#SNAKE_STRIKES
		sta	e_timer, x
		stz	e_struck, x
		lda	#<anim_snake_strike
		ldy	#>anim_snake_strike
		jmp	enemy_set_anim

.move:		jsr	snake_step
		lda	e_alt, x
		lsr	a
		bcc	.r
		; (fall through: fleeing, a second step)

; snake_step - X = snake: a step the way it faces; at a wall or a ledge, turn.
snake_step:	lda	e_xl, x
		pha
		lda	e_face, x
		jsr	enemy_step
		pla
		cmp	e_xl, x
		bne	.r
		lda	e_sub, x		; (every 8th step is skipped)
		and	#7
		beq	.r
		lda	e_face, x
		eor	#1
		sta	e_face, x
.r:		rts
