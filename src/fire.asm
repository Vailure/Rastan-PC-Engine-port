; ***************************************************************************
;
; Rastan - the lava hall's fire (arcade markers $4C, $52-$55).
;
; The arcade draws a row of 32x32 flames along the lava, four phases of four
; cells a phase every 4 frames, neighbouring blocks a phase apart. The port
; has them in the tile map instead (tools/pce_stage.py): the strip's cells
; show 32 fixed tiles at FIRE_TILE0 (VRAM $4C00, the stage props' cells,
; which only the cave block outside uses), the even blocks' 16 then the odd
; blocks', and this rewrites them: even blocks phase p, odd blocks p + 1.
;
; In DEBUG_BANK (MPR2, always mapped). Data: build/stage1/fire.bin, 4 phases
; of 16 tiles (32 bytes each).
;
; ***************************************************************************

FIRE_VRAM	=	R1_FIRE_TILE0 << 4

		.zp
fire_t:		ds	1		; Frame count: the phase is bits 2-3.
fire_on:	ds	1		; The tiles are in VRAM (bg_palettes clears it).

		.code

; fire_update - once a frame, in VBLANK.
fire_update:
		R1_ONLY				; (round 1's own: none in other rounds yet)
		lda	<bg_set			; Outdoors the tiles are the props'.
		bne	!+
		stz	<fire_on
		rts
!:		jsr	column_cells		; (the castle: the column's cells, once)
	.if	BG_CHECK | CAMERA_TEST		; (test builds: still, at phase 0, as
		lda	<fire_on		; the converter's preview shows it)
		bne	fire_done
		cla
		bra	fire_phase
	.else
		inc	<fire_t
		lda	<fire_on		; (just loaded: the tiles at once)
		beq	!+
		lda	<fire_t
		and	#3
		bne	fire_done
!:		lda	<fire_t
		lsr	a
		lsr	a
		and	#3
	.endif
		; (fall through)
; fire_phase - A = phase: even blocks' tiles that phase, odd blocks' the next.
fire_phase:	php
		sei
		pha
		lda	#^fire_data
		tam3
		st0	#VDC_MAWR
		st1	#<FIRE_VRAM
		st2	#>FIRE_VRAM
		st0	#VDC_VWR
		lda	#<VDC_DL		; ram_tia: tia src, VDC_DL, 512
		sta	ram_tia + 3
		lda	#>VDC_DL
		sta	ram_tia + 4
		stz	ram_tia + 5
		lda	#2
		sta	ram_tia + 6
		pla
		pha
		jsr	fire_half			; Even blocks: phase A,
		pla
		inc	a			; odd blocks: the next.
		jsr	fire_half
		lda	#1
		sta	<fire_on
		lda	#128			; (ram_tia back to its usual length)
		sta	ram_tia + 5
		stz	ram_tia + 6
		plp
fire_done:	rts
fire_half:	and	#3			; src = fire_data + phase * 512
		asl	a
		clc
		adc	#>fire_data
		sta	ram_tia + 2
		lda	#<fire_data
		sta	ram_tia + 1
		jmp	ram_tia
