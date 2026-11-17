# Block reference

The single source of truth is `src/shared/Schema/Blocks.luau`. This page explains how the blocks behave.

## Triggers

| Trigger | Fields | Behaviour |
| --- | --- | --- |
| **Press** | — | Runs when you press the move's key. |
| **Counter** | `window` 0.2–1.5s | Pressing opens a counter window. If someone damages you during it, their hit is cancelled and the move runs with the **attacker as the target**. |
| **ComboFinisher** | — | Runs automatically, **with the target**, when the 4th M1 of a combo lands. |
| **Passive** | `interval` 3–60s | Runs on its own every *interval* seconds (or the cooldown, if that's longer). |

Blocks that need a target (Damage, Knockback, Stun, Grab) only work inside a Hitbox or Projectile `onHit` slot, or at the root of a Counter or ComboFinisher move.

## Blocks

| Category | Block | Fields | Notes |
| --- | --- | --- | --- |
| Flow | **Wait** | seconds 0–3 | Pauses the move. |
| Flow | **Repeat** | count 1–10 · `body` | Multiplies the budget of everything inside. |
| Flow | **If** | condition, value · `then` / `else` | Conditions: AnyTargetHit, HealthBelow (%), EnergyAbove (CE), Chance (%), Airborne, TargetBlocking. |
| Flow | **Stop Move** | — | Ends the move. |
| Combat | **Hitbox** | shape, size, offset, duration 0–1, maxTargets · `onHit` | `onHit` runs once per enemy hit, each in its own thread. With duration 0 it checks once. |
| Combat | **Projectile** | speed, range, radius, pierce, offset, vfx · `onHit` | Flies toward the camera aim, or toward the target after **Face Nearest Enemy**. Stops at walls. |
| Combat | **Damage** | amount 0–30, guardBreak, ignoreArmor | A blocking target takes 25%. guardBreak breaks the block and stuns. Super armor reduces damage to 70%. |
| Combat | **Knockback** | direction, force 0–120 | Ignored against super armor. |
| Combat | **Stun** | seconds 0–2.5 | Ignored against super armor. A stunned caster's move is cancelled. |
| Combat | **Grab** | seconds, offset | Holds the target in front of you. |
| Movement | **Dash** | direction, distance, seconds | Relative to where you face. |
| Movement | **Face Nearest Enemy** | range | Also aims later projectiles. |
| Movement | **Teleport** | mode Forward / BehindTarget, distance | Won't pass through walls. |
| Self | **Spend Cursed Energy** | amount | If you don't have enough, the move stops here. |
| Self | **Heal** | amount 0–30 | |
| Self | **Super Armor** | seconds 0–2 | |
| Self | **Speed Boost** | multiplier, seconds | |
| Visual | **Play Animation** | animationId, speed, stopPrevious | The animation must belong to the game's owner (user or group). |
| Visual | **Play VFX** | effect, at Self / Target / InFront, offset, seconds | |
| Visual | **Play Sound** | soundId, volume, pitch | |
| Visual | **Camera Shake** | intensity, seconds, radius | Shakes nearby players' cameras. |

## Budgets (per move, in `Config.Budget`)

| Limit | Default |
| --- | --- |
| Total damage per target (Repeat multiplies) | 60 |
| Total Wait, Dash, Hitbox, and Grab time | 8 s |
| Hitboxes (Repeat and maxTargets multiply) | 12 |
| Projectiles | 8 |
| Healing | 30 |
| Minimum cooldown | `max(1, damage / 12, heal / 2)` s |

A technique that breaks a budget can still be **saved**, so you don't lose work, but it can't be **equipped** until you fix it.

## Share code format

```
JJR1.<kind>.<payload>.<crc32>
  kind     M = technique (moveset), V = VFX effect
  payload  base64url( LZW( JSON({ v = 1, data = … }) ) )
  crc32    8 hex characters over the payload text, used to catch typos and truncation
```

Decoding produces plain data, which then goes through `MovesetValidator` or `VfxValidator`. When an imported technique contains effects, those effects get fresh IDs in your library, so they never overwrite your own.

### Moveset data

```lua
{
  name = "Cursed Strikes", description = "...", color = { r, g, b },
  moves = {
    { name = "Divergent Fist", cooldown = 5,
      trigger = { type = "Press", fields = {} },
      blocks = {
        { type = "Hitbox", fields = { shape = "Box", size = {5,5,6}, ... },
          children = { onHit = { { type = "Damage", fields = { amount = 7 } } } } },
      } },
  },
  vfx = { [effectId] = effect },
}
```

### VFX data

```lua
{
  name = "Impact",
  layers = {
    { kind = "Emitter" | "Mesh" | "Beam" | "Light", name = "...", offset = {x,y,z}, props = { ... } },
  },
}
```

`src/shared/Vfx/VfxSchema.luau` lists every allowed property, with its type and range. Value encodings: colors are `{r,g,b}` (0–255), ColorSequences are `{{t,r,g,b},…}`, NumberSequences are `{{t,value,envelope},…}`, ranges are `{min,max}`, and assets are digit-only strings.
