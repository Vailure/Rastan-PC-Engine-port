; ***************************************************************************
;
; Rastan - the rounds in the ROM.
;
; Each round's stage data (line records, quads, patterns, collision map, BG
; palettes: tools/pce_stage.py, pce_coll.py) sits in an SF2 page of its own,
; round n in page n, at the same banks of every page (STAGE_BANK0 ... in
; main.asm), so the stream code reads any round's the same way once
; sf2_round has mapped its page. What differs between rounds besides (the
; length of its stream, its camera boxes, its lava hall's camera, its boss
; door's line) is copied into RAM by round_setup from the round's constants
; (build/stageN/stage.inc, stage_regions.inc).
;
; ***************************************************************************

NUM_ROUNDS	=	3
MAX_REGIONS	=	8		; Camera boxes a round may have.

		.zp
cur_round:	ds	1		; The round being played, 1 ...

		.bss
rd_lines:	ds	2		; Its number of stream lines,
rd_region_end:	ds	1		; the camera box after the last line,
rd_boss_line:	ds	2		; the first line past the boss room's door,
rd_rest_x0:	ds	2		; its lava hall's camera (src/player.asm:
rd_rest_x1:	ds	2		; cam_rest; x0 = x1: none),
rd_rest_y:	ds	2
region_free:	ds	MAX_REGIONS	; and its camera boxes (region_* as in
region_x0_l:	ds	MAX_REGIONS	; stage_regions.inc).
region_x0_h:	ds	MAX_REGIONS
region_x1_l:	ds	MAX_REGIONS
region_x1_h:	ds	MAX_REGIONS
region_y0_l:	ds	MAX_REGIONS
region_y0_h:	ds	MAX_REGIONS
region_y1_l:	ds	MAX_REGIONS
region_y1_h:	ds	MAX_REGIONS
		.code

; round_setup - the round cur_round: its page mapped, its constants in RAM,
; the HUD's "ROUND n".
round_setup:	ldx	<cur_round
		dex
		lda	rt_lines_l, x
		sta	rd_lines
		lda	rt_lines_h, x
		sta	rd_lines + 1
		lda	rt_region_end, x
		sta	rd_region_end
		lda	rt_boss_l, x
		sta	rd_boss_line
		lda	rt_boss_h, x
		sta	rd_boss_line + 1
		txa
		asl	a
		tay
		lda	rt_rest_x0, y
		sta	rd_rest_x0
		lda	rt_rest_x0 + 1, y
		sta	rd_rest_x0 + 1
		lda	rt_rest_x1, y
		sta	rd_rest_x1
		lda	rt_rest_x1 + 1, y
		sta	rd_rest_x1 + 1
		lda	rt_rest_y, y
		sta	rd_rest_y
		lda	rt_rest_y + 1, y
		sta	rd_rest_y + 1
		lda	rt_regions, y		; Camera boxes: the round's nine arrays of
		sta	<tmp			; n (consecutive), into nine of
		lda	rt_regions + 1, y	; MAX_REGIONS.
		sta	<tmp + 1
		lda	rd_region_end
		inc	a
		sta	<count
		clx				; (destination: region_free + k * 8)
.array:		phx
		cly
.copy:		lda	[tmp], y
		sta	region_free, x
		inx
		iny
		cpy	<count
		bne	.copy
		lda	<tmp			; Next source array.
		clc
		adc	<count
		sta	<tmp
		bcc	!+
		inc	<tmp + 1
!:		pla				; Next destination array.
		clc
		adc	#MAX_REGIONS
		tax
		cpx	#9 * MAX_REGIONS
		bne	.array
	.if	!CAMERA_TEST
		jsr	hud_round
	.endif
		; (fall through)

; sf2_round - the round's SF2 page into banks $40-$7F (stage stream,
; collision map, BG palettes). X and Y kept.
sf2_round:	phx
		ldx	<cur_round
		lda	rt_page - 1, x
		tax
		stz	$FFF0, x
		plx
		rts

; The rounds' constants.
rt_page:	db	(r1_page >> 6) - 1, (r2_page >> 6) - 1, (r3_page >> 6) - 1	; (the SF2 pages)
rt_lines_l:	db	<R1_STAGE_LINES, <R2_STAGE_LINES, <R3_STAGE_LINES
rt_lines_h:	db	>R1_STAGE_LINES, >R2_STAGE_LINES, >R3_STAGE_LINES
rt_region_end:	db	R1_STAGE_REGION_END, R2_STAGE_REGION_END, R3_STAGE_REGION_END
rt_boss_l:	db	<(R1_STAGE_DOOR_LINE + 1), <(R2_STAGE_DOOR_LINE + 1), <(R3_STAGE_DOOR_LINE + 1)
rt_boss_h:	db	>(R1_STAGE_DOOR_LINE + 1), >(R2_STAGE_DOOR_LINE + 1), >(R3_STAGE_DOOR_LINE + 1)
rt_rest_x0:	dw	R1_CAM_REST_X0, R2_CAM_REST_X0, R3_CAM_REST_X0
rt_rest_x1:	dw	R1_CAM_REST_X1, R2_CAM_REST_X1, R3_CAM_REST_X1
rt_rest_y:	dw	R1_CAM_REST_Y, R2_CAM_REST_Y, R3_CAM_REST_Y
rt_regions:	dw	r1_region_free, r2_region_free, r3_region_free

	.if	(R1_STAGE_REGION_END >= MAX_REGIONS) | (R2_STAGE_REGION_END >= MAX_REGIONS) | (R3_STAGE_REGION_END >= MAX_REGIONS)
	.fail	a round has more camera boxes than MAX_REGIONS
	.endif

		include	"stage1/stage_regions.inc"
		include	"stage2/stage_regions.inc"
		include	"stage3/stage_regions.inc"
