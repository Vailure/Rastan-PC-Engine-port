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

export PCE_INCLUDE := $(abspath $(STAGE)):$(abspath $(HUC))/include/hucc
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

$(BUILD)/rastan.pce: src/main.asm $(STAGE)/stage.bin
	cd $(BUILD) && $(PCEAS) --newproc --strip -m -l 2 -S -gA --raw ../src/main.asm -o rastan.pce

# Scroll the ROM through the whole stage and compare with the converter preview.
test: $(BUILD)/rastan.pce tools/tgrun/tgrun
	python3 tools/test_scroll.py $(BUILD)/rastan.pce $(STAGE)/preview.png $(BUILD)/test $$(seq 62 37 2950)
	PAD=46 python3 tools/test_scroll.py $(BUILD)/rastan.pce $(STAGE)/preview.png $(BUILD)/test_down 80 120 160 300

tools/tgrun/tgrun: tools/tgrun/tgrun.c
	HUC=$(abspath $(HUC)) tools/tgrun/build.sh

clean:
	rm -rf $(BUILD)

.PHONY: all clean test
