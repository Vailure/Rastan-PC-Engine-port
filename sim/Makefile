M = musashi/m68kcpu.c musashi/m68kdasm.c musashi/m68kops.c musashi/softfloat/softfloat.c
CFLAGS = -O2 -w
DEPS = $(wildcard musashi/*.[ch] musashi/softfloat/*)

all: sim dasm

sim: sim.c $(DEPS)
	$(CC) $(CFLAGS) -o $@ sim.c $(M) -lz -lm

dasm: dasm.c $(DEPS)
	$(CC) $(CFLAGS) -o $@ dasm.c $(M) -lm

clean:
	rm -f sim dasm

