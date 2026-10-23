
#include "shared.h"

t_psg psg;

/*--------------------------------------------------------------------------*/
/* Init, reset, shutdown routines                                           */
/*--------------------------------------------------------------------------*/

int psg_init(void)
{
    memset(&psg, 0, sizeof(psg));
    return (0);
}

void psg_reset(void)
{
    memset(&psg, 0, sizeof(psg));
}

void psg_shutdown(void)
{
}

/*--------------------------------------------------------------------------*/
/* PSG emulation                                                            */
/*--------------------------------------------------------------------------*/

#include <stdlib.h>
#include <stdio.h>
FILE *psg_log;
void psg_w(uint16 address, uint8 data)
{
    if (!psg_log && getenv("TGRUN_PSGLOG")) psg_log = fopen(getenv("TGRUN_PSGLOG"), "w");
    if (psg_log) fprintf(psg_log, "%d %04x %02x\n", psg.select, address, data);
    switch(address)
    {
        case 0x0800: /* Channel select */
            psg.select = (data & 7);
            break;

        case 0x0801: /* Global sound balance */
            psg.globalbalance = data;
            break;

        case 0x0802: /* Channel frequency (LSB) */
            PSGCH.frequency = (PSGCH.frequency & 0x0F00) | (data);
            break;

        case 0x0803: /* Channel frequency (MSB) */
            PSGCH.frequency = (PSGCH.frequency & 0x00FF) | ((data & 0x0F) << 8);
            break;

        case 0x0804: /* Channel enable, DDA, volume */
            PSGCH.control = data;
            if((data & 0xC0) == 0x40) PSGCH.waveform_index = 0;
            break;

        case 0x0805: /* Channel balance */
            PSGCH.balance = data;
            break;

        case 0x0806: /* Channel waveform data, or a direct D/A level */
            if((PSGCH.control & 0xC0) == 0xC0)
            {
                /* In D/A mode this sets the output level there and then; the
                   waveform data is left alone. They are kept for the update,
                   which spreads them evenly over the samples it makes: what
                   feeds a D/A is a timer, so they do arrive evenly. */
                if(PSGCH.dda_count < PSG_DDA_MAX)
                    PSGCH.dda[PSGCH.dda_count++] = (data & 0x1F);
            }
            else
            {
                PSGCH.waveform[PSGCH.waveform_index] = data;
                PSGCH.waveform_index = ((PSGCH.waveform_index + 1) & 0x1F);
            }
            break;

        case 0x0807: /* Noise enable and frequency */
            psg.noisectrl = data;
            break;

        case 0x0808: /* LFO frequency */
            psg.lfofreq = data;
            break;

        case 0x0809: /* LFO trigger and control */
            psg.lfoctrl = data;
            break;
    }
}

void psg_update(int16 *bufl, int16 *bufr, int length)
{
    int total = length, index = 0, ch;

    /* Fill as many samples as needed */
    while(length > 0)
    {
        int sample[2] = {0, 0};    /* Left and right samples */
        int start;                 /* Skip channels 0, 1 if LFO is enabled */ 
        int stop;                  /* Skip channels 4, 5 if noise is enabled */

        start = ((psg.lfoctrl & 3) == 0) ? 0 : 2;
        stop = (psg.noisectrl & 0x80) ? 4 : 6;

        for(ch = start; ch < stop; ch += 1)
        {
            /* If channel is ON and DDA is ON, play the levels written to it */
            if((psg.channel[ch].control & 0xC0) == 0xC0)
            {
                int lbal = (psg.globalbalance >> 4) & 0x0F;
                int rbal = (psg.globalbalance >> 0) & 0x0F;
                int lchb = (psg.channel[ch].balance >> 4) & 0x0F;
                int rchb = (psg.channel[ch].balance >> 0) & 0x0F;
                int chvl = (psg.channel[ch].control & 0x1F);
                int n = psg.channel[ch].dda_count;
                int data;

                if(n == 0) continue;
                data = psg.channel[ch].dda[(index * n) / total];
                sample[0] = (sample[0] + ((lbal + lchb + chvl) * data));
                sample[1] = (sample[1] + ((rbal + rchb + chvl) * data));
                continue;
            }

            /* If channel is ON and DDA is OFF, play waveform data */
            if((psg.channel[ch].control & 0xC0) == 0x80)
            {
                /* Global sound balance (left and right, all channels) */
                int lbal = (psg.globalbalance >> 4) & 0x0F;
                int rbal = (psg.globalbalance >> 0) & 0x0F;

                /* Balance (left and right, this channel) */
                int lchb = (psg.channel[ch].balance >> 4) & 0x0F;
                int rchb = (psg.channel[ch].balance >> 0) & 0x0F;

                /* Volume level (this channel) */
                int chvl = (psg.channel[ch].control & 0x1F);
    
                /* Total volume levels for left and right
                   (volume sounds too soft - not sure how to combine these) */
                int lvol = (lbal + lchb + chvl);
                int rvol = (rbal + rchb + chvl);

                int base, step, offset, data;

                /* This is the largest possible step value which is divided
                   by the channel frequency used to increment the counter,
                   which in turn is used to traverse the waveform buffer.
                   3580000 (PSG clock) / 32 (length of waveform) = 111875 (base step value)
                   That doesn't work right but multiplying it by three sounds better. */
                base = (3580000 / 32) * 3;

                /* Calculate the value to add to the counter for each sample,
                   but don't divide by zero if the frequency is zero */
                step = (psg.channel[ch].frequency) ? base / psg.channel[ch].frequency : 0;

                /* Use upper 5 bits of 12-bit frequency as wave index */
                offset = (psg.channel[ch].counter >> 12) & 0x1F;

                /* Bump waveform index */
                psg.channel[ch].counter += step;

                /* Data is 5 bits */
                data = (psg.channel[ch].waveform[offset] & 0x1F);

                /* Add new sample to old one */
                sample[0] = (sample[0] + (lvol * data));
                sample[1] = (sample[1] + (rvol * data));
            }
        }

        /* Make samples signed */
        if(sample[0] & 0x8000) sample[0] ^= 0x8000;
        if(sample[1] & 0x8000) sample[1] ^= 0x8000;

        /* Store samples in buffer */
        *bufl++ = sample[0];
        *bufr++ = sample[1];

        /* Do next sample pair */
        ++index;
        --length;
    }

    /* The D/A levels have been played: wait for the next frame's */
    for(ch = 0; ch < 6; ch += 1) psg.channel[ch].dda_count = 0;
}
