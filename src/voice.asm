; ***************************************************************************
;
; Rastan - the arcade's voice samples, on the PC Engine's D/A.
;
; Rastan's jump grunt and his death cry are not FM on the arcade: the sound
; board plays them from an ADPCM ROM through an MSM5205. The PC Engine has no
; ADPCM, but a PSG channel can be put in direct D/A mode, where every write to
; its waveform port sets the output level there and then.
;
; tools/pce_voice.py decodes the arcade's samples into one 5-bit level per
; tick of the H6280's timer (7.16 MHz / 1024 = 6991 Hz, within 2% of the
; MSM5205's rate here). The timer interrupt writes one of them a tick to PSG
; channel 5, which the music gets back when the voice ends.
;
; Every other PSG write in the game runs with the interrupt held off
; (src/sound.asm), because the channel-select port cannot be read back and so
; cannot be put back by an interrupt in the middle of someone else's write.
;
; ***************************************************************************

VOICE_CH	=	5		; The PSG channel a voice takes.

		.zp
voice_ptr:	ds	2		; Sample data, mapped into MPR3 ($6000-$7FFF).
voice_bank:	ds	1
voice_on:	ds	1		; A voice is playing.
voice_held:	ds	1		; Channel 5 is still a voice's: the music gets it
					; back on the frame after the voice ends.
voice_sav:	ds	1		; MPR3 while the interrupt reads.

		.code

; ---------------------------------------------------------------------------
; voice_init - take the timer interrupt (the core jumps through timer_hook),
; with the timer stopped until there is something to play.

voice_init:	stz	<voice_on
		stz	<voice_held
		php
		sei
		stz	TIMER_CR
		stz	TIMER_DR		; One tick a sample: 6991 Hz.
		lda	#<voice_irq
		sta	timer_hook
		lda	#>voice_irq
		sta	timer_hook + 1
		smb2	<irq_vec		; (the core sets this too)
		stz	IRQ_ACK
		plp
		rts

; ---------------------------------------------------------------------------
; voice_play - A = VOICE_*: play it on channel VOICE_CH.

voice_play:	cmp	#VOICE_COUNT
		bcs	.r
		tax
		php
		sei
		lda	voice_tbl_bank, x
		sta	<voice_bank
		lda	voice_tbl_lo, x
		sta	<voice_ptr
		lda	voice_tbl_hi, x
		sta	<voice_ptr + 1
		lda	#VOICE_CH
		sta	PSG_AR
		sta	<psg_ar
		lda	#$FF
		sta	PSG_PAN
		lda	#$DF			; On, direct D/A, full volume.
		sta	PSG_CTRL
		lda	#1
		sta	<voice_on
		sta	<voice_held
		stz	IRQ_ACK			; (this reloads the timer)
		sta	TIMER_CR
		plp
.r:		rts

; ---------------------------------------------------------------------------
; voice_irq - one sample, from the timer interrupt. The data window (MPR3) is
; wherever the interrupted code left it, so it is put back before returning.

voice_irq:	pha
		tma3
		sta	<voice_sav
		lda	<voice_bank
		tam3
		lda	#VOICE_CH		; (whoever was interrupted left the PSG
		sta	PSG_AR			; selecting a channel of their own)
		lda	[voice_ptr]
		bmi	.done			; $80 ends it (levels are 0-31).
		sta	PSG_WAVEFORM
		lda	<psg_ar
		sta	PSG_AR
		lda	<voice_sav
		tam3
		inc	<voice_ptr
		bne	.ack
		inc	<voice_ptr + 1
		lda	<voice_ptr + 1
		cmp	#$80			; Out of MPR3: on into the next bank.
		bcc	.ack
		lda	#$60
		sta	<voice_ptr + 1
		inc	<voice_bank
.ack:		stz	IRQ_ACK
		pla
		rti

.done:		stz	PSG_CTRL		; Silent until sound_update hands the
		lda	<psg_ar			; channel back to the music.
		sta	PSG_AR
		lda	<voice_sav
		tam3
		stz	TIMER_CR
		stz	<voice_on
		bra	.ack
