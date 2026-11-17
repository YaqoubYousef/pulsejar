# App family identity

Rules shared by every app Yaqoub makes, so they read as one family. PulseJar is the first member and the reference.

## Icons: one object, one carved line

- Each app icon is **one bold silhouette** of an everyday Levantine object (pottery, coffee ware, lanterns, woven things).
- **One line is carved through it** in the background colour, and that line says what the app does. PulseJar: a clay *jarra* carved with a heartbeat.
- Same craft on every icon: full-bleed square tile (iOS rounds the corners), the object fills about 60% of the tile, carved line about 1.5% of the tile wide with round joins, ear handles and rim drawn with round ends.
- Avoid shapes that read as a house: no single roof-like peak on top of two parallel "walls".

## Colour

| Role | Name | Hex |
|---|---|---|
| Background of every icon and splash screen | Night | `#13202E` |
| Accent (PulseJar) | Clay | `#C8643B` |
| Seal: first side | Sand | `#E9D3B4` |
| Seal: the shared part (blend of sand and clay) | Blend | `#D89C78` |
| Text on night | Cream | `#F3E9DC` |

Every app keeps **Night** as its background and picks **one earthy accent** for its object (clay, olive, copper, sand, indigo). No gradients.

## The maker's seal

Source: [brand/seal.svg](brand/seal.svg). In code: `MakerSeal` in `PulseJar/Views/BrandViews.swift`.

- **Two figures with raised arms**: the initials **YY**, and two people celebrating.
- **Sand and clay**: the two sides of one person.
- They **hold the eight-point star** (the Levantine tile star) between their hands, in the **blend** colour, because it's made of both.
- Soft style: round ends and joins, even arms, short legs.
- It never goes on an app icon. It appears small at the bottom of the splash screen and at the end of Settings, next to "made by Yaqoub" and the version.

## Files

- `brand/app-icon.svg`: PulseJar icon master (1024 px, full bleed)
- `brand/jar-mark.svg`: the jar alone, for the splash screen
- `brand/seal.svg`: the maker's seal
- `explorations/`: earlier rounds, kept locally and not committed
