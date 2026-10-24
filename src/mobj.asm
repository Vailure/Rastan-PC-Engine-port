; ***************************************************************************
;
; Rastan - the map objects of rounds 2 and 3 (approximate): floating logs and
; sinking blocks Rastan rides, the mud in round 2's gaps, round 3's wall
; spears, floor spears and rock spikes.
;
; In the arcade each is an object a map marker puts in play as the camera
; comes near (and takes out of play once it is past). Measured on the bot's
; runs through the rounds (build/r2run.snp, r3run.snp: Makefile R2RUN_POKES):
;
; - Logs (markers $59-$5D, object type $17; four 16 px cells): drift right
;   and back over 48 px, a step every 3 frames (the offsets in mo_logtab, an
;   ease in and out), resting 72 frames at either end. Rastan rides them.
; - Blocks (round 2's $61-$63, round 3's $6E-$70; type $15; 2x2 cells): rest
;   at the surface, then sink 2 px every 5 frames until gone, stay down 151
;   frames, rise the same way and rest 151. Rastan rides them (and goes down
;   with them). A row of cells under the surface is not drawn.
; - Mud ($5E-$60, type $16; 2x4 cells, one of its four phases): fills a gap in
;   the ground. The port's gap does the rest.
; - Wall spears ($65/$66, type $13): two spears out of the wall to the right,
;   one above the other; they rest 4 px out for 99 frames, thrust to 46 px at
;   2 px a frame, hold 3 frames and draw back. Out further than at rest they
;   hurt like a sword (12 units, knocked back: the arcade's 23-frame hurt).
; - Floor spears ($46/$6C/$6D, type $1D, round 1's traps.asm in other places)
;   and rock spikes ($71/$72, type $21): rest 99 frames 2 px out of the
;   floor, rise 64 px at 2 px a frame, hold 4 frames and sink. Out of the
;   floor (8 px or more) they kill on touch, as round 1's spears do.
;
; Each round's objects are a table (mo_tab_r2, mo_tab_r3): kind, anchor x,
; y (the arcade object's), and the frames it waits when it comes into play.
; Up to MO_MAX are in play, those whose anchor is within MO_MARGIN of the
; screen. Their cells are resident at MOB_VRAM ($4B00-$4FFF: round 1's floor
; spears and props' place, which rounds 2 and 3 leave free; build/objects/
; mobj_r<n>.bin), uploaded by enemies_load.
;
; Code in bank XBANK2 (MPR2, through the x_mobj_* trampolines); the platform
; test coll_world asks (mobj_coll) is in GAME_BANK (src/props.asm).
;
; ***************************************************************************

MO_MAX		=	6
MO_MARGIN	=	96		; In play while x - scroll_x is in -96 .. 351.
MOB_VRAM	=	$4B00
MOB_PAT		=	MOB_VRAM >> 5
MOB_ENTRIES	=	28		; SATB entries the map objects may take.

MK_LOG		=	0
MK_BLOCK	=	1
MK_MUD		=	2
MK_WSPEAR	=	3
MK_FSPEAR	=	4
MK_RISER	=	5

LOG_REST	=	72
BLK_REST	=	151
BLK_STEP	=	5		; Frames a 2 px step.
WSP_REST	=	99
WSP_OUT		=	46
WSP_IN		=	4
SPK_REST	=	99
SPK_TOP		=	64
SPK_HOLD	=	4

		.bss
mo_ent:		ds	MO_MAX		; Table entry in play ($FF: free slot).
mo_kind:	ds	MO_MAX
mo_xl:		ds	MO_MAX
mo_xh:		ds	MO_MAX
mo_yl:		ds	MO_MAX
mo_yh:		ds	MO_MAX
mo_ph:		ds	MO_MAX		; Phase.
mo_t:		ds	MO_MAX		; Frames left in it.
mo_v:		ds	MO_MAX		; Log: step 0-23; block: px above the anchor;
					; spears, spikes: px out.
mo_on:		ds	2		; Table entries in play (bits).
mo_n:		ds	1		; (mobj_update: entries in the round's table)
mo_off:		ds	1		; (its offset)
mo_lo:		ds	1		; (the window's x >> 8)
mo_hi:		ds	1
mo_dx:		ds	1		; (carry: Rastan moved with a platform)
mo_dy:		ds	1
mo_cnt:		ds	1		; (mobj_draw: entries written)
; Platforms for coll_world (mobj_coll): per slot, x0 <= x < x1, top <= y < top + 8.
mo_pf:		ds	MO_MAX		; Nonzero: a platform.
mo_px0l:	ds	MO_MAX
mo_px0h:	ds	MO_MAX
mo_px1l:	ds	MO_MAX
mo_px1h:	ds	MO_MAX
mo_ptl:		ds	MO_MAX
mo_pth:		ds	MO_MAX
mo_nplat:	ds	1		; Platforms in play (0: coll_world skips them).
		.code

; ---------------------------------------------------------------------------
; mobj_reset - nothing in play (a restart).

mobj_reset:	ldx	#MO_MAX - 1
!:		lda	#$FF
		sta	mo_ent, x
		stz	mo_pf, x
		dex
		bpl	!-
		stz	mo_on
		stz	mo_on + 1
		stz	mo_nplat
		rts

; ---------------------------------------------------------------------------
; mobj_update - after player_update (rounds 2 and 3).

mobj_update:	lda	<cur_round
		asl	a
		tax
		lda	mo_tabs - 4, x
		sta	<ep
		lda	mo_tabs - 3, x
		sta	<ep + 1
		; Out of the margin: out of play.
		ldx	#MO_MAX - 1
.drop:		lda	mo_ent, x
		bmi	.dnext
		jsr	mo_inwin
		bcs	.dnext
		lda	mo_ent, x
		jsr	mo_bit
		eor	#$FF
		and	mo_on, y
		sta	mo_on, y
		lda	#$FF
		sta	mo_ent, x
		stz	mo_pf, x
.dnext:		dex
		bpl	.drop
		; Into the margin: into play (a free slot). A quick test on x's
		; high byte first, (scroll_x - MO_MARGIN) >> 8 .. (scroll_x + 255 +
		; MO_MARGIN) >> 8, keeps the pass over the table cheap.
		lda	<scroll_x
		sec
		sbc	#MO_MARGIN
		lda	<scroll_x + 1
		sbc	#0
		bpl	!+
		cla				; (the tables' x are all positive)
!:		sta	mo_lo
		lda	<scroll_x
		clc
		adc	#<(255 + MO_MARGIN)
		lda	<scroll_x + 1
		adc	#>(255 + MO_MARGIN)
		sta	mo_hi
		cly				; (table offset)
		stz	mo_n			; (entry)
.spawn:		lda	[ep], y
		cmp	#$FF
		bne	!+
		jmp	.think
!:		iny
		iny
		lda	[ep], y			; x >> 8
		dey
		dey
		cmp	mo_lo
		bcc	.snext
		cmp	mo_hi
		beq	!+
		bcs	.snext
!:		sty	mo_off
		lda	mo_n
		jsr	mo_bit
		and	mo_on, y
		bne	.sback
		ldy	mo_off
		iny
		lda	[ep], y			; Anchor x
		sta	<ex
		iny
		lda	[ep], y
		sta	<ex + 1
		jsr	mo_win_ex
		bcc	.sback
		ldx	#MO_MAX - 1		; A free slot?
!:		lda	mo_ent, x
		bmi	.slot
		dex
		bpl	!-
		jmp	.think
.slot:		lda	mo_n
		sta	mo_ent, x
		jsr	mo_bit
		ora	mo_on, y
		sta	mo_on, y
		ldy	mo_off
		lda	[ep], y
		sta	mo_kind, x
		iny
		lda	[ep], y
		sta	mo_xl, x
		iny
		lda	[ep], y
		sta	mo_xh, x
		iny
		lda	[ep], y
		sta	mo_yl, x
		iny
		lda	[ep], y
		sta	mo_yh, x
		iny
		lda	[ep], y			; Its first wait.
		sta	mo_t, x
		stz	mo_ph, x
		ldy	mo_kind, x
		lda	.v0, y
		sta	mo_v, x
.sback:		ldy	mo_off
.snext:		inc	mo_n
		tya
		clc
		adc	#6
		tay
		jmp	.spawn
.v0:		db	0, 32, 0, WSP_IN, 2, 2

		; Each in play: its step, the ride, its touch.
.think:		stz	mo_nplat
		ldx	#MO_MAX - 1
.loop:		lda	mo_ent, x
		bmi	.next
		lda	mo_kind, x
		asl	a
		tay
		lda	.kinds, y
		sta	<etmp
		lda	.kinds + 1, y
		sta	<etmp + 1
		phx
		jsr	.call
		plx
		lda	mo_pf, x
		beq	.next
		inc	mo_nplat
.next:		dex
		bpl	.loop
		rts
.call:		jmp	[etmp]
.kinds:		dw	mo_log, mo_block, mo_none, mo_wspear, mo_spike, mo_spike

; mo_offset - Y = entry: Y = its offset in the table (6 bytes an entry).
mo_offset:	tya
		asl	a
		sta	<etmp
		asl	a
		clc
		adc	<etmp
		tay
		rts

; mo_bit - A = entry: A = its bit in mo_on + Y.
mo_bit:		pha
		lsr	a
		lsr	a
		lsr	a
		tay
		pla
		and	#7
		phx
		tax
		lda	.bits, x
		plx
		rts
.bits:		db	1, 2, 4, 8, 16, 32, 64, 128

; mo_inwin - carry set if slot X's anchor is within the margin of the screen.
mo_inwin:	lda	mo_xl, x
		sta	<ex
		lda	mo_xh, x
		sta	<ex + 1
		; (fall through)
; mo_win_ex - carry set if ex - scroll_x + MO_MARGIN is in 0 .. 255 + 2 * MO_MARGIN.
mo_win_ex:	lda	<ex
		sec
		sbc	<scroll_x
		sta	<etmp
		lda	<ex + 1
		sbc	<scroll_x + 1
		sta	<etmp + 1
		lda	<etmp
		clc
		adc	#MO_MARGIN
		sta	<etmp
		lda	<etmp + 1
		adc	#0
		beq	.yes			; (0 .. 255)
		cmp	#1
		bne	.no
		lda	<etmp			; (256 .. 255 + 2 * MO_MARGIN)
		cmp	#2 * MO_MARGIN
		bcs	.no
.yes:		sec
		rts
.no:		clc
		rts

mo_none:	rts

; ---------------------------------------------------------------------------
; The kinds' steps (X = slot).

; Logs: mo_v the step (0-23, its offset mo_logtab), mo_ph 0 resting at the
; left, 1 drifting right, 2 resting at the right, 3 drifting left.
mo_log:		lda	mo_v, x			; The old offset's rect: Rastan on it?
		tay
		lda	mo_logtab, y
		sta	mo_dy
		jsr	mo_log_rect
		jsr	mo_on_plat
		php
		dec	mo_t, x
		bne	.moved
		lda	mo_ph, x
		cmp	#1
		beq	.right
		cmp	#3
		beq	.left
		inc	a			; Rest done: drift.
		sta	mo_ph, x
		bra	.again
.right:		inc	mo_v, x			; A step every 3 frames.
		lda	mo_v, x
		cmp	#23
		bne	.again
		bra	.rest
.left:		dec	mo_v, x
		bne	.again
.rest:		lda	mo_ph, x
		inc	a
		and	#3
		sta	mo_ph, x
		lda	#LOG_REST
		sta	mo_t, x
		bra	.moved
.again:		lda	#3
		sta	mo_t, x
.moved:		plp				; On it: he moves with it.
		php
		bcc	.rect
		lda	mo_v, x
		tay
		lda	mo_logtab, y
		sec
		sbc	mo_dy
		beq	.rect
		phx
		sta	<dx
		jsr	move_x
		plx
.rect:		lda	mo_v, x
		tay
		lda	mo_logtab, y
		sta	mo_dy
		jsr	mo_log_rect
		plp
		bcc	!+
		jmp	mo_snap
!:		rts

; mo_log_rect - slot X's platform: x + offset (mo_dy) .. + 64, top y.
mo_log_rect:	lda	mo_xl, x
		clc
		adc	mo_dy
		sta	mo_px0l, x
		lda	mo_xh, x
		adc	#0
		sta	mo_px0h, x
		lda	mo_px0l, x
		clc
		adc	#64
		sta	mo_px1l, x
		lda	mo_px0h, x
		adc	#0
		sta	mo_px1h, x
		lda	mo_yl, x
		sta	mo_ptl, x
		lda	mo_yh, x
		sta	mo_pth, x
		lda	#1
		sta	mo_pf, x
		rts

mo_logtab:	db	1, 2, 3, 5, 7, 9, 11, 13, 15, 17, 20, 23, 26, 29, 32, 34, 36, 38, 40, 42, 44, 46, 47, 48

; Blocks: mo_v px above the anchor (32 at rest at the top, 0 gone), mo_ph 0
; resting up, 1 sinking, 2 down, 3 rising.
mo_block:	jsr	mo_block_rect		; The old rect: Rastan on it?
		jsr	mo_on_plat
		php
		lda	mo_v, x
		sta	mo_dy			; (old height)
		dec	mo_t, x
		bne	.done
		lda	#BLK_STEP
		sta	mo_t, x
		lda	mo_ph, x
		cmp	#1
		beq	.sink
		cmp	#3
		beq	.rise
		inc	a			; Rest done: sink or rise.
		sta	mo_ph, x
		bra	.done
.sink:		dec	mo_v, x			; 2 px every BLK_STEP frames.
		dec	mo_v, x
		bne	.done
		bra	.rest
.rise:		inc	mo_v, x
		inc	mo_v, x
		lda	mo_v, x
		cmp	#32
		bne	.done
.rest:		lda	#BLK_REST
		sta	mo_t, x
		lda	mo_ph, x
		inc	a
		and	#3
		sta	mo_ph, x
.done:		plp				; On it: down or up with it (his feet on
		php				; its new top).
		jsr	mo_block_rect
		plp
		bcc	mo_snap_r
		; (fall through)
; mo_snap - Rastan stands on slot X's platform top: p_y = top - 25.
mo_snap:	lda	mo_pf, x
		beq	mo_snap_r
		lda	mo_ptl, x
		sec
		sbc	#25
		sta	<p_y
		lda	mo_pth, x
		sbc	#0
		sta	<p_y + 1
mo_snap_r:	rts

; mo_block_rect - x - 16 .. x + 16, top y - mo_v; none when under.
mo_block_rect:	stz	mo_pf, x
		lda	mo_v, x
		beq	.r
		lda	mo_xl, x
		sec
		sbc	#16
		sta	mo_px0l, x
		lda	mo_xh, x
		sbc	#0
		sta	mo_px0h, x
		lda	mo_xl, x
		clc
		adc	#16
		sta	mo_px1l, x
		lda	mo_xh, x
		adc	#0
		sta	mo_px1h, x
		lda	mo_yl, x
		sec
		sbc	mo_v, x
		sta	mo_ptl, x
		lda	mo_yh, x
		sbc	#0
		sta	mo_pth, x
		inc	mo_pf, x
.r:		rts

; mo_on_plat - carry set if Rastan stands on slot X's platform (rect as set):
; on the ground, his feet (p_y + 25) in its top 8 px, p_x - 6 or + 6 over it.
mo_on_plat:	lda	mo_pf, x
		beq	.no
		ldy	<p_state
		lda	.ground, y
		beq	.no
		lda	<p_y			; feet - top in 0 .. 7?
		clc
		adc	#25
		sta	<etmp
		lda	<p_y + 1
		adc	#0
		sta	<etmp + 1
		lda	<etmp
		sec
		sbc	mo_ptl, x
		tay
		lda	<etmp + 1
		sbc	mo_pth, x
		bne	.no
		cpy	#8
		bcs	.no
		lda	<p_x			; p_x + 6 >= x0 and p_x - 6 < x1
		clc
		adc	#6
		sta	<etmp
		lda	<p_x + 1
		adc	#0
		sta	<etmp + 1
		lda	<etmp
		cmp	mo_px0l, x
		lda	<etmp + 1
		sbc	mo_px0h, x
		bmi	.no
		lda	<etmp
		sec
		sbc	#12
		sta	<etmp
		lda	<etmp + 1
		sbc	#0
		sta	<etmp + 1
		lda	<etmp
		cmp	mo_px1l, x
		lda	<etmp + 1
		sbc	mo_px1h, x
		bpl	.no
		sec
		rts
.no:		clc
		rts
.ground:	db	1, 1, 1, 0, 1, 1, 0, 0, 0, 0, 1	; (ST_STAND .. ST_UATK)

; Wall spears: mo_v px out (WSP_IN at rest), mo_ph 0 resting, 1 thrusting,
; 2 holding, 3 drawing back.
mo_wspear:	lda	mo_ph, x
		beq	.wait
		cmp	#2
		beq	.wait
		cmp	#1
		bne	.back
		inc	mo_v, x
		inc	mo_v, x
		lda	mo_v, x
		cmp	#WSP_OUT
		bne	.touch
		lda	#3
		bra	.ph
.back:		dec	mo_v, x
		dec	mo_v, x
		lda	mo_v, x
		cmp	#WSP_IN
		bne	.touch
		lda	#WSP_REST
.ph:		sta	mo_t, x
		lda	mo_ph, x
		inc	a
		and	#3
		sta	mo_ph, x
		bra	.touch
.wait:		dec	mo_t, x
		bne	.touch
		lda	mo_ph, x
		inc	a
		sta	mo_ph, x
.touch:		lda	mo_v, x			; Out: x - out .. x, y - 16 .. y + 16.
		cmp	#WSP_IN + 1
		bcc	.r
		lda	mo_xl, x
		sec
		sbc	mo_v, x
		sta	<ex
		lda	mo_xh, x
		sbc	#0
		sta	<ex + 1
		lda	mo_v, x
		sta	<ctmp
		lda	#16
		ldy	#32
		jsr	mo_touch
		bcc	.r
		phx
		lda	#$FF			; Knocked back away from the wall.
		ldy	#HIT_DAMAGE
		jsr	player_hit
		plx
.r:		rts

; Floor spears and rock spikes: mo_v px out of the floor (2 at rest), mo_ph 0
; resting, 1 rising, 2 holding, 3 sinking.
mo_spike:	lda	mo_ph, x
		beq	.wait
		cmp	#2
		beq	.wait
		cmp	#1
		bne	.sink
		inc	mo_v, x
		inc	mo_v, x
		lda	mo_v, x
		cmp	#SPK_TOP
		bne	.touch
		lda	#SPK_HOLD
		bra	.ph
.sink:		dec	mo_v, x
		dec	mo_v, x
		lda	mo_v, x
		cmp	#2
		bne	.touch
		lda	#SPK_REST
.ph:		sta	mo_t, x
		lda	mo_ph, x
		inc	a
		and	#3
		sta	mo_ph, x
		bra	.touch
.wait:		dec	mo_t, x
		bne	.touch
		lda	mo_ph, x
		inc	a
		sta	mo_ph, x
.touch:		lda	mo_v, x			; 8 px or more out: x0 .. x0 + w, y - out .. y.
		cmp	#8
		bcc	.r
		ldy	mo_kind, x
		lda	mo_xl, x
		sec
		sbc	.left - MK_FSPEAR, y
		sta	<ex
		lda	mo_xh, x
		sbc	#0
		sta	<ex + 1
		lda	.wide - MK_FSPEAR, y
		sta	<ctmp
		lda	mo_v, x
		tay
		jsr	mo_touch
		bcc	.r
	.if	GOD_MODE			; (test builds: nothing hurts him)
		rts
	.endif
		lda	<p_state
		cmp	#ST_DEAD
		beq	.r
		phx
		jsr	enter_dead		; Pierced.
		plx
.r:		rts
.left:		db	24, 14			; (floor spears, rock spikes)
.wide:		db	32, 32

; mo_touch - carry set if Rastan's body (p_x +/- 12, p_y - 24 .. p_y + 24)
; overlaps the box ex .. ex + ctmp, (y - A) .. (y - A + Y) of slot X
; (A, Y, ctmp < 128).
mo_touch:	sty	<etmp + 1		; (height)
		sta	<etmp
		lda	<dbg_god
		bne	.no
		lda	<ex			; cx = ex - p_x
		sec
		sbc	<p_x
		sta	<cx
		lda	<ex + 1
		sbc	<p_x + 1
		sta	<cx + 1
		lda	<cx			; ex < p_x + 12: cx - 12 < 0
		sec
		sbc	#12
		lda	<cx + 1
		sbc	#0
		bpl	.no
		lda	<cx			; p_x - 12 < ex + w: cx + w + 12 > 0
		clc
		adc	<ctmp
		sta	<cx
		lda	<cx + 1
		adc	#0
		sta	<cx + 1
		lda	<cx
		clc
		adc	#12
		tay
		lda	<cx + 1
		adc	#0
		bmi	.no
		bne	.xok
		cpy	#0
		beq	.no
.xok:		lda	mo_yl, x		; cy = (y - A) - p_y
		sec
		sbc	<etmp
		sta	<cy
		lda	mo_yh, x
		sbc	#0
		sta	<cy + 1
		lda	<cy
		sec
		sbc	<p_y
		sta	<cy
		lda	<cy + 1
		sbc	<p_y + 1
		sta	<cy + 1
		lda	<cy			; y0 < p_y + 24: cy - 24 < 0
		sec
		sbc	#24
		lda	<cy + 1
		sbc	#0
		bpl	.no
		lda	<cy			; p_y - 24 < y0 + h: cy + h + 24 > 0
		clc
		adc	<etmp + 1
		sta	<cy
		lda	<cy + 1
		adc	#0
		sta	<cy + 1
		lda	<cy
		clc
		adc	#24
		tay
		lda	<cy + 1
		adc	#0
		bmi	.no
		bne	.yes
		cpy	#0
		beq	.no
.yes:		sec
		rts
.no:		clc
		rts

; ---------------------------------------------------------------------------
; mobj_cells - upload the round's cells to MOB_VRAM (display off: a restart).

mobj_cells:	ldx	<cur_round
		lda	mo_cells_l - 2, x
		sta	ram_tia + 1
		lda	mo_cells_h - 2, x
		sta	ram_tia + 2
		lda	mo_csize_l - 2, x
		sta	ram_tia + 5
		lda	mo_csize_h - 2, x
		sta	ram_tia + 6
		lda	#^mobj_cells_r2
		tam3
		php
		sei
		st0	#VDC_MAWR
		st1	#<MOB_VRAM
		st2	#>MOB_VRAM
		st0	#VDC_VWR
		jsr	ram_tia
		lda	#128			; (ram_tia back to its usual length)
		sta	ram_tia + 5
		stz	ram_tia + 6
		plp
		rts
mo_cells_l:	db	<mobj_cells_r2, <mobj_cells_r3
mo_cells_h:	db	>mobj_cells_r2, >mobj_cells_r3
mo_csize_l:	db	<(MOBJ_R2_CELLS * 128), <(MOBJ_R3_CELLS * 128)
mo_csize_h:	db	>(MOBJ_R2_CELLS * 128), >(MOBJ_R3_CELLS * 128)

; ---------------------------------------------------------------------------
; mobj_draw - SATB entries from satb_n (after Rastan's and the props').

mobj_draw:	php
		sei
		st0	#VDC_MAWR
		lda	<satb_n			; SATB_ADDR + satb_n * 4 ($7F00: low byte 0)
		asl	a
		asl	a
		sta	VDC_DL
		lda	#>SATB_ADDR
		sta	VDC_DH
		st0	#VDC_VWR
		stz	mo_cnt
		ldx	#MO_MAX - 1
.loop:		lda	mo_ent, x
		bmi	.next
		; Anchor on screen: ex = x - scroll_x + 32, ey = y - scroll_y + 64.
		lda	mo_xl, x
		sec
		sbc	<scroll_x
		sta	<ex
		lda	mo_xh, x
		sbc	<scroll_x + 1
		sta	<ex + 1
		lda	<ex
		clc
		adc	#32
		sta	<ex
		bcc	!+
		inc	<ex + 1
!:		lda	mo_yl, x
		sec
		sbc	<scroll_y
		sta	<ey
		lda	mo_yh, x
		sbc	<scroll_y + 1
		sta	<ey + 1
		lda	<ey
		clc
		adc	#64
		sta	<ey
		bcc	!+
		inc	<ey + 1
!:		lda	mo_kind, x
		asl	a
		tay
		lda	.kinds, y
		sta	<etmp
		lda	.kinds + 1, y
		sta	<etmp + 1
		phx
		jsr	.call
		plx
.next:		dex
		bpl	.loop
		lda	<satb_n
		clc
		adc	mo_cnt
		sta	<satb_n
		plp
		rts
.call:		jmp	[etmp]
.kinds:		dw	dr_log, dr_block, dr_mud, dr_wspear, dr_fspear, dr_riser

; mo_piece - one SATB entry: A = dx, Y = dy (signed, from the anchor ex, ey),
; cell number and palette in mo_cell, mo_pal (round's set). Skipped off screen
; or when MOB_ENTRIES are written.
		.bss
mo_cell:	ds	1
mo_pal:		ds	1
		.code
mo_piece:	pha
		lda	mo_cnt
		cmp	#MOB_ENTRIES
		pla
		bcc	!+
		rts
!:
		; screen x + 32 = ex + dx: visible if 16 < it < 288 (unsigned 16-bit)
		pha
		clc
		adc	<ex
		sta	<cx
		pla
		and	#$80
		beq	!+
		lda	#$FF
!:		adc	<ex + 1
		sta	<cx + 1
		bne	!+
		lda	<cx
		cmp	#17
		bcc	.r
		bra	.xok
!:		cmp	#1
		bne	.r
		lda	<cx
		cmp	#<288
		bcs	.r
.xok:		tya				; screen y + 64 = ey + dy: 49 .. 303
		pha
		clc
		adc	<ey
		sta	<cy
		pla
		and	#$80
		beq	!+
		lda	#$FF
!:		adc	<ey + 1
		sta	<cy + 1
		bne	!+
		lda	<cy
		cmp	#49
		bcc	.r
		bra	.yok
!:		cmp	#1
		bne	.r
		lda	<cy
		cmp	#<304
		bcs	.r
.yok:		lda	<cy
		sta	VDC_DL
		lda	<cy + 1
		and	#3
		sta	VDC_DH
		lda	<cx
		sta	VDC_DL
		lda	<cx + 1
		and	#3
		sta	VDC_DH
		lda	mo_cell			; pattern = MOB_PAT + cell * 2
		asl	a
		clc
		adc	#<MOB_PAT
		sta	VDC_DL
		cla
		adc	#>MOB_PAT
		sta	VDC_DH
		lda	mo_pal
		ora	#$80			; (in front of the BG)
		sta	VDC_DL
		st2	#0
		inc	mo_cnt
.r:		rts

; mo_set - A = cell, Y = palette.
mo_set:		sta	mo_cell
		sty	mo_pal
		rts

dr_log:		lda	mo_v, x
		tay
		lda	mo_logtab, y
		sta	<ctmp
		lda	#MO2_LOG
		ldy	#MO2_LOG_PAL
		jsr	mo_set
		ldx	#4
!:		lda	<ctmp
		cly
		jsr	mo_piece
		lda	<ctmp
		clc
		adc	#16
		sta	<ctmp
		dex
		bne	!-
		rts

; (blocks: round 2's or 3's cells, the same layout; a row from 2 px under
; the anchor on is under the surface, not drawn)
dr_block:	lda	mo_v, x
		bne	!+
		rts
!:		eor	#$FF			; dy of the top row: -v
		inc	a
		sta	<ctmp
		ldy	<cur_round
		lda	.blk0 - 2, y
		sta	<ctmp + 1		; (its first cell)
		lda	.pal - 2, y
		sta	mo_pal
		lda	<ctmp + 1
		sta	mo_cell
		lda	#-16
		ldy	<ctmp
		jsr	mo_piece
		inc	mo_cell
		cla
		ldy	<ctmp
		jsr	mo_piece
		lda	<ctmp			; The bottom row, 16 lower.
		clc
		adc	#16
		sta	<ctmp
		bmi	!+
		cmp	#2
		bcs	.r
!:		inc	mo_cell
		lda	#-16
		ldy	<ctmp
		jsr	mo_piece
		inc	mo_cell
		cla
		ldy	<ctmp
		jsr	mo_piece
.r:		rts
.blk0:		db	MO2_BLK0, MO3_BLK0
.pal:		db	MO2_BLK0_PAL, MO3_BLK0_PAL

dr_mud:		ldx	#7
!:		lda	.cell, x
		ldy	#MO2_MUD0_PAL
		jsr	mo_set
		lda	.dx, x
		ldy	.dy, x
		jsr	mo_piece
		dex
		bpl	!-
		rts
.cell:		db	MO2_MUD0, MO2_MUD1, MO2_MUD2, MO2_MUD3, MO2_MUD4, MO2_MUD5, MO2_MUD6, MO2_MUD7
.dx:		db	-14, 2, -14, 2, -14, 2, -14, 2
.dy:		db	-48, -48, -32, -32, -16, -16, 0, 0

; Wall spears: per spear (dy -16 and 0) its mount at +2, its tip at -out and
; shafts every 16 px after the tip while left of the mount (dx < 0).
dr_wspear:	lda	mo_v, x
		sta	<ctmp + 1
		lda	#-16
		sta	<ctmp
		lda	#MO3_WSP_MNT0
		jsr	.spear
		stz	<ctmp
		lda	#MO3_WSP_MNT1
.spear:		ldy	#MO3_WSP_MNT0_PAL
		jsr	mo_set
		lda	#2
		ldy	<ctmp
		jsr	mo_piece
		lda	#MO3_WSP_TIP
		ldy	#MO3_WSP_TIP_PAL
		jsr	mo_set
		lda	<ctmp + 1
		eor	#$FF
		inc	a
		sta	<etmp			; dx of the tip
.shaft:		lda	<etmp
		ldy	<ctmp
		jsr	mo_piece
		lda	#MO3_WSP_SHAFT
		sta	mo_cell
		lda	<etmp
		clc
		adc	#16
		sta	<etmp
		bmi	.shaft
		rts

; Floor spears: two (dx -24 and -8), each its cover at 0, its head at -out and
; shafts every 16 px below the head while above the floor (dy < 0).
dr_fspear:	lda	mo_v, x
		eor	#$FF
		inc	a
		sta	<ctmp + 1		; dy of the heads
		lda	#-24
		sta	<ctmp
		lda	#MO3_FSP_BASE0
		jsr	.spear
		lda	#-8
		sta	<ctmp
		lda	#MO3_FSP_BASE1
.spear:		ldy	#MO3_FSP_BASE0_PAL
		jsr	mo_set
		lda	<ctmp
		cly
		jsr	mo_piece
		lda	#MO3_FSP_HEAD
		ldy	#MO3_FSP_HEAD_PAL
		jsr	mo_set
		lda	<ctmp + 1
		sta	<etmp
.shaft:		lda	<ctmp
		ldy	<etmp
		jsr	mo_piece
		lda	#MO3_FSP_SHAFT
		sta	mo_cell
		lda	<etmp
		clc
		adc	#16
		sta	<etmp
		bmi	.shaft
		rts

; Rock spikes: the base halves at 0 (dx -14 and 2); the spike's tip and shaft
; at dx -6 from -out down, the side spikes in pairs (dx -14 and 2) 32 and 48
; below the tip, each piece while above the floor.
dr_riser:	lda	#MO3_RIS_B0
		ldy	#MO3_RIS_B0_PAL
		jsr	mo_set
		lda	#-14
		cly
		jsr	mo_piece
		lda	#MO3_RIS_B1
		sta	mo_cell
		lda	#2
		cly
		jsr	mo_piece
		lda	mo_v, x
		eor	#$FF
		inc	a
		sta	<ctmp			; dy of the tip
		ldx	#0
.piece:		lda	<ctmp
		clc
		adc	.dy, x
		bpl	.next			; (at or under the floor)
		tay
		lda	.cell, x
		sta	mo_cell
		lda	#MO3_RIS0_PAL
		sta	mo_pal
		lda	.dx, x
		jsr	mo_piece
.next:		inx
		cpx	#6
		bne	.piece
		rts
.cell:		db	MO3_RIS0, MO3_RIS1, MO3_RIS2, MO3_RIS3, MO3_RIS4, MO3_RIS5
.dx:		db	-6, -6, -14, 2, -14, 2
.dy:		db	0, 16, 32, 32, 48, 48

; ---------------------------------------------------------------------------
; The rounds' map objects (the arcade objects' anchors, from build/r2run.snp
; and r3run.snp): kind, x, y, the frames of its first wait.

MOBJ		.macro
		db	\1
		dw	\2, \3
		db	\4
		.endm

mo_tabs:	dw	mo_tab_r2, mo_tab_r3
mo_tab_r2:	MOBJ	MK_LOG, 1831, 328, LOG_REST	; (markers $59-$5D)
		MOBJ	MK_LOG, 1958, 328, LOG_REST
		MOBJ	MK_LOG, 2086, 328, LOG_REST
		MOBJ	MK_LOG, 2214, 328, LOG_REST
		MOBJ	MK_LOG, 2342, 328, LOG_REST
		MOBJ	MK_MUD, 2670, 360, 0		; ($5E-$60)
		MOBJ	MK_MUD, 2766, 360, 0
		MOBJ	MK_MUD, 2894, 360, 0
		MOBJ	MK_LOG, 5734, 296, LOG_REST	; ($59, $5A)
		MOBJ	MK_LOG, 5862, 296, LOG_REST
		MOBJ	MK_BLOCK, 6479, 336, 56		; ($61-$63)
		MOBJ	MK_BLOCK, 6543, 336, 56
		MOBJ	MK_BLOCK, 6607, 336, 56
		db	$FF
mo_tab_r3:	MOBJ	MK_WSPEAR, 3837, 304, 82	; ($65, $66)
		MOBJ	MK_WSPEAR, 3968, 240, 82
		MOBJ	MK_FSPEAR, 4055, 448, 42	; ($46)
		MOBJ	MK_FSPEAR, 4822, 448, 1		; ($6C, $6D)
		MOBJ	MK_FSPEAR, 4887, 384, 42
		MOBJ	MK_BLOCK, 5446, 368, 56		; ($6E-$70)
		MOBJ	MK_BLOCK, 5510, 368, 56
		MOBJ	MK_BLOCK, 5574, 368, 56
		MOBJ	MK_RISER, 6766, 480, 42		; ($71, $72)
		MOBJ	MK_RISER, 6894, 448, 42
		MOBJ	MK_FSPEAR, 8630, 256, 42	; (the castle: $46, $6C, $46)
		MOBJ	MK_FSPEAR, 8694, 256, 1
		MOBJ	MK_FSPEAR, 9047, 224, 42
		db	$FF
