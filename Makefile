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

export PCE_INCLUDE := $(abspath $(STAGE)):$(abspath $(PLAYER)):$(abspath $(BUILD)/enemies):$(abspath $(BUILD)/hud):$(abspath $(BUILD)/props):$(abspath $(BUILD)/debug):$(abspath src):$(abspath $(HUC))/include/hucc
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

$(STAGE)/stage.bin: tools/pce_stage.py tools/fgmap.py tools/bgmap.py sim/maincpu.bin $(BUILD)/bot1.snp $(BUILD)/waterfall.snp
	cd tools && python3 pce_stage.py ../sim/maincpu.bin ../$(BUILD)/bot1.snp $(PALFRAME) 0 0x16 ../$(STAGE) ../$(BUILD)/waterfall.snp

# Rastan's poses are captured from the arcade program running a scripted
# sequence of actions (walk, crouch, attacks, jumps).
$(BUILD)/actions.snp: sim/sim sim/maincpu.bin sim/scripts/actions.txt
	@mkdir -p $(BUILD)
	sim/sim sim/maincpu.bin sim/scripts/actions.txt $@ 1

# The attract demo climbs a rope; its climbing poses come from there.
$(BUILD)/attract.snp: sim/sim sim/maincpu.bin sim/scripts/attract_demo.txt
	@mkdir -p $(BUILD)
	sim/sim sim/maincpu.bin sim/scripts/attract_demo.txt $@ 1

$(BUILD)/thrusts.snp: sim/sim sim/maincpu.bin sim/scripts/thrusts.txt
	@mkdir -p $(BUILD)
	sim/sim sim/maincpu.bin sim/scripts/thrusts.txt $@ 1

# Lizardmen walk up to a passive Rastan and attack (his hurt poses, their walk and
# attack), then he swings at them (their death).
$(BUILD)/lizard.snp: sim/sim sim/maincpu.bin sim/scripts/lizard.txt
	@mkdir -p $(BUILD)
	sim/sim sim/maincpu.bin sim/scripts/lizard.txt $@ 1

# The bot (health held) runs to the first waterfall and dies on its lip: the
# death animation, waterfall palette cycle and the segment 3 sky come from here.
$(BUILD)/waterfall.txt: tools/make_bot.py
	@mkdir -p $(BUILD)
	python3 tools/make_bot.py $@ 1720

$(BUILD)/waterfall.snp: sim/sim sim/maincpu.bin $(BUILD)/waterfall.txt
	sim/sim sim/maincpu.bin $(BUILD)/waterfall.txt $@ 1

$(PLAYER)/player.bin: tools/pce_player.py tools/fgmap.py sim/maincpu.bin $(BUILD)/actions.snp $(BUILD)/attract.snp $(BUILD)/thrusts.snp $(BUILD)/lizard.snp $(BUILD)/waterfall.snp
	cd tools && python3 pce_player.py ../sim/maincpu.bin ../$(BUILD)/actions.snp ../$(BUILD)/attract.snp ../$(BUILD)/thrusts.snp ../$(BUILD)/lizard.snp ../$(BUILD)/waterfall.snp ../$(PLAYER)

# Blue club throwers at checkpoint 2: they throw at a passive Rastan, then he
# walks into them swinging.
$(BUILD)/blue.snp: sim/sim sim/maincpu.bin sim/scripts/blue.txt
	@mkdir -p $(BUILD)
	sim/sim sim/maincpu.bin sim/scripts/blue.txt $@ 1

ENEMIES    := $(BUILD)/enemies
$(ENEMIES)/enemies.bin: tools/pce_enemies.py tools/enemy_capture.py $(BUILD)/lizard.snp $(BUILD)/blue.snp
	cd tools && python3 pce_enemies.py ../$(BUILD)/lizard.snp ../$(BUILD)/blue.snp ../$(ENEMIES)

# HUD cells (lives, icon, health bar, ROUND) from the arcade's HUD sprites.
$(BUILD)/hud/hud.bin: tools/pce_hud.py $(BUILD)/actions.snp
	cd tools && python3 pce_hud.py ../$(BUILD)/actions.snp ../$(BUILD)/hud

# Stage props (the cave block) from a bot run that breaks it with a down thrust.
$(BUILD)/block.snp: sim/sim sim/maincpu.bin sim/scripts/block.txt
	@mkdir -p $(BUILD)
	sim/sim sim/maincpu.bin sim/scripts/block.txt $@ 1

$(BUILD)/props/props.bin: tools/pce_props.py tools/enemy_capture.py $(BUILD)/block.snp
	cd tools && python3 pce_props.py ../$(BUILD)/block.snp ../$(BUILD)/props

# Debug menu font: characters $20-$5F of HuC's 8x8 bold font (it starts at $10).
$(BUILD)/debug/font.bin: $(HUC)/examples/asm/elmer/font/font8x8-ascii-bold-short.dat
	@mkdir -p $(BUILD)/debug
	dd if=$< of=$@ bs=8 skip=16 count=64 status=none

GAME_DEPS  := src/main.asm src/player.asm src/enemies.asm src/props.asm src/hud.asm src/dyncolor.asm src/debug.asm $(BUILD)/debug/font.bin $(STAGE)/stage.bin $(PLAYER)/player.bin $(BUILD)/enemies/enemies.bin $(BUILD)/hud/hud.bin $(BUILD)/props/props.bin

$(BUILD)/rastan.pce: $(GAME_DEPS)
	@mkdir -p $(BUILD)/opt
	printf "CAMERA_TEST = 0\nNO_ENEMIES = 0\nGOD_MODE = 0\n" > $(BUILD)/opt/options.inc
	cd $(BUILD) && PCE_INCLUDE=$(abspath $(BUILD)/opt):$$PCE_INCLUDE $(PCEAS) --newproc --strip -m -l 2 -S -gA --raw ../src/main.asm -o rastan.pce

# Test build: the pad drives the camera directly and Rastan is not drawn.
$(BUILD)/camtest.pce: $(GAME_DEPS)
	@mkdir -p $(BUILD)/opt_test
	printf "CAMERA_TEST = 1\nNO_ENEMIES = 1\nGOD_MODE = 0\n" > $(BUILD)/opt_test/options.inc
	cd $(BUILD) && PCE_INCLUDE=$(abspath $(BUILD)/opt_test):$$PCE_INCLUDE $(PCEAS) --newproc --strip -l 0 --raw ../src/main.asm -o camtest.pce

# Scroll the ROM through the whole stage and compare with the converter preview.
# Test build: no enemies, for the movement checks.
$(BUILD)/noenemy.pce: $(GAME_DEPS)
	@mkdir -p $(BUILD)/opt_noen
	printf "CAMERA_TEST = 0\nNO_ENEMIES = 1\nGOD_MODE = 0\n" > $(BUILD)/opt_noen/options.inc
	cd $(BUILD) && PCE_INCLUDE=$(abspath $(BUILD)/opt_noen):$$PCE_INCLUDE $(PCEAS) --newproc --strip -l 0 --raw ../src/main.asm -o noenemy.pce

# Test build: enemies on, but they can't hurt Rastan (to reach later sections).
$(BUILD)/god.pce: $(GAME_DEPS)
	@mkdir -p $(BUILD)/opt_god
	printf "CAMERA_TEST = 0\nNO_ENEMIES = 0\nGOD_MODE = 1\n" > $(BUILD)/opt_god/options.inc
	cd $(BUILD) && PCE_INCLUDE=$(abspath $(BUILD)/opt_god):$$PCE_INCLUDE $(PCEAS) --newproc --strip -l 0 --raw ../src/main.asm -o god.pce

test: $(BUILD)/camtest.pce $(BUILD)/noenemy.pce $(BUILD)/rastan.pce $(BUILD)/god.pce tools/tgrun/tgrun
	python3 tools/test_scroll.py $(BUILD)/camtest.pce $(STAGE)/preview.png $(BUILD)/test $$(seq 62 37 2950)
	PAD=46 python3 tools/test_scroll.py $(BUILD)/camtest.pce $(STAGE)/preview.png $(BUILD)/test_down 80 120 160 300
	python3 tools/test_player.py $(BUILD)/noenemy.pce
	python3 tools/test_enemies.py $(BUILD)/rastan.pce $(BUILD)/god.pce
	python3 tools/test_effects.py $(BUILD)/noenemy.pce $(STAGE)/dyncolor.inc
	python3 tools/test_debug.py $(BUILD)/rastan.pce $(BUILD)/noenemy.pce

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
