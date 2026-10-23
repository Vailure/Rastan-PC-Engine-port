; ***************************************************************************
;
; Rastan - music and sound effects on the PC Engine's PSG.
;
; The arcade's sound board is a Z80 with a YM2151: it keeps music on FM
; channels 0-5 and sound effects on 6-7. sim/snd runs that driver and logs its
; register writes; tools/pce_sound.py turns each tune and effect into a stream
; of what the PSG needs - per channel, a frequency and a volume - timed in the
; driver's own sequencer ticks (about 54.6 Hz, its YM2151 timer A).
;
; Music plays on PSG channels 0-5; an effect takes 4 and 5 while it sounds,
; and the music's last notes there are put back when it ends.
;
; Stream bytes (tools/pce_sound.py):
;   $FF        the music loops, an effect stops
;   $80 | mask channels 0-5 in mask change; three bytes each: period low,
;              period high (bit 7: strike the note again), volume 0-31
;   n          wait n + 1 ticks
;
; ***************************************************************************

SND_FIRST_SFX_CH =	4		; Effects take channels 4 and 5.

		.zp
snd_ptr:	ds	2		; Music stream, in MPR3/MPR4 ($6000-$9FFF).
snd_bank:	ds	1
snd_wait:	ds	1
snd_acc:	ds	1		; Ticks per frame, 8.8: the fraction so far.
snd_track:	ds	1		; Music playing + 1 ($00: none).
sfx_ptr:	ds	2
sfx_bank:	ds	1
sfx_wait:	ds	1
sfx_on:		ds	1
snd_tmp:	ds	1
snd_ch:		ds	1
sfx_f0:		ds	1
sfx_f1:		ds	1
sfx_v:		ds	1

		.bss
snd_freq_l:	ds	6		; What the music last set each channel to, so an
snd_freq_h:	ds	6		; effect can hand 4 and 5 back.
snd_vol:	ds	6

		.code

; ---------------------------------------------------------------------------
; sound_init - silence, and a waveform in every channel.

sound_init:	stz	<snd_track
		stz	<sfx_on
		stz	<snd_acc
		lda	#$FF			; Main volume, both sides.
		sta	PSG_VOL
		stz	PSG_LFO_CTRL
		clx
.ch:		stx	PSG_AR
		stz	PSG_CTRL		; Channel off: the waveform index resets.
		lda	#$FF
		sta	PSG_PAN
		cly
.wave:		lda	snd_waveform, y
		sta	PSG_WAVEFORM
		iny
		cpy	#32
		bne	.wave
		stz	PSG_CTRL
		stz	snd_vol, x
		inx
		cpx	#6
		bne	.ch
		stz	PSG_NOISE
		rts

; A 32-step wave, one period: the arcade's FM voices become this one timbre.
; Half a sine over the top and a flat trough reads as a soft square, which
; carries a melody better than a pure sine without the pure square's edge.
snd_waveform:	db	16, 19, 22, 25, 27, 29, 30, 31, 31, 31, 30, 29, 27, 25, 22, 19
		db	16, 13, 10,  7,  5,  3,  2,  1,  1,  1,  2,  3,  5,  7, 10, 13

; ---------------------------------------------------------------------------
; sound_music - A = SND_*: start a tune (it loops). sound_stop silences all.

sound_music:	cmp	#SND_MUSIC_COUNT
		bcs	sound_stop
		tax
		inc	a
		sta	<snd_track
		lda	snd_music_bank, x
		sta	<snd_bank
		lda	snd_music_lo, x
		sta	<snd_ptr
		lda	snd_music_hi, x
		sta	<snd_ptr + 1
		stz	<snd_wait
		stz	<snd_acc
		bra	snd_silence

sound_stop:	stz	<snd_track
		stz	<sfx_on
snd_silence:	clx
.ch:		stx	PSG_AR
		stz	PSG_CTRL
		stz	snd_vol, x
		inx
		cpx	#6
		bne	.ch
		rts

; ---------------------------------------------------------------------------
; sound_sfx - A = SFX_*: start an effect on channels 4 and 5.

sound_sfx:	cmp	#SND_SFX_COUNT
		bcs	.r
		tax
		lda	snd_sfx_bank, x
		sta	<sfx_bank
		lda	snd_sfx_lo, x
		sta	<sfx_ptr
		lda	snd_sfx_hi, x
		sta	<sfx_ptr + 1
		stz	<sfx_wait
		lda	#1
		sta	<sfx_on
.r:		rts

; ---------------------------------------------------------------------------
; sound_update - once a frame (in VBLANK). The streams run at the arcade
; driver's tick rate, so a fraction of a tick is carried frame to frame.

sound_update:	lda	<snd_acc
		clc
		adc	#<SND_TICK_RATE
		sta	<snd_acc
		bcc	snd_done		; (less than a whole tick this frame)
		lda	<sfx_on			; The effect first: it owns 4 and 5.
		beq	!+
		jsr	sfx_tick
!:		lda	<snd_track
		bne	music_tick
snd_done:	rts
		; (fall through)
music_tick:	lda	<snd_wait
		beq	!+
		dec	<snd_wait
.r:		rts
!:		lda	<snd_bank		; Map the stream: two banks, $6000 up.
		tam3
		inc	a
		tam4
.byte:		lda	[snd_ptr]
		jsr	snd_next
		cmp	#$FF
		beq	.loop
		cmp	#$80
		bcs	.chans
		sta	<snd_wait		; Wait n + 1 ticks (this one included).
		rts
.chans:		and	#$3F
		sta	<snd_tmp
		stz	<snd_ch
.each:		lsr	<snd_tmp
		bcc	.skip
		jsr	snd_read_ch		; Into snd_freq_*/snd_vol, then play it
		ldx	<snd_ch			; unless an effect has the channel.
		cpx	#SND_FIRST_SFX_CH
		bcc	!+
		lda	<sfx_on
		bne	.skip
!:		ldx	<snd_ch
		jsr	snd_write_ch
.skip:		inc	<snd_ch
		lda	<snd_tmp
		bne	.each
		bra	.byte
.loop:		ldx	<snd_track		; The tune loops back inside itself.
		dex
		lda	snd_loop_bank, x
		sta	<snd_bank
		lda	snd_loop_lo, x
		sta	<snd_ptr
		lda	snd_loop_hi, x
		sta	<snd_ptr + 1
		lda	<snd_bank
		tam3
		inc	a
		tam4
		bra	.byte

; sfx_tick - the same for the effect stream; its channels are 4 and 5.
sfx_tick:	lda	<sfx_wait
		beq	!+
		dec	<sfx_wait
		rts
!:		lda	<sfx_bank
		tam3
		inc	a
		tam4
.byte:		lda	[sfx_ptr]
		jsr	sfx_next
		cmp	#$FF
		beq	.done
		cmp	#$80
		bcs	.chans
		sta	<sfx_wait
		rts
.chans:		and	#$3F
		sta	<snd_tmp
		stz	<snd_ch
.each:		lsr	<snd_tmp
		bcc	.skip
		ldx	<snd_ch			; (its own channels: write them through)
		jsr	sfx_read_ch
.skip:		inc	<snd_ch
		lda	<snd_tmp
		bne	.each
		bra	.byte
.done:		stz	<sfx_on			; Give the music its channels back.
		ldx	#SND_FIRST_SFX_CH
!:		jsr	snd_write_ch
		inx
		cpx	#6
		bne	!-
		rts

; snd_read_ch - three stream bytes into the music's record of channel snd_ch.
snd_read_ch:	ldx	<snd_ch
		lda	[snd_ptr]
		sta	snd_freq_l, x
		jsr	snd_next
		lda	[snd_ptr]
		sta	snd_freq_h, x
		jsr	snd_next
		lda	[snd_ptr]
		sta	snd_vol, x
		jmp	snd_next

; sfx_read_ch - three stream bytes straight to PSG channel X.
sfx_read_ch:	lda	[sfx_ptr]
		sta	<sfx_f0
		jsr	sfx_next
		lda	[sfx_ptr]
		sta	<sfx_f1
		jsr	sfx_next
		lda	[sfx_ptr]
		sta	<sfx_v
		jsr	sfx_next
		stx	PSG_AR
		lda	<sfx_v
		beq	.off
		lda	<sfx_f1
		bpl	!+			; Bit 7: strike the note again.
		stz	PSG_CTRL
!:		and	#$0F
		sta	PSG_FREQ_HI
		lda	<sfx_f0
		sta	PSG_FREQ_LO
		lda	<sfx_v
		ora	#$80
		sta	PSG_CTRL
		rts
.off:		stz	PSG_CTRL
		rts

; snd_write_ch - X = channel: play what the music last set there.
snd_write_ch:	stx	PSG_AR
		lda	snd_vol, x
		beq	.off
		pha
		lda	snd_freq_h, x
		bpl	!+			; Bit 7: strike the note again, which
		stz	PSG_CTRL		; restarts the waveform.
!:		and	#$0F
		sta	PSG_FREQ_HI
		lda	snd_freq_l, x
		sta	PSG_FREQ_LO
		pla
		ora	#$80
		sta	PSG_CTRL
		rts
.off:		stz	PSG_CTRL
		rts

; snd_next / sfx_next - step a stream pointer, following it into the next bank.
snd_next:	inc	<snd_ptr
		bne	!+
		inc	<snd_ptr + 1
		bpl	!+			; Past $8000: shift the pair down.
		lda	<snd_ptr + 1
		cmp	#$A0
		bcc	!+
		sec
		sbc	#$20
		sta	<snd_ptr + 1
		inc	<snd_bank
		lda	<snd_bank
		tam3
		inc	a
		tam4
!:		rts
sfx_next:	inc	<sfx_ptr
		bne	!+
		inc	<sfx_ptr + 1
		lda	<sfx_ptr + 1
		cmp	#$A0
		bcc	!+
		sec
		sbc	#$20
		sta	<sfx_ptr + 1
		inc	<sfx_bank
		lda	<sfx_bank
		tam3
		inc	a
		tam4
!:		rts
