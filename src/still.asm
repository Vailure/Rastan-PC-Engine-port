; ***************************************************************************
;
; Rastan - still screens: the arcade's title, its GAME OVER and its
; round-clear screen ("YOU ARE A BRAVE FIGHTER..."), each converted whole by
; tools/pce_still.py into tiles, a 32x28 tile map and palettes. They replace the stage in VRAM for a moment; the
; stage is streamed in again from scratch afterwards (checkpoint_start).
;
; Lives in DEBUG_BANK (MPR2, always mapped). Data: one incbin per still,
; mapped into MPR3/MPR4 ($6000-$9FFF, at most 16 KB).
;
; ***************************************************************************

STILL_ENDING	=	0
STILL_TITLE	=	1
STILL_GAMEOVER	=	2

		.zp
st_ptr:		ds	2		; Source, $6000 up.
st_cnt:		ds	2		; Words to go.
st_n:		ds	1		; The still shown.
st_t:		ds	2		; Frames it has been up.
still_on:	ds	1		; A still is up (tools/audit.py: no game frames then).

		.code

still_bank:	db	^still_ending, ^still_title, ^still_gameover
still_map_l:	db	<($6000 + ENDING_MAP_OFS), <($6000 + TITLE_MAP_OFS), <($6000 + GAMEOVER_MAP_OFS)
still_map_h:	db	>($6000 + ENDING_MAP_OFS), >($6000 + TITLE_MAP_OFS), >($6000 + GAMEOVER_MAP_OFS)
still_pal_l:	db	<($6000 + ENDING_PAL_OFS), <($6000 + TITLE_PAL_OFS), <($6000 + GAMEOVER_PAL_OFS)
still_pal_h:	db	>($6000 + ENDING_PAL_OFS), >($6000 + TITLE_PAL_OFS), >($6000 + GAMEOVER_PAL_OFS)
still_tiles_l:	db	<(ENDING_TILES * 16), <(TITLE_TILES * 16), <(GAMEOVER_TILES * 16)	; Words.
still_tiles_h:	db	>(ENDING_TILES * 16), >(TITLE_TILES * 16), >(GAMEOVER_TILES * 16)
still_pals:	db	ENDING_PALS, TITLE_PALS, GAMEOVER_PALS
still_hud:	db	1, 0, 1			; The HUD's top line (score) shown?

; ---------------------------------------------------------------------------
; still_show - X = STILL_*: cut to it (sprites gone, but for the HUD's top
; line where the arcade shows it) and show it from the next VBLANK.

still_show:	stx	<st_n
		lda	#1
		sta	<still_on
		jsr	screen_cut
		php
		sei
		st0	#VDC_MAWR		; The SATB: the HUD's entries, then
		st1	#<SATB_ADDR		; nothing.
		st2	#>SATB_ADDR
		st0	#VDC_VWR
		clx				; (256 words: 64 entries)
!:		st1	#0
		st2	#0
		dex
		bne	!-
		ldx	<st_n
		lda	still_hud, x
		beq	.nohud
		jsr	hud_satb
		st0	#VDC_MAWR		; ... less its bottom line (entries 0-6).
		st1	#<SATB_ADDR
		st2	#>SATB_ADDR
		st0	#VDC_VWR
		ldx	#7 * 4
!:		st1	#0
		st2	#0
		dex
		bne	!-
.nohud:		lda	#64			; (and enemies_draw clears from the
		sta	<en_satb_prev		; start when the stage comes back)

		st0	#VDC_MAWR		; The BAT: blank (tile 0, $1000).
		st1	#0
		st2	#0
		st0	#VDC_VWR
		ldy	#16			; 64 x 64 words.
		clx
!:		st1	#$00
		st2	#$01
		dex
		bne	!-
		dey
		bne	!-

		ldx	<st_n
		lda	still_bank, x
		tam3
		inc	a
		tam4
		st0	#VDC_MAWR		; Tiles from VRAM $1000.
		st1	#$00
		st2	#$10
		st0	#VDC_VWR
		stz	<st_ptr
		lda	#$60
		sta	<st_ptr + 1
		lda	still_tiles_l, x
		sta	<st_cnt
		lda	still_tiles_h, x
		sta	<st_cnt + 1
		jsr	still_copy

		lda	still_map_l, x		; The map: 28 rows of 32, BAT rows 0-27.
		sta	<st_ptr
		lda	still_map_h, x
		sta	<st_ptr + 1
		cly
.row:		st0	#VDC_MAWR
		tya				; MAWR = row * 64
		lsr	a
		lsr	a
		pha
		tya
		asl	a
		asl	a
		asl	a
		asl	a
		asl	a
		asl	a
		sta	VDC_DL
		pla
		sta	VDC_DH
		st0	#VDC_VWR
		lda	#32
		sta	<st_cnt
		stz	<st_cnt + 1
		phy
		jsr	still_copy
		ply
		iny
		cpy	#28
		bne	.row

		ldx	<st_n			; Palettes, from BG palette 0.
		lda	still_pal_l, x
		sta	<st_ptr
		lda	still_pal_h, x
		sta	<st_ptr + 1
		lda	still_pals, x
		asl	a			; x 16 words
		asl	a
		asl	a
		asl	a
		tax
		stz	VCE_CTA + 0
		stz	VCE_CTA + 1
		cly
!:		lda	[st_ptr], y
		sta	VCE_CTW + 0
		iny
		lda	[st_ptr], y
		sta	VCE_CTW + 1
		iny
		bne	!+
		inc	<st_ptr + 1
!:		dex
		bne	!--

		st0	#VDC_BXR		; Scrolled to the corner.
		st1	#0
		st2	#0
		st0	#VDC_BYR
		st1	#0
		st2	#0
		plp
		call	wait_vsync
		call	set_dspon		; (colour 0 stays black, as converted)
		call	wait_vsync
		rts

; still_copy - st_cnt words from [st_ptr] to the VRAM write address.
still_copy:	cly
.w:		lda	<st_cnt
		ora	<st_cnt + 1
		beq	.r
		lda	[st_ptr], y
		sta	VDC_DL
		iny
		lda	[st_ptr], y
		sta	VDC_DH
		iny
		bne	!+
		inc	<st_ptr + 1
!:		lda	<st_cnt
		bne	!+
		dec	<st_cnt + 1
!:		dec	<st_cnt
		bra	.w
.r:		tya
		clc
		adc	<st_ptr
		sta	<st_ptr
		bcc	!+
		inc	<st_ptr + 1
!:		rts

; still_end - back from a still: the stage's colours and the HUD's sprites
; (the caller then restarts the stage, which streams its tiles in again).
still_end:	stz	<still_on
		jsr	screen_cut		; (stage_start loads the palettes)
		php
		sei
		jsr	hud_satb
		plp
		rts

; still_wait - Y:X frames (Y = high + 1), or until RUN once A frames have gone
; (A = 0: no RUN). The music plays on.
still_wait:	sta	<st_t + 1
		stz	<st_t
.wait:		phx
		phy
		call	wait_vsync
		jsr	sound_update
		ply
		plx
		lda	<st_t + 1		; RUN counts once st_t + 1 frames are up.
		beq	.time
		inc	<st_t
		cmp	<st_t
		bcs	.time
		lda	joytrg
		bit	#JOY_RUN
		bne	.r
.time:		dex
		bne	.wait
		dey
		bne	.wait
.r:		rts

; ---------------------------------------------------------------------------
; title_screen - the arcade's title, "PUSH RUN BUTTON" blinking, until RUN:
; then a new game (3 lives, no score) from the start of round 1. UP + SELECT
; held (the debug build: SELECT) opens the debug menu, a screen of its own
; (title_menu): it starts the new game where and as it says, or comes back
; here. There is no debug menu in play.

title_screen:
	.if	TITLE
		jsr	sound_stop
		ldx	#STILL_TITLE
		jsr	still_show
		stz	<st_t
.loop:		call	wait_vsync
		inc	<st_t
		lda	<st_t			; Every 32 frames: on, off.
		and	#$1F
		bne	.key
		lda	<st_t
		and	#$20
		jsr	title_blink
.key:
	.if	DEBUG_MENU			; The debug build: SELECT alone opens
		lda	joytrg			; the debug menu.
		bit	#JOY_SEL
		bne	.open
	.endif
		lda	joynow			; UP + SELECT held: the debug menu.
		and	#JOY_SEL | JOY_U
		cmp	#JOY_SEL | JOY_U
		beq	.held
		stz	<dbg_hold
		lda	joytrg
		bit	#JOY_RUN
		beq	.loop
		bra	.start
.held:		inc	<dbg_hold
		lda	<dbg_hold
		cmp	#DBG_HOLD
		bcc	.loop
.open:		stz	<dbg_hold		; The debug menu, a screen of its own
		jsr	title_menu		; (src/debug.asm): it sets the checkpoint,
		bcs	.chosen			; the lives and the weapon, or goes back.
		ldx	#STILL_TITLE
		jsr	still_show
		stz	<st_t
		bra	.loop
.chosen:	jsr	still_end
		bra	.new
.start:		stz	<dbg_hold
		jsr	still_end
	.endif					; (test builds: straight into a new game)
		lda	#START_LIVES
		sta	<lives
		stz	<cur_cp
.new:		stz	<score
		stz	<score + 1
		stz	<score + 2
		jmp	hud_reset

; title_blink - A = 0: "PUSH RUN BUTTON" shown, else hidden (its palette's
; colours, or black).
title_blink:	php
		sei
		pha
		lda	#^still_title
		tam3
		inc	a
		tam4
		lda	#<(TITLE_BLINK_PAL * 16 + 1)
		sta	VCE_CTA + 0
		stz	VCE_CTA + 1
		pla
		ldx	#15
		cly
.c:		cmp	#0
		beq	.on
		stz	VCE_CTW + 0
		stz	VCE_CTW + 1
		bra	.n
.on:		lda	$6000 + TITLE_PAL_OFS + TITLE_BLINK_PAL * 32 + 2, y
		sta	VCE_CTW + 0
		lda	$6000 + TITLE_PAL_OFS + TITLE_BLINK_PAL * 32 + 3, y
		sta	VCE_CTW + 1
		cla
.n:		iny
		iny
		dex
		bne	.c
		plp
		rts

; ---------------------------------------------------------------------------
; game_over - the last life is gone: the arcade's GAME OVER (with the score)
; for 4 s (RUN skips it after 1 s), then the title.

game_over:	jsr	sound_stop
		ldx	#STILL_GAMEOVER
		jsr	still_show
		ldx	#<240
		ldy	#(>240) + 1
		lda	#60
		jsr	still_wait
		jsr	title_screen
		jsr	stage_start
		jmp	start_weapon

; ---------------------------------------------------------------------------
; round_end - the boss is dead: the arcade's round-clear screen with its
; jingle (RUN skips it after 2 s), then, with only round 1 ported, the title.

ROUND_END_FRAMES =	420			; The arcade: this screen, then "ROUND 2
						; READY", 7 s in all before round 2.
round_end:	jsr	sound_stop
		ldx	#STILL_ENDING
		jsr	still_show
		lda	#SND_CLEAR
		jsr	sound_music
		ldx	#<ROUND_END_FRAMES
		ldy	#(>ROUND_END_FRAMES) + 1
		lda	#120
		jsr	still_wait
		jsr	title_screen
		jsr	stage_start
		jmp	start_weapon
