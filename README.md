<p align="center"><img src="docs/logo.png" width="128" alt="Myrling's logo, a small green pixel creature"></p>

# Myrling

A pixel editor for tiny game creatures, born in Realms of Eldermyr. One HTML file.
Open it and draw.

    open index.html

No build, no server, no install, no internet. Double click the file, or drag it onto a
browser window. Everything runs locally and nothing is uploaded anywhere. Use Chrome or
Edge if you can: they are the browsers that can save your edits straight back into the
files you opened. There is also a small Mac app, below.

MIT licensed. Take it, fork it, ship your own creatures with it.

**Try it without downloading anything:** the editor runs at
[josiah-turnquist.github.io/myrling-sprite-editor/editor.html](https://josiah-turnquist.github.io/myrling-sprite-editor/editor.html),
and the landing page lives at
[josiah-turnquist.github.io/myrling-sprite-editor](https://josiah-turnquist.github.io/myrling-sprite-editor/).
Saving in place works there too — the page is served over HTTPS, so Chrome and Edge
allow it. After editing `index.html`, `make site` refreshes the hosted copy — and gives
it a new version number, which is how installed Mac apps find out there is one.

## The window

The canvas is the whole window. Everything else floats over it: the top bar with the
sprite's folder and name, a Sprites panel and a Tools panel down the left, a frames dock
along the bottom, and one tabbed inspector on the right — **Preview** and **Checks**,
with the colour and palette in the Tools panel. The path after the name says where saving will write; click it to pick a
different folder. When a sprite has warning flags, an amber pill in the top bar counts
them, and turns red when the packer would refuse it; either one jumps to the Checks
tab. **+** in the Sprites panel opens PNGs or starts a blank sprite, and the small ×
beside a sprite closes it (twice, on purpose).

## Made for one game, useful for yours

The rules baked into this editor — square frames, at most 32 colours, every pixel fully
solid or fully clear, feet on the bottom row — are the art rules of Realms of Eldermyr,
the game it was built for. You do not need that game for any of this to be useful: it is
still a tiny pixel editor that saves straight back over your PNGs. Everything
game-specific sits in plain sight in `index.html` — the checks, the path bar text, the
reference creatures and grounds in the game size view — so making it enforce your own
game's rules is an afternoon of editing one file. Sections below that talk about "the
game" or "the packer" are describing Eldermyr's; read them as the ones you would swap
for your own.

## The Mac app

The same editor in its own window and Dock icon, with in-place saving done natively.
There is a built copy on the
[releases page](https://github.com/Josiah-Turnquist/myrling-sprite-editor/releases/latest):
download the zip, unzip it, drag Myrling into Applications.

The download is signed with an Apple Developer ID and notarised by Apple, so it opens
with an ordinary double-click — no right-click, no warning box. Every release is built,
signed and notarised on a clean machine by the workflow in `.github/workflows`, never
from someone's laptop.

Or build it yourself. It needs the Xcode command line tools once
(`xcode-select --install`), then:

    make app     # builds dist/Myrling.app
    make run     # builds and opens it

The wrapper is one Swift file, `mac/main.swift`, around the very same `index.html` — the
web page is not changed at all. WebKit has no File System Access API, so `mac/bridge.js`
fills in the little of it the editor uses and hands the work to the Swift side: Open PNGs
shows the real open panel, Save over writes the real files, Export lands in your
Downloads folder. A build you make yourself is built for your machine and ad-hoc signed,
which is all a local tool needs.

The icon is itself a 16 pixel sprite, drawn by `mac/make-icon.py` (`make icon` redraws
it, plus `docs/logo.png` and the page's favicon).

### It keeps its editor current

The app is a window around a web page, so the page is the part that changes most and the
part worth updating quietly. On launch Myrling asks GitHub Pages whether the hosted
editor has moved on, and if it has, takes the new page and uses it from the next launch.
Fixes reach your copy without you downloading anything.

In the **Myrling** menu: **Check for Updates…** asks right now and tells you either way,
and the toggle beside it turns the launch check off if you would rather it did not.
Turning it off leaves the app on whatever page it already has, which keeps working.

Nothing is taken on trust. Every published page is signed with an Ed25519 key, over the
page's version and the SHA-256 of its exact bytes. The app carries the public half, and
before it keeps a downloaded page it hashes what it actually received and checks the
signature against it. **If that does not verify, the update is refused** and the app
stays on the page it has — a page that was tampered with in transit, or served by
something that is not us, cannot get in that way.

### Cutting a release

`make site` is the publish step for the editor page, and should be run before committing
any change to `index.html`. It gives the page today's version (`2026.09.22.1`, counting
up if you ship more than once in a day), copies it to `docs/editor.html`, and writes
`docs/update.json` — the little manifest the app reads, carrying the version, the hash
and the signature. Commit and push, and GitHub Pages serves it.

Releasing the app itself, when `mac/` has changed:

    make release VERSION=1.1       # stamps the version, republishes, commits, tags v1.1
    git push && git push origin v1.1

It refuses if the working tree is dirty — a release tag has to point at a finished
commit — and stops before touching anything if the signing key is missing. Pushing the
tag is what actually builds: `.github/workflows/release.yml` builds `Myrling.app` on a
Mac runner, zips it with `ditto`, and attaches it to a GitHub Release with notes made
from the commits since the previous tag. Nothing happens until the tag is pushed.

### The signing key

The private key lives at **`~/.myrling/update-key.b64`** — base64 of 32 raw bytes,
outside the repository on purpose. It is never committed and never copied into CI; the
release workflow does not need it, because the page is published from the maintainer's
own machine, not from a runner. `tools/sign.swift` does the signing with CryptoKit
(macOS ships LibreSSL, which cannot do Ed25519 at all).

**Back it up somewhere safe.** The public half is baked into every copy of the app
already in people's hands, so if the private key is lost, no page can ever be signed for
those copies again and their updates stop for good — there is no way to re-key them
short of everyone downloading the app again. For the same reason `make site` refuses to
run without it rather than writing an unsigned or stale manifest, which would look fine
and silently break every installed copy.

## Why this exists

The game used to store creature art as rows of characters plus a palette, painted one
rectangle at a time while the game ran. It does not any more. It loads real PNG files, so
what you draw here is exactly what ships. That means a plain image editor is the right
tool, and this one has the game's rules built into it.

## Your work is kept

Everything open is written into this browser after every change, and comes back the next
time you open the page. The bottom left corner always says what is being held, how big it
is and when it was last written, and clears the lot in two presses.

Two things it does not keep:

- **Undo history.** A stale undo stack is worse than none, so undo starts fresh each time.
- **Anything after you press Close or Forget all.** Both ask twice before they do it.

If the browser refuses to keep anything, the same corner says so in plain words rather
than losing the work quietly. Keeping it in the browser is not a backup: export the files
when a creature is done.

## Where the files go

This section is the Eldermyr team's workflow. If that is not you, the short version:
Export downloads `name-0.png`, `name-1.png` and so on, Save over writes them back where
they came from, and the path bar is yours to repoint at your own game's art folder.

The path after the name in the top bar says exactly where the files go, and follows the
name as you type it:

    creatures / miretoad   → art-live/creatures/miretoad-0.png, miretoad-1.png

Hover it for the command to run after: `npm run pack-art`.

**Folder** is the folder under `art-live`. `creatures` for an enemy. The others the game
uses are `bosses`, `items`, `hero`, `steeds`, `gates` and `stairs`.

**Name** is the creature's key. Lowercase letters, digits, `-` and `_`, starting with a
letter or a digit. Anything else is dropped, and the bar says what the name will actually
be before you export.

Export writes `name-0.png`, `name-1.png` and so on into your downloads folder. Move them
into `art-live/<folder>/` and run `npm run pack-art` from the game's repo.

## Saving over the files you opened

In Chrome, Edge and the Mac app, a file opened through **Open PNGs** or dropped onto the
window comes with permission to write it back. The **Save over** button sits next to
Export: press it (or `Cmd + S` / `Ctrl + S`) and your edits are written straight into the
originals, wherever they live — open them from your game's art folder and there is no
moving files about at all.

The button is greyed out until the sprite in front of you actually came from files this
session — hover it and it says exactly what to do to turn it on. In Firefox and Safari it
never appears, because those browsers do not let a page write files.

The destination is yours to change before saving: click the path in the top bar and a
real folder picker opens, the path then shows the folder you chose, and Save writes every frame
of the sprite there — including a sprite that never came from files at all. Pick your
game's art folder once and a brand new creature saves straight into it.

**The editor remembers where the work is.** Open files or pick a folder, and from then on
every picker starts there and a brand new sprite saves there too, so you set the folder
once rather than every time. The Mac app keeps that place between launches. A browser
cannot hold onto a folder across visits, so after a reload the path bar says which folder
it was and asks you to open it again rather than pretending it is still set.

Plain words about how it behaves:

- The browser asks **once per file** the first time, with its own "save changes" prompt.
  If it only lets some through on the first press, the top bar says so: press Save over
  again for the rest.
- It obeys the same checks as Export. A sprite the packer would refuse arms the button to
  **Save anyway?** for a second press, the same way Close asks twice.
- A frame added since opening has no file yet, so that one goes to downloads and the top
  bar tells you to put it next to the others.
- Renaming the sprite makes the names stop matching the files, so the button greys out
  and Export takes over. Same if the sprite was only brought back from browser storage:
  the browser cannot keep file permissions across visits, so open the files again to get
  the button back.

## Generating with PixelLab

**Generate…** in the top bar asks [PixelLab](https://www.pixellab.ai) to draw for you:
describe a creature, pick a size and how many, and a handful of candidates comes back.
Click one and it opens as a sprite, where the checks panel judges it like anything drawn
by hand — generated art usually needs its soft pixels snapped and its palette thinned,
and the editor already knows how to say so.

You bring your own PixelLab API key. It is kept in your browser and sent only to
api.pixellab.ai, when you press Generate; each image spends PixelLab credits and the
status bar says roughly what a batch cost. In the Mac app the call travels natively.

**Every generation is kept.** The history at the bottom of the dialog holds every image
that ever came back, newest first, each one a click away from becoming a sprite again —
a prompt you liked last week is still there. One button writes the whole history into a
folder of PNG files, named by date and prompt, if you want it on disk or in a repo.

## Opening art

- **Open PNGs** or drop files anywhere on the window. Several at once is fine.
- Files named `bat-0.png` and `bat-1.png` open as **one sprite with two frames**. That is
  the same naming the game's packer reads.
- A file that will not open no longer loses the rest of the drop. The ones that worked open
  and the top bar names the ones that did not.
- Frames have to start at 0 with no gaps, so a set numbered 2 and 4 opens renumbered to 0
  and 1, and the top bar says so.
- Anything else opens as its own sprite. To pull a loose file in as another frame of the
  sprite you are working on, use **Add from file** in the frames row.
- **New sprite** starts a blank square at the size in the box next to it. 16 is the usual
  size for a creature.

Open sprites are listed down the left. Click one to work on it, and drag one up or down to
reorder the list; a green edge says where it will land, and the sprite you were working on
stays the one you are working on. A red dot beside one means the packer would refuse it as
it is.

## The rules the game holds you to

The Checks tab is live, and it splits the same way the packer does. Every check is a
rule with a name, and the rules are yours: **Edit rules** lists them, each with a switch
and a ×, and a box to write a rule of your own. A rule you write is listed in the checks
as a reminder — the editor cannot judge free text — until someone wires it to a check
in `index.html`. **Back to Eldermyr's rules** puts everything back.

Above the list, one master checkbox — **Hold me to this game's rules while I draw** —
governs the three rules that change what leaves in a file: solid pixels, the colour
ceiling and squareness. Untick it and the editor stops refusing soft pixels, extra
colours and non-square pictures — what you paint, part see-through pixels included, is
exactly what exports. For Eldermyr art leave it on, because the packer itself still
refuses those files.

**Red is refused.** The packer writes nothing and exits with an error:

- **A part see-through pixel.** Every pixel is fully solid or fully clear. With the rules
  on this editor never makes one, but a file you open can carry them, and then a bar
  appears at the top with a button to snap them. Anything at half strength or more becomes
  solid, the rest becomes clear.
- **Not square.** A picture that is not square gets squashed.
- **More than 32 colours.** A count that high means the picture was resized or blurred
  rather than drawn cell by cell.
- **An empty frame**, or **frames that are not all the same size**.
- **A name or folder that cannot be a filename.**

Export refuses these too, and says which one. If you want the file anyway, an **Export
anyway** button appears next to it.

**Amber is worth a look.** The packer lets these through but they are almost always wrong:

- **Nothing on the bottom row.** The game plants the bottom row of the picture at the
  creature's feet. If nothing is painted there the creature hovers on every screen in the
  game. Empty rows belong at the top. The guide line at the bottom of the canvas turns red.
- **One frame only.** The game wants two, a standing one and a stepping one.
- **No clear pixels at all**, which means the background got painted in.
- **A later frame using colours frame 0 does not have.** All the frames of one creature
  share one palette.

The blue line down the middle is where the game centres the creature.

## Drawing

| Tool | Key | What it does |
| --- | --- | --- |
| Pencil | D | Draw with the current colour. Drag for a freehand line. |
| Eraser | E | Clear back to nothing. Right click does this with any tool. |
| Fill | F | Flood the touching pixels of the same colour. |
| Line | L | Drag a straight line. It only makes the lines pixel art wants: flat, upright, or a true one-for-one diagonal, whichever the drag is closest to. |
| Square | R | Drag a box from corner to corner. **Outline** or **Filled** sits under the tools while it is chosen; Alt flips the two for one drag, and Shift makes it a true square. |
| Spray | A | Throw pixels at random into a disc under the cursor, for stone, dirt, rust and static. Hold it still and the texture keeps building; **Size** and **Flow** sit under the tools. |
| Pick | S | Take the colour under the pointer, then go back to the pencil. |
| Select | V | Drag a box, then drag inside it to move those pixels. |

With a box in place, painting stays inside it. Arrow keys nudge the box. With no box, arrow
keys move the whole picture. Delete clears what is in the box. Esc drops the box.

`Cmd + C` (or `Ctrl + C`) copies the pixels in the box, `Cmd + X` cuts them, and `Cmd + V`
pastes — into the same sprite or a different one, since the clipboard travels between
open sprites. A paste lands centred as a floating box: drag it into place and it sets
down when the box is dropped. Pasting into a smaller sprite trims to fit and says so.

**Flip** mirrors the frame left to right. Creatures are always drawn facing right and the
game flips them itself when they walk the other way, so this is for fixing one you drew
facing the wrong way.

Every tool key, and the onion skin and grid toggles, can be rebound in **Settings** — the
button in the top bar, `Cmd + ,`, or the app menu on the Mac. Click a key, press the new
one, and it is kept in your browser. If
the new key already did another job, the two swap, so nothing is ever unreachable. One
button puts them all back.

The side columns are draggable at their inner edges if the sprite list or the panels need
more room; double clicking a divider puts it back.

Undo is `Cmd + Z` or `Ctrl + Z`, redo is `Shift + Z`. It goes back 200 steps, or fewer on a
very large sprite so the undo stack cannot eat all the memory.

The palette fills up from the colours already in the open sprite, most used first. The
colour square and the hex box next to it set what you draw with.

**Canvas**, under the palette, is what sits behind the sprite while you draw: the
checkerboard out of the box, because it makes a clear pixel unmistakable, or a flat
colour when you would rather judge a silhouette — black, white, mid grey, the old
transparency magenta, or any colour you pick. It is only a view. Clear pixels stay clear
in what you save, export and keep.

**Opacity**, under the colour, sets how hard the paint lands: at 50%, red over white
leaves pink. With the game's rules on, a painted pixel always comes out fully solid —
over empty ground the colour lands at full strength, because the game refuses part
see-through pixels. With the rules off it is true alpha blending, and the softness is
kept. Either way a stroke blends each pixel once, so a slow drag does not darken its
own line.

Zoom with the wheel over the canvas, with `-` and `+`, or with Fit.

## The whole picture

**Image ▾** in the Tools panel — and, in the Mac app, the buttons in the title bar and
the Image menu — works on every frame at once, as one undo step:

- **Canvas size…** grows, shrinks or scales the picture, three ways. *By edge* adds pixels
  to a side with a positive number and takes them away with a negative one. *To a size*
  takes a width and height, with an anchor for which part of the picture stays put (feet
  on the ground, centred, out of the box). *Scale* takes a factor and applies it to the
  picture and the canvas, the canvas only, or the picture only inside the same canvas —
  nearest neighbour, so pixels stay crisp. The dialog says what the numbers add up to
  before you press Apply.
- **Crop to selection** cuts the canvas down to the box you dragged with the Select tool.
- **Trim to the pixels** cuts it down to what is painted, so the bottom row is the feet.
- **Flip** left–right or top–bottom, and **rotate** a quarter turn clockwise.

## Frames and the walk cycle

The frames row is under the canvas. Add, copy and delete are there, and the frames
rearrange by dragging: pick one up, and the blue edge on its neighbour says which side
it will land on. The numbers follow the new order. Click a frame and the keys are its:
`Cmd + C` copies it, `Cmd + V` pastes the copy after it, `Cmd + X` cuts it, and Backspace
or Delete removes it.

Right click a frame for **Duplicate frame**, copy, paste after, **Duplicate sprite** and
delete. Right click a sprite in the list to duplicate it or close it; a duplicate is named
`<name>-copy`, saves beside its original, and needs a new name before it goes anywhere. **Onion skin** shows
the frame before the current one faintly underneath, so a leg can be moved a known
distance. **Play** runs the frames in the game size view at the speed on the slider, which
is the only honest way to tell whether a walk cycle works.

## Preview

Top right, and it is the panel that matters. A sprite at 16 pixels tells you nothing on its
own, so this draws it the size a player actually sees, on the game's own ground, with the
game's own shadow under it, next to three creatures already in the game: a grave rat, the
hero, and a wild ogre.

- **Window** is how many screen pixels a drawn pixel gets: 1× to 8×. The game runs at
  2, 3 and 4; the bigger steps are for games that scale everything up. The choice is kept.
- **Edit references** swaps the creatures yours stands beside. The game's own three are
  the defaults; add any open sprite by name, or pick a PNG, and drop any you do not want.
  Your list is kept in the browser.
- The faint squares are map tiles. A 16 pixel creature is about two thirds of a tile.
- **Ground** switches between the realm's grass, dirt path, stone, sand, snow, burnt ground
  and dungeon floor, in the colours the game paints them.

Drawing on a bigger grid does not make a creature bigger in the game, only finer. A new
creature is drawn to fill its box, and the box is the same either way.

### As tiles

**Tiles** in the Preview tab repeats the sprite across the panel instead of standing it
beside creatures, which is what ground art needs. A sprite in the `terrain` folder opens
that way; the switch is yours after that.

- **Repeat every N px** is the pitch, and it is not always the picture's width. Eldermyr
  draws ground at 32 px from art that is 33 px, so every tile laps one pixel over the
  next; the default follows that, and the note under the switch says what the number
  means. Get this wrong and a tile looks seamless here and shows a seam in the game.
- **Frames are variants, not animation.** The game picks a tile's frame from its world
  hash, so grass's four frames are four different grasses scattered about. The preview
  scatters them the same way rather than blinking them in unison.
- **Offset** shifts the field half a tile, so the joins land in the middle of the panel
  where you can actually see them, the way an offset filter does elsewhere.
- **Tile edges meet where they lap** is a rule in the Checks panel, off until you ask for
  it. Where the art laps, the covered edge has to match the one covering it, or painted
  pixels quietly vanish under the neighbour; the check counts the rows and columns that
  differ.

### Checking a tilesheet lines up

When the sprite is ruled as a sheet — one picture holding many tiles in a grid — the
Preview panel stops thinking about the whole picture and starts thinking about one cell.
A row of the sheet is one terrain type and its columns are that type's variants, and
everything below follows from that.

- **The tile is the cell you are on.** A small map of the whole sheet sits under the
  switches with the current cell ringed; click a cell to work on it, and the canvas
  follows. **Repeat every N px** is now the cell's pitch, not the picture's, and it
  defaults to the cell's width — 16 px art at a 16 px pitch, edge to edge. The one pixel
  lap is the older 33-px convention; a sheet only has one if you ask for it.
- **Row variants** scatters every painted cell of the current row across the field, using
  the same world hash the game uses to pick a tile's variant. The note says how many it
  found and which row they came from. Turn it off to repeat the one cell alone.
- **Board** is a third preview mode, and it is where tiles that are *supposed* to differ
  get checked: grass beside a grass-to-sand edge, an inside corner against an outside one.
  Drag on the little map to lay the current cell down, right-click or hold Alt to lift it,
  Shift-click to pick up whatever is under the cursor and work on that instead. **Fill
  from row** scatters the row over the whole board, **Clear** empties it, and the size
  chip cycles 6 × 4, 10 × 6 and 16 × 9. The board is drawn at the pitch, so laps overlap
  exactly as they will in play, and it is kept with the sprite.
- **Seams** marks every join where two tiles do not agree, in both Tiles and Board.
  **Red** means the two edges do not line up: nothing is overlaid there, so the only
  question is whether they read as one picture, and more than a third of the pixel pairs
  jumping a long way in colour says they do not. **Amber** means a lap is covering pixels
  that differ, which is the exact fault — paint you can see in the editor that the
  neighbour quietly eats. The note counts them: *3 of 40 joins look rough*, or *All joins
  line up*.
- **Sheet edges line up** is a rule in the Checks panel, on by default, and it only speaks
  for a sprite ruled as a sheet. Every painted cell of the current row has to be able to
  sit beside something in that row, so it names the ones that cannot — *Cell 2,0's right
  edge lines up with nothing in its row* — for the right edge and the bottom edge in turn.
  A tile that meets itself cleanly passes on its own. When the grid has a gutter or a
  margin, it also looks for ink outside the cells, because splitting the sheet into one
  file a tile would drop it.

## Tilesheets

Terrain is easier to draw as one picture. A tilesheet is a single PNG holding many tiles
in a grid, so a whole set of grass can be drawn, compared and adjusted side by side
instead of a file at a time.

The game never reads a sheet. It reads one PNG a tile, `<key>-<n>.png`, where the numbered
frames of a tile are its *variants* and not its animation. So a sheet is a way of working,
not a way of shipping: you rule a grid on it, draw in it, and split it back into sprites
before you save.

**Tilesheet…** in the **+** menu above the sprite list starts a sheet from nothing: a cell
size, how many columns and rows, and a name. It makes an empty `terrain` sprite already
ruled — eight by eight cells of 16 px is a 128 by 128 picture — and the line under the
fields says what the numbers come to before you press Make. Cells are square here; the
grid dialog changes them afterwards.

**Tilesheet grid…** in the Tools panel — and, in the Mac app, the Image menu — rules the
grid. It takes a cell width and height, a margin before the first cell, and a gap between
cells, and the line under the fields says what those numbers add up to: how many columns
and rows fit, and how many pixels are left unused at the right and the bottom. **Grow to
fit** takes a number of columns and rows and resizes the canvas to hold exactly that many,
adding clear pixels at the right and the bottom so nothing already drawn moves out from
under its cell. **Clear grid** takes the rule off again and leaves one plain picture.

A PNG opened into the `terrain` folder is ruled on the way in, as is any picture whose
size reads as a grid of 16s with at least two cells each way. Small pictures are left
alone unless they are terrain, because a 32 pixel sprite with four frames is not a sheet.
The status line says what it decided, and the dialog undoes it in one click.

### Working a cell at a time

The cell rule is drawn on the canvas at every zoom, and is not tied to the **Grid** switch:
on a sheet the cell edges are what you are drawing to. Gutters and margins sit back a
shade, because they belong to no tile, and the cell you last worked in wears a ring. The
readout in the corner names the cell as well as the pixel.

- **In cell**, beside the grid button, keeps every stroke inside the cell it starts in,
  whichever tool is in hand — a pencil that runs into the next tile ruins two tiles at
  once, and a bucket that escapes ruins the sheet. It is on until you turn it off, and the
  choice is kept. A stroke begun in a gutter is not penned anywhere.
- **Double click a cell** with the Select tool and the box is exactly that cell. Holding
  **Alt** while dragging a box snaps it out to whole cells.
- `[` and `]` step to the cell before or after, wrapping onto the next row; with **Shift**
  they select it as they go.
- **Right click a cell** for select, copy, paste into, clear, and **Duplicate cell to the
  right**, which is the quickest road to a variant: copy a finished tile into the cell
  beside it and change a few pixels. Copy uses the same clipboard a dragged box does, so
  `Cmd + V` knows about it; pasting *into* a cell lands square in it and stops at its edge
  rather than floating in the middle of the picture. On a sheet the right button belongs to
  this menu, so it does not also rub out there.

### Splitting and adding

**Split sheet into sprites…** — from the cell menu, from a right click on the sprite in the
list, or from the Image menu — cuts the sheet back into the sprites the game reads. Two
ways:

- **A sprite a row.** Each row that has anything in it becomes one sprite, and the cells
  along the row become its frames, left to right. This is the one you usually want: a row
  is one terrain type and the variants the game scatters about.
- **A sprite a cell.** Every cell with anything in it becomes its own one-frame sprite.
  For a sheet of unrelated tiles.

Empty cells are skipped, the sheet itself stays open, and the new sprites land in the list
right after it, in the `terrain` folder and saving where the sheet saves. They are named
`<sheet>-r<row>` or `<sheet>-c<n>` — rename them before you save, because the game reads
the name.

**Add to a sheet…**, from a right click on a sprite in the list or from the Image menu,
goes the other way: tiles already drawn as sprites are laid into a sheet, a row each and a
column a frame. The dialog lists the open sprites with a thumbnail apiece, and only the one
you right-clicked is ticked to begin with — tick as many as you like. The first one ticked
settles the cell size, and anything of another size greys out, because a sheet holds one
size of tile. **Into** offers a new sheet, or any open sheet ruled in that size, and the
line beneath says what you are about to get: how many rows, how many frames the widest
sprite has, and what the sheet grows to.

Rows land below whatever is already in the sheet, and the canvas grows down and to the
right with clear pixels, so nothing already drawn moves out from under its cell; the
columns grow too if a sprite has more frames than the sheet is wide. The sprites themselves
stay open and untouched. It round-trips — split what it made and you get them back, pixel
for pixel.

## Notes

- Tested in Chrome. Any current browser should work.
- Large images are fine. The canvas only ever spans the visible window — you scroll
  the rest — so a 1000 by 2000 picture opens instantly and zooms 1x to 48x like any
  sprite. Pictures past 4096 a side are refused on open, in plain words. A sprite past
  about a million pixels is too big for the browser's own storage, so it is not kept
  between visits — the corner says so, and saving it to files works as ever. If a bad
  kept state ever wedges the page on open, add #forget to the URL and reload.
- The picture you export is the picture you drew, pixel for pixel. Opening a shipped sprite
  and exporting it untouched gives back an identical image. The file's bytes can differ,
  because the PNG is written again here, but not one pixel moves.
- No outline. The game used to grow a dark edge around every creature and it does not any
  more, so the silhouette you draw is the silhouette that ships. Dark pixels are for
  interior work: a seam, a joint, the line between two body parts.
- The game does add a ground shadow under every creature. Do not paint one in. The game
  size view draws the real one, so what you see there is what a player sees.
