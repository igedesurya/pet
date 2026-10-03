# Nori rumah outfit

Approved look, locked by the user. Use this for every new or edited clip in `Resources/characters/nori-rumah/`.

## Clothes

- Above the waist: an opaque cream tank top only. The hem ends at the waist.
- Below the hem: bare legs and bare feet. No leggings, shorts, pants, skirt, apron, or nightgown.
- Seated home clips keep both knees together. Sleep stays cross-legged.
- The Pesona clips are the exception: she faces forward with both legs spread wide, wider adult hips, and a defined waist. `pesona` raises the arms, `pesona_rest` sits and looks forward, `pesona_hair` tucks her hair, and `pesona_knee` lifts one knee and rests both hands on it. Do not copy that pose onto tea, reading, eating, or waking.
- A hem that covers the hips reads as a child. Do not lengthen the tank.

## Body

Adult woman: long legs, smaller head, adult shoulders and waist. Match the approved sleep clip, not a chibi silhouette.

## How to change a clip

1. Reference `Resources/characters/nori-rumah/home_sleeping/00.png` for identity and clothes. Do not use `nori-terang` idle; that reference copies the sports outfit and leggings.
2. Generate one 16:9 strip, flat magenta `#FF00FF`, six full-body figures, even gaps, feet inside the frame, same scale in every cell.
3. Slice with `swift /tmp/slice_mood.swift <strip.jpg> <clip-folder>`.
4. If an equal-width cut leaves a stray limb, delete alpha islands smaller than the largest component divided by 8. Do not blob-erase the whole frame.
5. Leave the already approved clips in place: `idle`, `home_reading_book`, `home_eating`, `home_waking_up`, `home_sleeping`.

`home_drinking_tea` uses the same tank and bare legs, seated with a cup.
