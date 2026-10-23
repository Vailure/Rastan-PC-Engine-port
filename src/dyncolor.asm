;***************************************************************************
;
; Run-time BG color changes, measured in the arcade (tools/pce_stage.py):
;  - the waterfalls cycle 4 color states, 8 frames each;
;  - the sky darkens toward dusk in DYN_SKY_N steps, each while the arcade
;    streams the column 2 before an odd segment (190, 318, ... 958:
;    dyn_sky_col); a restart shows its checkpoint's step (cp_sky).
; The converter gives these colors palette slots of their own and emits the
; VCE update lists in dyncolor.inc. Updates run in VBLANK (VCE writes during
; the display can speckle on real hardware).
;
;***************************************************************************

		.zp
dyn_timer:	ds	1
dyn_phase:	ds	1
dyn_sky:	ds	1
dyn_ptr:	ds	2

		.code

; dyn_reset - a (re)start: first cycle state, the checkpoint's sky (the
; arcade's restart loads the step its checkpoint is at).
dyn_reset:	stz	<dyn_timer
		stz	<dyn_phase
		lda	#^dyn_sky_col
		tam3
		lda	#<dyn_cycle0
		ldx	#>dyn_cycle0
		jsr	vce_list
	.if	BG_CHECK			; (bgcheck: the colours as converted)
		cla
	.else
		ldx	<cur_cp
		lda	cp_sky, x
	.endif
		sta	<dyn_sky
		tax
		lda	dyn_sky_l, x
		pha
		lda	dyn_sky_h, x
		tax
		pla
		jmp	vce_list

; dyn_update - once a frame, in VBLANK.
dyn_update:	lda	#^dyn_sky_col
		tam3
		inc	<dyn_timer
		lda	<dyn_timer
		and	#7
		bne	.sky
		lda	<dyn_phase
		inc	a
		and	#3
		sta	<dyn_phase
		asl	a
		tay
		lda	.cycles, y
		ldx	.cycles + 1, y
		jsr	vce_list
.sky:		lda	<dyn_sky		; next_col > the next step's column: on.
		inc	a
		cmp	#DYN_SKY_N
		bcs	.done
		asl	a
		tax
		lda	dyn_sky_col, x
		cmp	<next_col
		lda	dyn_sky_col + 1, x
		sbc	<next_col + 1
		bcs	.done
		inc	<dyn_sky
		ldx	<dyn_sky
		lda	dyn_sky_l, x
		pha
		lda	dyn_sky_h, x
		tax
		pla
		jmp	vce_list
.done:		rts
.cycles:	dw	dyn_cycle0, dyn_cycle1, dyn_cycle2, dyn_cycle3

; vce_list - A/X = list: count, then (VCE address, color) word pairs. (The
; pointer moves on a pair at a time: the sky's lists are well over 256 bytes.)
vce_list:	sta	<dyn_ptr
		stx	<dyn_ptr + 1
		lda	[dyn_ptr]
		beq	.done
		tax
		inc	<dyn_ptr		; (past the count)
		bne	.loop
		inc	<dyn_ptr + 1
.loop:		cly
		lda	[dyn_ptr], y
		sta	VCE_CTA + 0
		iny
		lda	[dyn_ptr], y
		sta	VCE_CTA + 1
		iny
		lda	[dyn_ptr], y
		sta	VCE_CTW + 0
		iny
		lda	[dyn_ptr], y
		sta	VCE_CTW + 1
		lda	<dyn_ptr
		clc
		adc	#4
		sta	<dyn_ptr
		bcc	!+
		inc	<dyn_ptr + 1
!:		dex
		bne	.loop
.done:		rts

; (The lists, dyncolor.inc, are in data bank $08: mapped into MPR3 here.)
