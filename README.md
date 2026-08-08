# Raichu Unlock

Lets your starter **PIKACHU** evolve into **RAICHU** with a **THUNDER STONE**
in Pokémon Yellow — and lets a second Thunder Stone turn it back.

## Why this is needed

Yellow refuses the stone on the Pikachu Oak gives you. The check is an
**owner-identity** test, not a species test — `item_effects.asm` runs
`IsThisPartyMonStarterPikachu` before `TryEvolvingMon` and bails to the voiced
cry and "PIKACHU is refusing!". Gen1Recomp reproduces it faithfully in
`src/inventory/ItemEffects.lua`.

So in principle a Pikachu that isn't yours would evolve fine. In practice
there is no such Pikachu: grepping the Yellow disassembly's `data/wild/maps`
for `PIKACHU` or `RAICHU` returns **nothing**. Yellow took wild Pikachu out of
Viridian Forest and never put one in the Power Plant (that's
Magnemite/Voltorb/Grimer). One Pikachu exists on the cartridge, and it's the
one that says no — which makes Raichu unobtainable without a link trade.

The evolution *data* is intact. `evos_moves.asm` still carries
`db EVOLVE_ITEM, THUNDER_STONE, 1, RAICHU` under Pikachu, so the row is right
there in the data extracted from your own ROM. Nothing is invented here; only
the refusal is lifted.

## What it changes

Two things, both through the same seam. When a stone is used outside battle
on a Pokémon that's yours (OT-matched, same identity check the engine already
uses):

- **On your PIKACHU** — evolves it, same as any legal stone evolution.
- **On your RAICHU** — reverts it back to PIKACHU, using whatever item
  PIKACHU's own data says evolves it (looked up fresh each time, not
  hardcoded to `THUNDER_STONE` by name). Vanilla stones do nothing to a
  Raichu (`RaichuEvosMoves` has no evolutions at all), so this claims an
  otherwise-dead case rather than overriding anything.

Both directions return the same result the engine's own stone branch returns
for a legal evolution and let `BagMenu`/`Evolution.evolve` take it from
there — consume the item, close the bag, play the movie, run the evolved
species' level-up move check. `Evolution.apply` is symmetric by construction:
it recalculates stats for the new species at your current level and preserves
the **HP deficit**, not the HP value, so a revert doesn't heal or clip you.
It also never clears the Pokédex entry for the species you're leaving, so
RAICHU stays marked seen/owned across a revert.

Neither direction touches `PikachuFollower` — it keys purely on
`mon.species == "PIKACHU"`, so the walking companion and Pikachu's Beach
disappear when you evolve and **come back on their own** when you revert.

It does **not** edit or delete the engine's refusal check. It runs ahead of
it for exactly these two cases. Everything else falls through to the
untouched original:

| Situation | Behavior |
|---|---|
| Stone used in battle | Unchanged — OAK's "this isn't the time" |
| Any other Pokémon | Unchanged — the owner test only matches your Pikachu/Raichu |
| Any other item | Unchanged — only stones are considered |
| Wrong stone on Pikachu | Unchanged — no `FIRE_STONE` evolution row exists, so it isn't diverted |
| Cancelling the movie | Not possible either direction, same as vanilla stones (`via = "ITEM"`) |
| Stone on the refuse path | Still not consumed, because there is no refuse path anymore |

The mod's own logic is wrapped in `pcall`. `ItemEffects.use` isn't fenced by
`Pipelines.guardRender`, so an unguarded throw there would take the frame
down. If anything in the mod errors, the call proceeds to vanilla — the
failure mode is "refusing" or "no effect," not a crash in the bag.

## One cosmetic wart, kept on purpose

`EvolutionState`'s on-screen text is hardcoded "is evolving!" / "evolved
into," in that direction only — it isn't written to be reused in reverse. So
reverting shows:

> What? RAICHU is evolving! ... Your RAICHU evolved into PIKACHU!

Which reads a little backwards. Everything *else* about the flow — stat
recalculation, HP-deficit preservation, the sprite flash, the cry,
non-cancelability, the post-transform move check — is the real engine screen,
unmodified, run in both directions. Rewriting the text would mean
reimplementing that screen instead of calling it, just for a wording nicety.

## Also worth knowing

Raichu learns nothing by level-up in Gen 1 (`RaichuEvosMoves` is empty), so
there's no move progression lost by evolving early, or gained back by
reverting late — the moveset just tracks whichever form you're currently in
at your current level.

## Options

MODS → RAICHU UNLOCK → OPTIONS

| Option | Default | Effect |
|---|---|---|
| `ALLOW EVOLUTION` | ON | Off restores the vanilla refusal on Pikachu without uninstalling |
| `ALLOW REVERT` | ON | Off makes evolving one-way again (a stone on Raichu goes back to "no effect") |

Both read live — no restart needed.

## Install

Launcher → MODS → Import mod .zip → pick `raichu-unlock-0.1.0.zip`.

## How to check it works

Get two THUNDER STONEs (Celadon Department Store, 4F). Use one on your
Pikachu outside of battle — vanilla plays its cry and prints "PIKACHU is
refusing!"; modded, you get the evolution movie into Raichu. Use the second
on the resulting Raichu — you should get the (backwards-worded) movie back
to Pikachu, and the walking Pikachu follower should reappear on the next
map you enter.

## Status

**0.1.0, untested.** Built and reasoned against the engine source; not run.
