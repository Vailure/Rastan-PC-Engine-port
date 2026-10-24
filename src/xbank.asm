; ***************************************************************************
;
; Rastan - the way into bank XBANK (src/main.asm): a routine there runs with
; XBANK in MPR2 ($4000) in place of DEBUG_BANK, which comes back after it. X
; and Y go through; A and the flags do not come back.
;
; ***************************************************************************

XCALL		.macro
x_\1:		lda	#XBANK
		tam2
		jsr	\1
		jmp	x_back
		.endm

		XCALL	garg_spawn
		XCALL	garg_think
		XCALL	jets_spawn
		XCALL	jet_think
		XCALL	snake_think
		XCALL	boss_spawn
		XCALL	boss_think
		XCALL	boss2_think
		XCALL	frag_think
		XCALL	kn_spawn
		XCALL	kn_think
		XCALL	kn2_think
		XCALL	orb_think
		XCALL	wz_spawn
		XCALL	wz_think
		XCALL	wf_think
		XCALL	column_reset
		XCALL	column_cells
		XCALL	column_update
		XCALL	column_draw
		XCALL	wall_update
		XCALL	wall_draw
		XCALL	weights_update
		XCALL	weights_draw

x_back:		lda	#DEBUG_BANK
		tam2
		rts
