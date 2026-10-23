M = musashi/m68kcpu.c musashi/m68kdasm.c musashi/m68kops.c musashi/softfloat/softfloat.c
CFLAGS = -O2 -w

all: sim dasm snd

sim: sim.c $(M)
	$(CC) $(CFLAGS) -o $@ sim.c $(M) -lz -lm

snd: snd.c
	$(CC) $(CFLAGS) -o $@ snd.c

dasm: dasm.c $(M)
	$(CC) $(CFLAGS) -o $@ dasm.c $(M) -lm

clean:
	rm -f sim dasm snd
