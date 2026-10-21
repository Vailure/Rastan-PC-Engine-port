# Build the PC Engine ROM.
#
#   make HUC=/path/to/huc        (a built checkout of github.com/pce-devel/huc)
#
# Needs your own MAME "rastan" ROM set in roms/rastan (or RASTAN_ROMS).

HUC        ?= $(HOME)/huc
PCEAS      := $(HUC)/bin/pceas
ROMS       ?= roms/rastan
PALFRAME   ?= 1000
BUILD      := build
STAGE      := $(BUILD)/stage1
PLAYER     := $(BUILD)/player

export PCE_INCLUDE := $(abspath $(STAGE)):$(abspath $(PLAYER)):$(abspath src):$(abspath $(HUC))/include/hucc
export RASTAN_ROMS := $(abspath $(ROMS))

all: $(BUILD)/rastan.pce

sim/maincpu.bin: tools/extract_roms.py tools/arcade_gfx.py
	python3 tools/extract_roms.py $(ROMS) sim

sim/sim: sim/sim.c
	$(MAKE) -C sim

# Round 1 palette is captured from the arcade program running in the simulator.
$(BUILD)/bot1.txt: tools/make_bot.py
	@mkdir -p $(BUILD)
	python3 tools/make_bot.py $@

$(BUILD)/bot1.snp: sim/sim sim/maincpu.bin $(BUILD)/bot1.txt
	sim/sim sim/maincpu.bin $(BUILD)/bot1.txt $@ 20

$(STAGE)/stage.bin: tools/pce_stage.py tools/fgmap.py tools/bgmap.py sim/maincpu.bin $(BUILD)/bot1.snp
	cd tools && python3 pce_stage.py ../sim/maincpu.bin ../$(BUILD)/bot1.snp $(PALFRAME) 0 0x16 ../$(STAGE)

# Rastan's poses are captured from the arcade program running a scripted
# sequence of actions (walk, crouch, attacks, jumps).
$(BUILD)/actions.snp: sim/sim sim/maincpu.bin sim/scripts/actions.txt
	@mkdir -p $(BUILD)
	sim/sim sim/maincpu.bin sim/scripts/actions.txt $@ 1

# The attract demo climbs a rope; its climbing poses come from there.
$(BUILD)/attract.snp: sim/sim sim/maincpu.bin sim/scripts/attract_demo.txt
	@mkdir -p $(BUILD)
	sim/sim sim/maincpu.bin sim/scripts/attract_demo.txt $@ 1

$(PLAYER)/player.bin: tools/pce_player.py tools/fgmap.py sim/maincpu.bin $(BUILD)/actions.snp $(BUILD)/attract.snp
	cd tools && python3 pce_player.py ../sim/maincpu.bin ../$(BUILD)/actions.snp ../$(BUILD)/attract.snp ../$(PLAYER)

$(BUILD)/rastan.pce: src/main.asm src/player.asm $(STAGE)/stage.bin $(PLAYER)/player.bin
	@mkdir -p $(BUILD)/opt
	echo "CAMERA_TEST = 0" > $(BUILD)/opt/options.inc
	cd $(BUILD) && PCE_INCLUDE=$(abspath $(BUILD)/opt):$$PCE_INCLUDE $(PCEAS) --newproc --strip -m -l 2 -S -gA --raw ../src/main.asm -o rastan.pce

# Test build: the pad drives the camera directly and Rastan is not drawn.
$(BUILD)/camtest.pce: src/main.asm src/player.asm $(STAGE)/stage.bin $(PLAYER)/player.bin
	@mkdir -p $(BUILD)/opt_test
	echo "CAMERA_TEST = 1" > $(BUILD)/opt_test/options.inc
	cd $(BUILD) && PCE_INCLUDE=$(abspath $(BUILD)/opt_test):$$PCE_INCLUDE $(PCEAS) --newproc --strip -l 0 --raw ../src/main.asm -o camtest.pce

# Scroll the ROM through the whole stage and compare with the converter preview.
test: $(BUILD)/camtest.pce $(BUILD)/rastan.pce tools/tgrun/tgrun
	python3 tools/test_scroll.py $(BUILD)/camtest.pce $(STAGE)/preview.png $(BUILD)/test $$(seq 62 37 2950)
	PAD=46 python3 tools/test_scroll.py $(BUILD)/camtest.pce $(STAGE)/preview.png $(BUILD)/test_down 80 120 160 300
	python3 tools/test_player.py $(BUILD)/rastan.pce

tools/tgrun/tgrun: tools/tgrun/tgrun.c
	HUC=$(abspath $(HUC)) tools/tgrun/build.sh

# Exact-port groundwork: record every player-update call under random input and
# replay each through tools/m68k's reference interpreter (all 16 KB of RAM must match).
sim/full.asm: sim/maincpu.bin sim/sim
	sim/dasm sim/maincpu.bin 0 60000 > $@

lockstep: sim/sim sim/full.asm
	@mkdir -p $(BUILD)
	python3 tools/make_fuzz.py $(BUILD)/fuzz.txt 1 6000
	echo "callsnap 5132a $(BUILD)/fuzz.csnp" >> $(BUILD)/fuzz.txt
	sim/sim sim/maincpu.bin $(BUILD)/fuzz.txt /dev/null 1000
	cd tools && python3 lockstep.py ../sim/maincpu.bin ../sim/full.asm ../$(BUILD)/fuzz.csnp 5132a

clean:
	rm -rf $(BUILD)

.PHONY: all clean test lockstep
