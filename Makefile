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

export PCE_INCLUDE := $(abspath $(BUILD)):$(abspath $(PLAYER)):$(abspath $(BUILD)/objects):$(abspath $(BUILD)/hud):$(abspath $(BUILD)/props):$(abspath $(BUILD)/traps):$(abspath $(BUILD)/sound):$(abspath $(BUILD)/voice):$(abspath $(BUILD)/still):$(abspath $(BUILD)/debug):$(abspath src):$(abspath $(HUC))/include/hucc
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

$(STAGE)/stage.bin: tools/pce_stage.py tools/pce_coll.py tools/world.py tools/fgmap.py tools/bgmap.py sim/maincpu.bin $(BUILD)/bot1.snp $(BUILD)/waterfall.snp $(BUILD)/hall.snp $(BUILD)/sky04.snp $(BUILD)/sky0c.snp
	cd tools && SKY_SNAPS=../$(BUILD)/sky04.snp,../$(BUILD)/sky0c.snp python3 pce_stage.py ../sim/maincpu.bin ../$(BUILD)/bot1.snp $(PALFRAME) 0 0x16 ../$(STAGE) ../$(BUILD)/waterfall.snp ../$(BUILD)/hall.snp:4400
	cd tools && python3 pce_coll.py ../sim/maincpu.bin ../$(STAGE)

# Round 2 (the forest, then a castle; map segments $17-$2D): the arcade started in round 2
# at its first segment, its castle ($27) and its boss room ($2D) (the start switch $5FF9F:
# sim/scripts/round2.txt), its palette at frame 420 of each. The stage and collision go to
# $(STAGE2), every name in its .inc files prefixed R2_ (src/main.asm includes every round's).
STAGE2     := $(BUILD)/stage2
$(BUILD)/round2.snp: sim/sim sim/maincpu.bin sim/scripts/round2.txt
	sim/sim sim/maincpu.bin sim/scripts/round2.txt $@ 20 300

$(BUILD)/round2_castle.snp: sim/sim sim/maincpu.bin sim/scripts/round2_castle.txt
	sim/sim sim/maincpu.bin sim/scripts/round2_castle.txt $@ 20 300

$(BUILD)/round2_boss.snp: sim/sim sim/maincpu.bin sim/scripts/round2_boss.txt
	sim/sim sim/maincpu.bin sim/scripts/round2_boss.txt $@ 20 300

$(STAGE2)/stage.bin: tools/pce_stage.py tools/pce_coll.py tools/world.py tools/fgmap.py tools/bgmap.py sim/maincpu.bin $(BUILD)/round2.snp $(BUILD)/round2_castle.snp $(BUILD)/round2_boss.snp
	cd tools && RASTAN_ROUND=2 python3 pce_stage.py ../sim/maincpu.bin ../$(BUILD)/round2.snp 420 0x17 0x2d ../$(STAGE2) - ../$(BUILD)/round2_castle.snp:420 ../$(BUILD)/round2_boss.snp:420
	cd tools && RASTAN_ROUND=2 python3 pce_coll.py ../sim/maincpu.bin ../$(STAGE2)

# Round 3 (a cave, then a castle from $3E; three shafts up, $41-$43, the boss room $44 through
# a door): the arcade started at its first segment, its castle and its boss room (sim/scripts/
# round3*.txt: $5FF9F = $FD, $DD, $F5), its palette at frame 420 of each.
STAGE3     := $(BUILD)/stage3
$(BUILD)/round3.snp $(BUILD)/round3_castle.snp $(BUILD)/round3_boss.snp: $(BUILD)/%.snp: sim/sim sim/maincpu.bin sim/scripts/%.txt
	@mkdir -p $(BUILD)
	sim/sim sim/maincpu.bin sim/scripts/$*.txt $@ 20 300

$(STAGE3)/stage.bin: tools/pce_stage.py tools/pce_coll.py tools/world.py tools/fgmap.py tools/bgmap.py sim/maincpu.bin $(BUILD)/round3.snp $(BUILD)/round3_castle.snp $(BUILD)/round3_boss.snp
	cd tools && RASTAN_ROUND=3 python3 pce_stage.py ../sim/maincpu.bin ../$(BUILD)/round3.snp 420 0x2e 0x44 ../$(STAGE3) - ../$(BUILD)/round3_castle.snp:420 ../$(BUILD)/round3_boss.snp:420
	cd tools && RASTAN_ROUND=3 python3 pce_coll.py ../sim/maincpu.bin ../$(STAGE3)

# Round 3's objects: the bot (tools/make_bot.py) run from its restart checkpoints ($32, $34,
# $39: the restart table byte), every frame from 380.
$(BUILD)/r3bot_%.txt: tools/make_bot.py
	@mkdir -p $(BUILD)
	python3 tools/make_bot.py $@ 4400 $* 3

$(BUILD)/r3bot_%.snp: sim/sim sim/maincpu.bin $(BUILD)/r3bot_%.txt
	sim/sim sim/maincpu.bin $(BUILD)/r3bot_$*.txt $@ 1 380

# Rounds 2 and 3 run through from their start (to the castle) by the same bot, with the
# water, pits and climbs it cannot cross floored over while it passes (make_bot.py's floor
# pokes): the census of their map objects (logs, blocks, spears ...) and the captures of
# their poses, every frame from 380.
R2RUN_POKES = 1800:2112:40:32:63 1955:2355:40:0:51 2328:2525:40:12:15 2397:2584:40:24:27 2498:2660:40:40:43 \
	5303:5554:28:56:63 5338:5805:36:0:43 5928:6231:40:36:63
R3RUN_POKES = 966:1194:56:0:3 1012:1306:56:8:11 1100:1383:52:20:23 1569:1917:40:12:15 1790:2091:44:24:27 \
	1832:2204:40:32:35 1890:2221:36:40:43 2007:2463:44:56:59 2110:2478:40:0:3 2267:2665:36:16:19 \
	2379:2766:32:24:27 2470:2774:28:32:35 2986:3262:40:40:63 3126:3507:47:0:35 3767:4169:34:36:47 \
	3793:4169:30:42:47 4203:4393:36:20:20 4254:4519:48:32:32 4311:4619:56:40:40 4506:4764:56:60:60 \
	4749:5087:52:24:27 4786:5335:44:32:35 5079:5554:32:56:63 5593:5785:40:36:36 5593:5938:40:36:63
$(BUILD)/r2run.txt: tools/make_bot.py Makefile
	@mkdir -p $(BUILD)
	python3 tools/make_bot.py $@ 14000 - 2 $(R2RUN_POKES)
$(BUILD)/r3run.txt: tools/make_bot.py Makefile
	@mkdir -p $(BUILD)
	python3 tools/make_bot.py $@ 14000 - 3 $(R3RUN_POKES)
$(BUILD)/r2run.snp $(BUILD)/r3run.snp: $(BUILD)/%.snp: sim/sim sim/maincpu.bin $(BUILD)/%.txt
	sim/sim sim/maincpu.bin $(BUILD)/$*.txt $@ 1 380

# The sky darkens toward dusk in eight steps along the outdoor stage. The same bot from
# checkpoints 1 and 3 (the arcade's restart table byte: segments 4 and 12) sees the
# later steps (the round-start bot dies before them).
$(BUILD)/sky04.txt: tools/make_bot.py
	@mkdir -p $(BUILD)
	python3 tools/make_bot.py $@ 4000 04

$(BUILD)/sky0c.txt: tools/make_bot.py
	@mkdir -p $(BUILD)
	python3 tools/make_bot.py $@ 2200 0c

$(BUILD)/sky%.snp: sim/sim sim/maincpu.bin $(BUILD)/sky%.txt
	sim/sim sim/maincpu.bin $(BUILD)/sky$*.txt $@ 1

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

# The bot swings across the chasm on the vine at x 2750 (its frames 10755-11214):
# the vine's swing and Rastan's hanging pose, recorded every frame from 10700.
$(BUILD)/vine.txt: $(BUILD)/bot1.txt
	grep -v '^end' $< > $@
	echo 'end 11400' >> $@

$(BUILD)/vine.snp: sim/sim sim/maincpu.bin $(BUILD)/vine.txt
	sim/sim sim/maincpu.bin $(BUILD)/vine.txt $@ 1 10700

$(PLAYER)/player.bin: tools/pce_player.py tools/player_frames.py tools/fgmap.py tools/world.py sim/maincpu.bin $(BUILD)/actions.snp $(BUILD)/attract.snp $(BUILD)/thrusts.snp $(BUILD)/lizard.snp $(BUILD)/waterfall.snp $(BUILD)/vine.snp $(BUILD)/upatk.snp
	cd tools && python3 pce_player.py ../sim/maincpu.bin ../$(BUILD)/actions.snp ../$(BUILD)/attract.snp ../$(BUILD)/thrusts.snp ../$(BUILD)/lizard.snp ../$(BUILD)/waterfall.snp ../$(BUILD)/vine.snp ../$(BUILD)/upatk.snp ../$(PLAYER)

# Standing UP+attack: the arcade swings the sword over Rastan's head.
$(BUILD)/upatk.snp: sim/sim sim/maincpu.bin sim/scripts/upatk.txt
	@mkdir -p $(BUILD)
	sim/sim sim/maincpu.bin sim/scripts/upatk.txt $@ 1 500

# Blue club throwers at checkpoint 2: they throw at a passive Rastan, then he
# walks into them swinging.
$(BUILD)/blue.snp: sim/sim sim/maincpu.bin sim/scripts/blue.txt
	@mkdir -p $(BUILD)
	sim/sim sim/maincpu.bin sim/scripts/blue.txt $@ 1

# Weapon items and their bats: the axe in the cave (the bot breaks the block and
# takes it), the fire sword and the morning star (bot runs from checkpoints).
$(BUILD)/chimera.snp: sim/sim sim/maincpu.bin sim/scripts/chimera.txt
	@mkdir -p $(BUILD)
	sim/sim sim/maincpu.bin sim/scripts/chimera.txt $@ 1

$(BUILD)/gargoyle.snp: sim/sim sim/maincpu.bin sim/scripts/gargoyle.txt
	@mkdir -p $(BUILD)
	sim/sim sim/maincpu.bin sim/scripts/gargoyle.txt $@ 1

$(BUILD)/gargkill.snp: sim/sim sim/maincpu.bin sim/scripts/gargkill.txt
	@mkdir -p $(BUILD)
	sim/sim sim/maincpu.bin sim/scripts/gargkill.txt $@ 1 1150

$(BUILD)/woman.snp: sim/sim sim/maincpu.bin sim/scripts/woman.txt
	@mkdir -p $(BUILD)
	sim/sim sim/maincpu.bin sim/scripts/woman.txt $@ 1

$(BUILD)/castle.snp: sim/sim sim/maincpu.bin sim/scripts/castle.txt
	@mkdir -p $(BUILD)
	sim/sim sim/maincpu.bin sim/scripts/castle.txt $@ 1

$(BUILD)/boss.snp: sim/sim sim/maincpu.bin sim/scripts/boss.txt
	@mkdir -p $(BUILD)
	sim/sim sim/maincpu.bin sim/scripts/boss.txt $@ 1

$(BUILD)/item.snp: sim/sim sim/maincpu.bin sim/scripts/item.txt
	@mkdir -p $(BUILD)
	sim/sim sim/maincpu.bin sim/scripts/item.txt $@ 1

$(BUILD)/snake.snp: sim/sim sim/maincpu.bin sim/scripts/snake.txt
	@mkdir -p $(BUILD)
	sim/sim sim/maincpu.bin sim/scripts/snake.txt $@ 1 500

$(BUILD)/boss2.snp $(BUILD)/boss2_leap.snp $(BUILD)/boss2_kill.snp $(BUILD)/boss3.snp: $(BUILD)/%.snp: sim/sim sim/maincpu.bin sim/scripts/%.txt
	@mkdir -p $(BUILD)
	sim/sim sim/maincpu.bin sim/scripts/$*.txt $@ 1 400

$(BUILD)/item_%.snp: sim/sim sim/maincpu.bin sim/scripts/item_%.txt
	@mkdir -p $(BUILD)
	sim/sim sim/maincpu.bin sim/scripts/item_$*.txt $@ 1

# Object (enemy, projectile, item) poses: groups and captures in tools/object_specs.py.
# Cells start at bank $60; each group's poses and anims get the next banks.
OBJECTS    := $(BUILD)/objects
$(OBJECTS)/objcells.bin: tools/pce_objects.py tools/object_specs.py tools/census_all.py $(BUILD)/lizard.snp $(BUILD)/blue.snp $(BUILD)/item.snp $(BUILD)/item_fire.snp $(BUILD)/item_star.snp $(BUILD)/item_r2.snp $(BUILD)/chimera.snp $(BUILD)/gargoyle.snp $(BUILD)/gargkill.snp $(BUILD)/woman.snp $(BUILD)/castle.snp $(BUILD)/boss.snp $(BUILD)/vine.snp $(BUILD)/hall.snp $(BUILD)/swarm.snp $(BUILD)/snake.snp $(BUILD)/boss2.snp $(BUILD)/boss2_leap.snp $(BUILD)/boss2_kill.snp $(BUILD)/round2.snp $(BUILD)/round2_castle.snp $(BUILD)/round3.snp $(BUILD)/round3_castle.snp $(BUILD)/r3bot_32.snp $(BUILD)/r3bot_34.snp $(BUILD)/r3bot_39.snp $(BUILD)/boss3.snp $(BUILD)/r2run.snp $(BUILD)/r3run.snp
	cd tools && python3 pce_objects.py ../$(BUILD) ../$(OBJECTS) 0x13

# HUD cells (lives, icon, health bar, ROUND) from the arcade's HUD sprites.
$(BUILD)/hud/hud.bin: tools/pce_hud.py $(BUILD)/actions.snp
	cd tools && python3 pce_hud.py ../$(BUILD)/actions.snp ../$(BUILD)/hud

# Music and sound effects: sim/snd runs the arcade's Z80 sound driver and logs
# its YM2151 writes; pce_sound.py turns each command's tune or effect into a
# stream the PC Engine's PSG can play.
sim/snd: sim/snd.c
	$(MAKE) -C sim snd

$(BUILD)/sound/sound.bin: tools/pce_sound.py tools/ym2151.py sim/snd sim/audiocpu.bin sim/adpcm.bin
	@mkdir -p $(BUILD)/sound
	cd tools && python3 pce_sound.py ../sim/audiocpu.bin ../sim/adpcm.bin ../$(BUILD)/sound

# The round-clear screen, from the arcade (the boss script, run on).
$(BUILD)/ending.snp: sim/sim sim/maincpu.bin sim/scripts/ending.txt
	@mkdir -p $(BUILD)
	sim/sim sim/maincpu.bin sim/scripts/ending.txt $@ 1 2490

$(BUILD)/still/ending.bin: tools/pce_still.py tools/pce_stage.py $(BUILD)/ending.snp
	cd tools && python3 pce_still.py ending ../$(BUILD)/ending.snp 2500 60 8 0 0 ../$(BUILD)/still

# The title screen and GAME OVER, from the arcade's power-on attract sequence. The title's
# "PUSH RUN BUTTON" row becomes its two choices (src/still.asm: title_screen).
$(BUILD)/title.snp: sim/sim sim/maincpu.bin sim/scripts/attract_stills.txt
	@mkdir -p $(BUILD)
	sim/sim sim/maincpu.bin sim/scripts/attract_stills.txt $@ 1 155

$(BUILD)/still/title.bin: tools/pce_still.py tools/pce_stage.py $(BUILD)/title.snp
	cd tools && python3 pce_still.py title ../$(BUILD)/title.snp 160 24 16 01 0 ../$(BUILD)/still \
		--text 64,232,"START GAME  DEBUG MENU" --clear 216,232,320,240

$(BUILD)/still/gameover.bin: tools/pce_still.py tools/pce_stage.py $(BUILD)/title.snp
	cd tools && python3 pce_still.py gameover ../$(BUILD)/title.snp 2730 40 0 - 1 ../$(BUILD)/still \
		--keep 95,100,237,124 --grey

# Rastan's jump grunt and death cry: MSM5205 voice samples on the arcade.
$(BUILD)/voice/voice.bin: tools/pce_voice.py sim/adpcm.bin
	@mkdir -p $(BUILD)/voice
	cd tools && python3 pce_voice.py ../sim/adpcm.bin ../$(BUILD)/voice

sim/audiocpu.bin sim/adpcm.bin: sim/maincpu.bin

# The castle's lava hall: its flames and the sparks drifting off them.
$(BUILD)/hall.snp: sim/sim sim/maincpu.bin sim/scripts/hall.txt
	@mkdir -p $(BUILD)
	sim/sim sim/maincpu.bin sim/scripts/hall.txt $@ 1 4280

# The hurry-up swarm: Rastan waits at the round start until the bats come.
$(BUILD)/swarm.snp: sim/sim sim/maincpu.bin sim/scripts/swarm.txt
	@mkdir -p $(BUILD)
	sim/sim sim/maincpu.bin sim/scripts/swarm.txt $@ 1 2880

# The castle's floor spears (sprite cells resident in VRAM).
$(BUILD)/spikes.snp: sim/sim sim/maincpu.bin sim/scripts/spikes.txt
	@mkdir -p $(BUILD)
	sim/sim sim/maincpu.bin sim/scripts/spikes.txt $@ 1 1470

$(BUILD)/traps/traps.bin: tools/pce_traps.py $(BUILD)/spikes.snp $(PLAYER)/player.bin
	cd tools && PLAYER_PAL=$(abspath $(PLAYER))/sprpal.bin python3 pce_traps.py ../$(BUILD)/spikes.snp ../$(BUILD)/traps

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

# The ROM uses the Street Fighter II mapper (pceas --sf2; see src/main.asm). pceas
# pads it to 2 MB; SF2PAD makes it 2.5 MB, the size of the real card, which is how
# emulators recognise the mapper (MAME only accepts exactly that size).
SF2PAD     := python3 tools/pad_sf2.py

GAME_DEPS  := $(wildcard src/*.asm) $(BUILD)/debug/font.bin $(STAGE)/stage.bin $(STAGE2)/stage.bin $(STAGE3)/stage.bin $(PLAYER)/player.bin $(OBJECTS)/objcells.bin $(BUILD)/hud/hud.bin $(BUILD)/props/props.bin $(BUILD)/traps/traps.bin $(BUILD)/sound/sound.bin $(BUILD)/voice/voice.bin $(BUILD)/still/ending.bin $(BUILD)/still/title.bin $(BUILD)/still/gameover.bin

$(BUILD)/rastan.pce: $(GAME_DEPS)
	@mkdir -p $(BUILD)/opt
	printf "CAMERA_TEST = 0\nNO_ENEMIES = 0\nGOD_MODE = 0\nBG_CHECK = 0\nTITLE = 1\nDEBUG_MENU = 0\n" > $(BUILD)/opt/options.inc
	cd $(BUILD) && PCE_INCLUDE=$(abspath $(BUILD)/opt):$$PCE_INCLUDE $(PCEAS) --newproc --sf2 --strip -m -l 2 -S -gA --raw ../src/main.asm -o rastan.pce
	$(SF2PAD) $(BUILD)/rastan.pce

# Test build: straight into the game, with the debug menu in play (UP + SELECT
# held) for the tests' checkpoint warps. Not for playing: the menu draws over
# the stage.
$(BUILD)/testdbg.pce: $(GAME_DEPS)
	@mkdir -p $(BUILD)/opt_tdbg
	printf "CAMERA_TEST = 0\nNO_ENEMIES = 0\nGOD_MODE = 0\nBG_CHECK = 0\nTITLE = 0\nDEBUG_MENU = 1\n" > $(BUILD)/opt_tdbg/options.inc
	cd $(BUILD) && PCE_INCLUDE=$(abspath $(BUILD)/opt_tdbg):$$PCE_INCLUDE $(PCEAS) --newproc --sf2 --strip -l 0 --raw ../src/main.asm -o testdbg.pce
	$(SF2PAD) $(BUILD)/testdbg.pce

# Test build: the pad drives the camera directly and Rastan is not drawn.
$(BUILD)/camtest.pce: $(GAME_DEPS)
	@mkdir -p $(BUILD)/opt_test
	printf "CAMERA_TEST = 1\nNO_ENEMIES = 1\nGOD_MODE = 0\nBG_CHECK = 0\nTITLE = 0\nDEBUG_MENU = 1\n" > $(BUILD)/opt_test/options.inc
	cd $(BUILD) && PCE_INCLUDE=$(abspath $(BUILD)/opt_test):$$PCE_INCLUDE $(PCEAS) --newproc --sf2 --strip -l 0 --raw ../src/main.asm -o camtest.pce
	$(SF2PAD) $(BUILD)/camtest.pce

# Scroll the ROM through the whole stage and compare with the converter preview.
# Test build: no enemies, for the movement checks.
$(BUILD)/noenemy.pce: $(GAME_DEPS)
	@mkdir -p $(BUILD)/opt_noen
	printf "CAMERA_TEST = 0\nNO_ENEMIES = 1\nGOD_MODE = 0\nBG_CHECK = 0\nTITLE = 0\nDEBUG_MENU = 1\n" > $(BUILD)/opt_noen/options.inc
	cd $(BUILD) && PCE_INCLUDE=$(abspath $(BUILD)/opt_noen):$$PCE_INCLUDE $(PCEAS) --newproc --sf2 --strip -l 0 --raw ../src/main.asm -o noenemy.pce
	$(SF2PAD) $(BUILD)/noenemy.pce

# Test build: enemies on, but they can't hurt Rastan (to reach later sections).
$(BUILD)/god.pce: $(GAME_DEPS)
	@mkdir -p $(BUILD)/opt_god
	printf "CAMERA_TEST = 0\nNO_ENEMIES = 0\nGOD_MODE = 1\nBG_CHECK = 0\nTITLE = 0\nDEBUG_MENU = 1\n" > $(BUILD)/opt_god/options.inc
	cd $(BUILD) && PCE_INCLUDE=$(abspath $(BUILD)/opt_god):$$PCE_INCLUDE $(PCEAS) --newproc --sf2 --strip -l 0 --raw ../src/main.asm -o god.pce
	$(SF2PAD) $(BUILD)/god.pce

# Test build: god mode, and only the tile map is shown (no sprites, no colour
# cycling), so a whole playthrough can be compared with the converter's preview.
$(BUILD)/bgcheck.pce: $(GAME_DEPS)
	@mkdir -p $(BUILD)/opt_bg
	printf "CAMERA_TEST = 0\nNO_ENEMIES = 0\nGOD_MODE = 1\nBG_CHECK = 1\nTITLE = 0\nDEBUG_MENU = 1\n" > $(BUILD)/opt_bg/options.inc
	cd $(BUILD) && PCE_INCLUDE=$(abspath $(BUILD)/opt_bg):$$PCE_INCLUDE $(PCEAS) --newproc --sf2 --strip -l 0 --raw ../src/main.asm -o bgcheck.pce
	$(SF2PAD) $(BUILD)/bgcheck.pce

test: $(BUILD)/camtest.pce $(BUILD)/noenemy.pce $(BUILD)/rastan.pce $(BUILD)/testdbg.pce $(BUILD)/god.pce $(BUILD)/bgcheck.pce tools/tgrun/tgrun
	python3 tools/test_scroll.py $(BUILD)/camtest.pce $(STAGE)/preview.png $(BUILD)/test $$(seq 62 37 2950)
	PAD=46 python3 tools/test_scroll.py $(BUILD)/camtest.pce $(STAGE)/preview.png $(BUILD)/test_down 80 120 160 300
	KEYS=61:2175:44,2176:2540:01,2541:2930:44,2931:3300:01 python3 tools/test_scroll.py $(BUILD)/camtest.pce $(STAGE)/preview.png $(BUILD)/test_castle $$(seq 2150 30 3300)
	python3 tools/test_player.py $(BUILD)/noenemy.pce
	python3 tools/test_enemies.py $(BUILD)/testdbg.pce $(BUILD)/god.pce
	python3 tools/test_effects.py $(BUILD)/noenemy.pce $(STAGE)/dyncolor.inc
	python3 tools/test_debug.py $(BUILD)/testdbg.pce $(BUILD)/noenemy.pce
	python3 tools/test_items.py $(BUILD)/testdbg.pce $(BUILD)/god.pce $(BUILD)/noenemy.pce
	python3 tools/test_monsters.py $(BUILD)/testdbg.pce $(BUILD)/god.pce
	python3 tools/test_castle.py $(BUILD)/testdbg.pce $(BUILD)/god.pce $(BUILD)/noenemy.pce
	python3 tools/test_sound.py $(BUILD)/testdbg.pce $(BUILD)/god.pce $(BUILD)
	python3 tools/test_demo.py $(BUILD)/rastan.pce $(BUILD)/still
	python3 tools/test_round2.py $(BUILD)/testdbg.pce $(BUILD)/god.pce
	python3 tools/test_round3.py $(BUILD)/testdbg.pce $(BUILD)/bgcheck.pce $(BUILD)/god.pce $(STAGE3)

# A whole playthrough, checkpoint by checkpoint (about 2 minutes): object
# poses, slowdown, SATB use, and the tile map against the converter's preview.
# Contact sheets and logs go to build/audit and build/audit_bg.
audit: $(BUILD)/god.pce $(BUILD)/bgcheck.pce tools/tgrun/tgrun
	cd tools && python3 audit.py ../$(BUILD)/god.pce ../$(BUILD)/audit
	cd tools && AUDIT_EVERY=10 AUDIT_PREVIEW=../$(STAGE)/preview.png python3 audit.py ../$(BUILD)/bgcheck.pce ../$(BUILD)/audit_bg

tools/tgrun/tgrun: tools/tgrun/tgrun.c tools/tgrun/build.sh $(wildcard tools/tgemu/src/*.[ch] tools/tgemu/src/*/*.[ch])
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

.PHONY: all clean test lockstep audit
