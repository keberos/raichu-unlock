-- Raichu Unlock
--
-- Lets the starter PIKACHU evolve into RAICHU with a THUNDER STONE, and
-- undo it again the same way.
--
-- ------- why this needs a mod at all
--
-- Yellow's item_effects.asm runs IsThisPartyMonStarterPikachu before
-- TryEvolvingMon and bails to the voiced cry + _RefusingText, and the engine
-- reproduces that faithfully in src/inventory/ItemEffects.lua:
--
--     if target.species == "PIKACHU"
--        and require("src.core.GameVersion").isYellow()
--        and target.ot == save.player.name
--        and target.otId == save.player.id then
--       ... playCry, return "failed", _RefusingText
--     end
--
-- It is an OT-identity test, not a species test, so a Pikachu that is NOT
-- yours already evolves normally in the engine today. That escape hatch is
-- theoretical on a solo file, though: grepping pokeyellow's data/wild/maps
-- for PIKACHU or RAICHU turns up nothing at all -- Yellow removed wild
-- Pikachu from Viridian Forest and never put one in the Power Plant (that is
-- Magnemite/Voltorb/Grimer). So without a link partner there is exactly one
-- Pikachu on the cartridge, and it is the one that refuses.
--
-- The evolution DATA is intact, incidentally. pokeyellow's evos_moves.asm
-- still has `db EVOLVE_ITEM, THUNDER_STONE, 1, RAICHU` under Pikachu, so
-- data.pokemon.PIKACHU.evolutions has the row extracted from the player's
-- own ROM. Nothing has to be invented here -- only the refusal removed.
--
-- ------- where the refusal can be caught
--
-- Not in the evolution layer. src/pokemon/Evolution.lua has an
-- `evolution.check` hook, but the refusal short-circuits well before it:
-- ItemEffects.use returns "failed" without ever calling Evolution.pendingFor,
-- so there is no evolution to approve. There is no item.use hook either
-- (ItemEffects.lua calls Runtime exactly zero times). So the seam is
-- ItemEffects.use itself, monkey-patched.
--
-- ------- what the patch actually does
--
-- It does NOT remove or edit the engine's refusal check. It runs ahead of it,
-- and only for the two exact cases below, returning the same triple the
-- engine's own stone branch returns for a legal evolution:
--
--     return "consumed", nil, { evolveTo = <species> }
--
-- Which means BagMenu's `result == "consumed"` path handles the rest exactly
-- as it does for a vanilla stone: decrement the item, refresh the bag counts,
-- close the list, and call Evolution.evolve(game, target, to, nil, "ITEM").
-- Passing via = "ITEM" is load-bearing -- it is what makes the movie
-- non-cancelable (mirroring wForceEvolution), so the stone cannot be spent
-- and then B'd out of (engine #883). That applies equally to the revert:
-- once you commit a stone to it, it isn't cancelable either.
--
-- Case 1, evolve: THUNDER STONE on your PIKACHU. Same as the original
-- 0.1.0 behavior.
--
-- Case 2, revert: THUNDER STONE on your RAICHU. Vanilla stones have no
-- ITEM evolution row for RAICHU (RaichuEvosMoves is two zero bytes in the
-- disasm), so this case is otherwise dead -- a stone on a Raichu just
-- prints "won't have any effect". The mod claims that dead case ONLY when
-- the stone that would trigger it is the very one PIKACHU's own evolution
-- data lists (looked up fresh each time, not hardcoded to THUNDER_STONE by
-- name), so if a mod ever changes what stone evolves Pikachu, the reverse
-- direction follows it automatically.
--
-- Evolution.apply (called inside Evolution.evolve, either direction) is
-- symmetric by construction: it recalculates stats for the new species at
-- the current level/DVs/stat-exp and preserves the HP *deficit* rather than
-- the HP value, so reverting doesn't heal or clip the mon. It also doesn't
-- touch the Pokedex entry for the species you're leaving, so RAICHU stays
-- marked seen/owned across a revert -- you don't lose the dex entry you
-- earned. PikachuFollower keys purely on `mon.species == "PIKACHU"`, so the
-- walking companion and Pikachu's Beach resume on their own the moment the
-- species flips back; nothing in this mod has to touch that system at all.
--
-- One cosmetic wart, accepted on purpose: EvolutionState's on-screen text is
-- hardcoded to "is evolving!" / "evolved into", in that direction, and it
-- isn't parameterized for reuse in reverse. Reverting a Raichu shows
-- "What? RAICHU is evolving! ... Your RAICHU evolved into PIKACHU!" -- which
-- reads a little backwards, but it is the ONLY thing that reuses the
-- engine's text. Everything else about the flow (stat recalc, HP-delta
-- preservation, sprite flash, cry, non-cancelability, the post-evolution
-- level-up move check) is the real engine machinery, unmodified, run in
-- both directions. Rewriting the text would mean reimplementing
-- EvolutionState's screen instead of calling it, for a wording nicety.
--
-- Everything the mod does not divert falls through to the original function,
-- so all the surrounding vanilla behavior is untouched by construction:
--
--   in battle           `not battle` gates the patch, so a stone mid-fight
--                       still gets ItemUseNotTime's OAK text
--   any other mon       the OT test only matches your own Pikachu/Raichu
--   any other item      only ItemEffects.isStone ids are considered
--   wrong stone         a FIRE STONE on Pikachu finds no ITEM evolution row
--                       for FIRE_STONE, so it is not diverted and the
--                       vanilla refusal (or no-effect) still prints
--
-- The pcall is deliberate. ItemEffects.use is not one of the render
-- callbacks Pipelines.guardRender fences, so a throw in here would take the
-- frame down. Wrapped, any error in the mod's own logic just means the
-- lookup comes back nil and the call proceeds to vanilla -- the failure
-- mode is "no effect" or "refusing", not a crash in the bag.

return function(mod)
  local GameVersion = require("src.core.GameVersion")
  local ItemEffects = require("src.inventory.ItemEffects")

  -- Read live, so toggling either in MODS -> RAICHU UNLOCK -> OPTIONS takes
  -- effect on the next stone with no restart.
  mod.options:define({
    { key = "allow_evolve", label = "ALLOW EVOLUTION", type = "toggle",
      default = true },
    { key = "allow_revert", label = "ALLOW REVERT", type = "toggle",
      default = true },
  })

  -- item_effects.asm's IsThisPartyMonStarterPikachu, generalized to either
  -- species: OT-identity match on the current player. Since Yellow has no
  -- wild Pikachu or Raichu (see header) and evolution never touches
  -- mon.ot/otId, this is "is this mon your starter, in whichever form it's
  -- currently in" -- so it correctly excludes a Raichu received over Link
  -- (its OT is the trading partner, not you).
  local function ownedByPlayer(save, mon)
    return GameVersion.isYellow()
       and save ~= nil and save.player ~= nil
       and mon.ot == save.player.name
       and mon.otId == save.player.id
  end

  -- The ITEM evolution row for this stone on the given species, out of the
  -- player's own extracted ROM data. nil means the stone genuinely does
  -- nothing there and we must not divert it.
  local function speciesEvolvesVia(data, speciesId, itemId)
    local def = data and data.pokemon and data.pokemon[speciesId]
    for _, evo in ipairs((def and def.evolutions) or {}) do
      if evo.method == "ITEM" and evo.item == itemId then
        return evo.species
      end
    end
    return nil
  end

  -- Returns the species to transform into, or nil to let vanilla handle it.
  local function forcedTransform(data, save, itemId, target, battle)
    if battle then return nil end
    if not target then return nil end
    if not ItemEffects.isStone(itemId) then return nil end
    if not ownedByPlayer(save, target) then return nil end

    if target.species == "PIKACHU" and mod.options:get("allow_evolve") then
      return speciesEvolvesVia(data, "PIKACHU", itemId)
    end

    if target.species == "RAICHU" and mod.options:get("allow_revert") then
      -- Revert only with whatever item PIKACHU's own data says evolves it
      -- into RAICHU -- derived fresh, not hardcoded to THUNDER_STONE.
      if speciesEvolvesVia(data, "PIKACHU", itemId) == "RAICHU" then
        return "PIKACHU"
      end
    end

    return nil
  end

  -- Guard the original behind a mod-owned field so a reload wraps the engine
  -- function again rather than wrapping our own wrapper.
  local original = ItemEffects._raichuUnlockOriginal or ItemEffects.use
  ItemEffects._raichuUnlockOriginal = original

  function ItemEffects.use(data, save, itemId, target, battle, moveIndex, ow)
    local ok, species = pcall(forcedTransform, data, save, itemId, target,
                              battle)
    if ok and species then
      mod.log:info("%s -> %s via %s", target.species, species,
                   tostring(itemId))
      return "consumed", nil, { evolveTo = species }
    end
    return original(data, save, itemId, target, battle, moveIndex, ow)
  end
end
