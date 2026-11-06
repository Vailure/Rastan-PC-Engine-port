
#ifndef _PSG_H_
#define _PSG_H_

/* Levels a channel can be given in direct D/A mode between two updates (the
   H6280 timer, the fastest thing that feeds one, ticks 117 times a frame) */
#define PSG_DDA_MAX 1024

/* Macro to access currently selected PSG channel */
#define PSGCH   psg.channel[psg.select]

/* PSG structure */
typedef struct {
    uint8 select;               /* Selected channel (0-5) */
    uint8 globalbalance;        /* Global sound balance */
    uint8 noisectrl;            /* Noise enable and frequency */
    uint8 lfofreq;              /* LFO frequency */
    uint8 lfoctrl;              /* LFO control */
    struct {
        int counter;            /* Waveform index counter */
        uint16 frequency;       /* Channel frequency */
        uint8 control;          /* Channel enable, DDA, volume */
        uint8 balance;          /* Channel balance */
        uint8 waveform[32];     /* Waveform data */
        uint8 waveform_index;   /* Waveform data index */
        uint8 dda[PSG_DDA_MAX]; /* Levels written in direct D/A mode, this frame */
        int dda_count;
    } channel[8];
}t_psg;

/* Global variables */
extern t_psg psg;

/* Function prototypes */
int psg_init(void);
void psg_reset(void);
void psg_shutdown(void);
void psg_w(uint16 address, uint8 data);
void psg_update(int16 *bufl, int16 *bufr, int length);

#endif /* _PSG_H_ */

