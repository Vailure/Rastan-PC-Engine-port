;***************************************************************************
;
; Run-time BG color changes, measured in the arcade (tools/pce_stage.py):
;  - the waterfalls cycle 4 color states, 8 frames each;
;  - the sky changes once, while the arcade streams the column just before
;    segment 3 (DYN_SKY_COLUMN).
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

; dyn_reset - start of the stage: first cycle state, the first sky.
dyn_reset:	stz	<dyn_timer
		stz	<dyn_phase
		stz	<dyn_sky
		lda	#<dyn_cycle0
		ldx	#>dyn_cycle0
		jsr	vce_list
		lda	#<dyn_sky_a
		ldx	#>dyn_sky_a
		jmp	vce_list

; dyn_update - once a frame, in VBLANK.
dyn_update:	inc	<dyn_timer
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
.sky:		lda	<dyn_sky
		bne	.done
		lda	<next_col + 1		; next_col > DYN_SKY_COLUMN: switch.
		cmp	#>DYN_SKY_COLUMN
		bcc	.done
		bne	.switch
		lda	<next_col
		cmp	#<DYN_SKY_COLUMN + 1
		bcc	.done
.switch:	inc	<dyn_sky
		lda	#<dyn_sky_b
		ldx	#>dyn_sky_b
		jmp	vce_list
.done:		rts
.cycles:	dw	dyn_cycle0, dyn_cycle1, dyn_cycle2, dyn_cycle3

; vce_list - A/X = list: count, then (VCE address, color) word pairs.
vce_list:	sta	<dyn_ptr
		stx	<dyn_ptr + 1
		lda	[dyn_ptr]
		beq	.done
		tax
		ldy	#1
.loop:		lda	[dyn_ptr], y
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
		iny
		bne	!+			; Lists can pass 256 bytes.
		inc	<dyn_ptr + 1
!:		dex
		bne	.loop
.done:		rts

		include	"dyncolor.inc"
