# Eldermyr sprite editor

A pixel editor for Realms of Eldermyr creature sprites. One HTML file. Open it and draw.

    open index.html

No build, no server, no install, no internet. Double click the file, or drag it onto a
browser window. Everything runs locally and nothing is uploaded anywhere.

## Why this exists

The game used to store creature art as rows of characters plus a palette, painted one
rectangle at a time while the game ran. It does not any more. It loads real PNG files, so
what you draw here is exactly what ships. That means a plain image editor is the right
tool, and this one has the game's rules built into it.

## Opening art

- **Open PNGs** or drop files anywhere on the window. Several at once is fine.
- Files named `bat-0.png` and `bat-1.png` open as **one sprite with two frames**. That is
  the same naming the game's packer reads.
- Anything else opens as its own sprite. To pull a loose file in as another frame of the
  sprite you are working on, use **Add from file** in the frames row.
- **New sprite** starts a blank square at the size in the box next to it. 16 is the usual
  size for a creature.

Open sprites are listed down the left. Click one to work on it. Nothing is saved between
visits, so export before you close the tab.

## The rules the game holds you to

The checks panel on the right is live. Green is fine, amber is worth a look, red will be
refused when the art is packed for the game.

- **Solid or clear, never in between.** The game cannot paint a half see-through pixel, so
  this editor never makes one. If a file you open has soft edges, a bar appears at the top
  saying how many, with a button to snap them. Anything at half strength or more becomes
  solid, the rest becomes clear.
- **The bottom row is the ground.** The game plants the bottom row of the picture at the
  creature's feet. If nothing is painted there the creature hovers, so the guide line at
  the bottom of the canvas turns red and the checks say so. Empty rows belong at the top.
- **The centre column** is where the game centres the creature. It is the blue line.
- **Colour count.** The count is at the top of the checks. The brief asks for 8 to 12 per
  creature. More than 32 is refused, because a number that high means the picture was
  resized or blurred rather than drawn.
- **Square.** A picture that is not square gets squashed.
- **Two frames.** A standing one and a stepping one. The step frame still has to read as a
  creature standing still, because the walk cycle stops wherever the creature stops.

## Drawing

| Tool | Key | What it does |
| --- | --- | --- |
| Pencil | B | Draw with the current colour. Drag for a line. |
| Eraser | E | Clear back to nothing. Right click does this with any tool. |
| Fill | F | Flood the touching pixels of the same colour. |
| Pick | I | Take the colour under the pointer, then go back to the pencil. |
| Select | V | Drag a box, then drag inside it to move those pixels. |

With a box in place, painting stays inside it. Arrow keys nudge the box, or the whole
picture when there is no box. Delete clears what is in the box. Esc drops the box.

Undo is `Cmd + Z` or `Ctrl + Z`, redo is `Shift + Z`. It goes back 200 steps.

The palette fills up from the colours already in the open sprite, most used first. The
colour square next to it adds a new one.

## Frames and the walk cycle

The frames row is under the canvas. Add, copy and delete are there. **Onion skin** shows
the frame before the current one faintly underneath, so a leg can be moved a known
distance. **Play** runs the frames in the preview at the speed on the slider, which is the
only honest way to tell whether a walk cycle works.

## The preview

Top right, on grass, at one to four times size. That is roughly how small these are
actually looked at, and it is where most problems become obvious. The swatches under it
change the ground to dark grass, dirt, stone or night.

## Exporting

**Export frames** saves every frame as `name-0.png`, `name-1.png` and so on, using the name
in the top bar. That is the name the game's packer expects. **This frame** saves only the
one you are looking at. Files go to your downloads folder. Move them into the game's
`art/creatures/` folder and run the packer.

Alpha is snapped on the way out no matter what, so a file exported from here is always one
the game will accept.

## Notes

- Tested in Chrome. Any current browser should work.
- The picture you export is the picture you drew, pixel for pixel. Opening a shipped sprite
  and exporting it untouched gives back a byte for byte identical file.
- Do not draw an outline around the creature. The game draws one itself.
