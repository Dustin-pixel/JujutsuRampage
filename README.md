# Jujutsu Rampage

A Roblox fighting game where **every player designs their own cursed technique from scratch**. You build moves out of blocks in an in-game skill builder, make your own VFX from particle emitters and meshes, and share both as text codes.

## Features

- **Skill builder.** Each technique has up to 6 moves. A move is a trigger (Press, Hold to Charge, Counter, Combo Finisher, or Passive) followed by an ordered list of blocks. Blocks cover hitboxes, projectiles, damage, knockback, stun, grabs, dashes, teleports, healing, super armor, animations, VFX, sounds, and camera shake. Blocks like `Repeat`, `If`, `Hitbox → onHit`, and `Projectile → onHit` hold nested branches.
- **Budgets.** The builder shows each move's total damage, duration, hitbox count, and so on against the limits in `Config.luau`, and raises cooldowns to match a move's power. Imported codes go through the same checks, so nobody can import a broken move.
- **Share codes.** Techniques and effects export as `JJR1.M.…` or `JJR1.V.…` codes, which are compressed with a checksum. A technique code carries the effects it uses, so one code shares everything.
- **VFX editor.** Stack Emitter, Mesh, Beam, and Light layers. Edit every property, including color and size sequences. A live preview plays in front of your character. Meshes can use your own uploaded mesh IDs or built-in shapes (sphere, cylinder, block, wedge).
- **Domain expansions.** A barrier with sure-hit ticks, trapping, refinement-based domain clashes, and burnout afterward.
- **Charge moves and variables.** Hold to charge and scale damage or knockback with the charge. Move-scope and fighter-scope variables let you build stacks and empowered follow-ups.
- **Public gallery.** Publish techniques, browse them by newest or most liked, like, report, and import with one click.
- **Animation library.** You upload animations once, and players pick them by name in the builder.
- **Smooth projectiles.** Clients animate projectiles locally while the server checks hits.
- **Studio VFX exporter plugin.** Build an effect in Studio with real ParticleEmitters, Beams, lights, and MeshParts, click **Export VFX**, and paste the code into the game.
- **Basics.** M1 combos, blocking (F), cursed energy, training dummies, DataStore saves with session locking, and text filtering.

## Setup

1. Install [Rokit](https://github.com/rojo-rbx/rokit), then run this in the repo to get the pinned Rojo version:

   ```bash
   rokit install
   ```

2. Install the Rojo plugin in Roblox Studio (`rojo plugin install`, or get it from the Creator Store).
3. Start the sync server:

   ```bash
   rojo serve
   ```

4. In Studio, open a Baseplate, click **Rojo → Connect**, and press **Play**.
5. Optional: to test saving, turn on *Game Settings → Security → Enable Studio Access to API Services*. If it's off, you play with a temporary profile that is never saved.

To build a place file instead:

```bash
rojo build -o JujutsuRampage.rbxlx
```

### Controls

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Moves 1–6 | `1`–`6` | X, Y, B, D-pad |
| M1 | Left click | R2 |
| Block (hold) | `F` | L2 |
| Open builder | `B` | — |

On mobile, the hotbar and the M1 and Block buttons appear on screen.

### Running the tests

Sync the place, then run this in Studio's command bar:

```lua
require(game.ReplicatedStorage.Tests.RunTests)()
```

### Installing the VFX exporter plugin

```bash
rojo build plugin.project.json -o JJRVfxExporter.rbxm
```

Put `JJRVfxExporter.rbxm` in your Studio Plugins folder (*Plugins → Plugins Folder*). Open a place that has the game code synced, select the Part, Model, or Attachment that holds your effect, and click **JujutsuRampage → Export VFX**. The plugin's header comment lists the optional attributes (`Delay`, `EmitCount`, `Duration`, `EndScale`, `Spin`, …) for timing control.

## Animation library (do this before launch)

Roblox only plays animations owned by the game's creator, so players can't use their own uploads. Animate a set of moves (punches, kicks, casting poses, hand signs), publish them under the account or group that owns the game, and list them in `src/shared/AnimationLibrary.luau`:

```lua
{ key = "punch_r", name = "Right Punch", id = "1234567890" },
```

Never change a `key` once players are using it, because share codes store the key.

## Gallery notes

- Gallery data lives in the DataStore `Gallery_v1`. Each server batches writes to the shared index every 20 s, because DataStores limit how often one key can be written. A new like can take up to about a minute to show up on other servers.
- Entries with 5 or more reports are hidden. For moderation, look up the entry in `index` with a DataStore editor plugin and remove it.
- Only techniques that pass the budget can be published. Imports from the gallery are validated exactly like pasted codes.

## Project layout

```
src/shared/      code shared by client and server (ReplicatedStorage.Shared)
  Config         every limit and budget
  Schema/        Blocks (the block registry) and Triggers
  Codec/         Base64, LZW, CRC32, and ExportCode (share codes)
  Validate/      Sanitize, MovesetValidator, VfxValidator (everything untrusted goes through these)
  Vfx/           VfxSchema (allowed layers and properties), VfxSerialize, VfxBuilder (plays effects)
  Presets        the starter technique and starter effects
src/server/      CombatService, DomainService, GalleryService, Runtime/Executor + Actions, MovesetService, DataService, VfxService, Dummies
src/client/      InputController, VfxPlayer, Store, UI/ (App, SkillBuilder, VfxEditor, Gallery, Components)
plugin/          the Studio VFX exporter
tests/           specs for the codec and validators
docs/BLOCKS.md   block reference and code format
```

## Security model

Everything that comes from a player, whether a remote call, a pasted code, or a saved profile, is treated as untrusted data:

- Codes are only ever **decoded into plain tables**. Nothing in a code is executed.
- Validators keep only **whitelisted** block types, VFX layer kinds, and properties. They clamp every number, drop NaN and infinity, cap list sizes, nesting depth, and code length, and only accept numeric asset IDs.
- The server runs moves with a hard deadline and cancels them on stun or death. Remotes are rate limited.
- Player-written names and descriptions go through `TextService` filtering.

## Adding a new block

1. Add a definition to `src/shared/Schema/Blocks.luau`, with its fields and an optional budget.
2. Add a handler with the same ID to `src/server/Runtime/Actions.luau`. The server refuses to start if a handler is missing.
3. Document it in `docs/BLOCKS.md`.

The builder palette and inspector pick it up automatically.

## Roadmap ideas

- **Ranked/casual queues.** These need a lobby place plus arena places, connected with `TeleportService` and `MemoryStoreService` for matchmaking. That means publishing several places under one universe, so it's best done once the core gameplay feels right.
- **Client-side hit prediction.** Show hit effects instantly on the attacker's screen while the server stays authoritative.
- **Domain extras.** Custom barrier meshes, domain amplification, and Simple Domain as a counter to sure-hit.
- **More triggers.** On-dodge, and low-HP awakening.
