# ArtLabeler — Design Specification

**Date:** 2026-05-19
**Project:** ArtLabeler — 艺术图像区域标注工具
**Environment:** MATLAB R2021b+, Image Processing Toolbox

## 1. Overview

ArtLabeler is an interactive image annotation tool for art images. Users draw polygon regions, assign class labels, and export pixel-level masks with JSON/LabelMe metadata. The app is built as a programmatic MATLAB GUI (`uifigure`-based), not via App Designer `.mlapp`.

**Core workflow:** Load image → draw polygons → assign labels → export mask + metadata.

## 2. File Structure

```
ArtLabeler.m          Main app class (~800 lines)
exportMask.m          Build indexed PNG from regions (~40 lines)
exportJson.m          Write JSON metadata (~50 lines)
exportLabelMe.m       Write LabelMe XML (~60 lines)
darkTheme.m           Dark color scheme (~30 lines)
undoStack.m           Undo/redo stack utility (~50 lines)
```

### Export helper signatures

```matlab
function exportMask(regions, imageSize, filepath)
    % regions: cell array of region structs
    % imageSize: [height, width] of source image
    % filepath: full path for output PNG

function exportJson(filename, imageSize, regions, filepath)
    % filename: source image filename (e.g. '001.jpg')
    % imageSize: [height, width]
    % regions: cell array of region structs
    % filepath: full path for output JSON

function exportLabelMe(filename, imageSize, regions, filepath)
    % filename: source image filename
    % imageSize: [height, width]
    % regions: cell array of region structs
    % filepath: full path for output XML
```

## 3. Architecture — ArtLabeler.m

Inherits from `matlab.apps.AppBase`. Single classdef file containing UI creation, callbacks, and orchestration.

### Properties (State)

| Property | Type | Description |
|----------|------|-------------|
| `regions` | cell array of structs | Each entry is a region struct with fields `points`, `label`, `mask`, `roi` |
| `imageList` | cell array | Full paths to images in current folder |
| `currentIdx` | double | Index into `imageList` |
| `currentImg` | matrix | Currently displayed image data |
| `currentClass` | string | Selected class from dropdown (left panel). Default: 'person'. |
| `undoStack` | struct | Stack struct from `undoStack('create', 50)` — stores snapshot history |
| `redoStack` | struct | Same struct type, for redo snapshots |
| `isDrawing` | logical | Polygon drawing in progress |
| `dirty` | logical | Unsaved region changes exist since last save |
| `selectedRegion` | double | Index of selected region (0 = none) |
| `saveDebounceTimer` | timer | Debounce timer for vertex-drag auto-save (created on first use) |

### `dirty` flag lifecycle

- **Set true** on: polygon completed, region deleted, vertex drag completed
- **Set false** on: manual Save clicked, auto-save completed successfully
- **Not set** during intermediate vertex drag events (only on drag-end)

### Methods by Concern

| Concern | Methods |
|---------|---------|
| Startup | `ArtLabeler()` constructor, `createComponents()` |
| Image I/O | `loadImage()`, `loadFolder()`, `nextImage()`, `prevImage()` |
| Annotation | `startAnnotation()`, `onPolygonComplete()` |
| Display | `updateOverlay()`, `updateInfoPanel()`, `updateMaskPreview()` |
| Edit | `deleteRegion()`, `undoAction()`, `redoAction()`, `pushUndo()` |
| Export | `saveCurrent()`, `exportAll()` — delegates to helpers |
| Lifecycle | `onClose()`, `resetSession()`, `clearRegions()` |
| Input | `onKeyPress()` — keyboard shortcuts |

## 4. Data Model

### Region struct

```matlab
region = struct(
    'points', [],      % Nx2 double — vertex coordinates
    'label',  '',      % string — 'person'|'building'|'sky'|'plant'
    'mask',   [],      % HxW logical — per-region binary mask
    'roi',    []       % images.roi.Polygon handle
);
```

### Class mapping

| Class | Index (pixel value) | Overlay RGB |
|-------|---------------------|-------------|
| background | 0 | — (transparent) |
| person | 1 | Red `[1 0 0]` |
| building | 2 | Blue `[0 0 1]` |
| sky | 3 | Light blue `[0.5 0.8 1]` |
| plant | 4 | Green `[0 0.6 0]` |

### Overlapping regions

When two regions overlap, the later region (higher index in `regions`) wins — its class index overwrites earlier values in the combined mask. This matches creation order: newer polygons paint over older ones.

### Undo/redo stack (`undoStack.m`)

Single public dispatch function with action string (MATLAB convention for multi-operation utility files):

```matlab
function varargout = undoStack(action, varargin)
    % undoStack('create', maxDepth) → stack struct
    % undoStack('push',   stack, data) → stack with snapshot appended
    % undoStack('pop',    stack) → [stack, data_or_empty]
    % undoStack('clear',  stack) → empty stack
    % undoStack('isEmpty', stack) → logical

    % Internal: stack is a struct with fields:
    %   .entries   cell array of snapshots (deep copies)
    %   .depth     maximum depth (e.g. 50)
    %   .top       current number of entries
```

Usage in ArtLabeler.m:
```matlab
app.undoStack = undoStack('create', 50);
app.redoStack = undoStack('create', 50);
app.undoStack = undoStack('push', app.undoStack, app.regions);
[app.undoStack, snapshot] = undoStack('pop', app.undoStack);
```

Each snapshot is a deep copy of `regions`. `undoStack('push', ...)` on the undo stack also clears the redo stack by calling `undoStack('clear', app.redoStack)`. Max depth: 50 — oldest entry is dropped when full.

## 5. UI Layout

Three-panel `uigridlayout(1,3)` with ratios 200:1x:220. Dark theme via `darkTheme.m`.

### Left Panel (200px)

Vertical `uigridlayout(N,1)`:
- Class dropdown (annotation class: person/building/sky/plant)
- Buttons: Load Image, Load Folder
- Separator
- Start Annotation, Delete Region, Undo, Redo
- Separator
- Previous Image, Next Image
- Separator
- Save, Export

### Center Panel

Single `uiaxes` filling the panel. Image displayed with `imshow`. Overlay rendered as described below.

### Right Panel (220px)

- Region list (`uilistbox`): each item shows "label — area%" (e.g. "person — 24.6%"). Click selects a region — shows its polygon, enables vertex dragging, sets `selectedRegion`. Clicking the already-selected item deselects — hides polygon via `roi.Visible='off'`, disables dragging, clears `selectedRegion`. Clicking a different item switches selection (hide old, show new).
- Reclassify dropdown: changes the selected region's label. Disabled when no region is selected.
- Region count label
- Dynamic area stats list (label + pixel count + percentage per region, updated on every region change)
- Small mask preview `uiaxes` (~180x180px) showing the combined mask. Use `axis equal` to preserve aspect ratio.

### Status Bar

`uilabel` spanning bottom of figure. Formats:
- No image loaded: `No image loaded`
- Image loaded: `002.jpg | 3/20 | 3 regions | Saved` — or `... | Unsaved` when dirty
- Single image (no folder): `002.jpg | 3 regions | Saved` (omit index/total)

### Overlay rendering

A single combined RGB overlay image is built and displayed on top of the base image:

1. Create a zero-filled HxWx3 double array
2. For each region in `regions` (in order): set pixels where `region.mask` is true to the region's class RGB color
3. Display with: `hold on; h = imshow(overlayRGB, 'Parent', app.UIAxes); set(h, 'AlphaData', 0.4)`
4. On the 0.4-alpha overlay, class colors blend semi-transparently over the base image

Redrawn from scratch on every `updateOverlay()` call (region add/delete/edit).

### Dark Theme

- Container backgrounds: `[0.15 0.15 0.15]`
- Button backgrounds: `[0.2 0.2 0.2]`
- Text: white (`[1 1 1]`)
- Axes: dark background (`[0.15 0.15 0.15]`)

### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `Ctrl+Z` | Undo |
| `Ctrl+Y` | Redo |
| `Delete` | Delete selected region |
| `S` | Save current image |
| `N` | Next image |
| `P` | Previous image |
| `E` | Export dialog |

Mapped via `uifigure.KeyPressFcn`.

## 6. Annotation Workflow

1. User selects annotation class from **left panel** dropdown (default: 'person', always set — never empty)
2. Clicks **Start Annotation** → guard checks:
   - If no image loaded, status "Load an image first."
   - If `isDrawing` is true, status "Already drawing — double-click to finish current polygon."
   - If a region is selected, deselect it first (hide polygon, disable interactivity, clear `selectedRegion`) to avoid two active ROIs.
   - Class is always valid because the dropdown defaults to 'person' and has no empty option.
3. `drawpolygon()` invoked on UIAxes; user clicks vertices on the image, double-click to finish
4. `onPolygonComplete` callback fires:
   - Validate polygon has ≥3 vertices and non-zero area; if degenerate, discard and show status message
   - `createMask(roi)` generates binary mask
   - Set `roi.InteractionsAllowed = 'reshape'` (enable vertex dragging)
   - `pushUndo()` snapshots current regions
   - Append new region struct to `regions`
   - `updateOverlay()` redraws all colored overlays
   - `updateInfoPanel()` refreshes region list, area stats, mask preview
   - `autoSave()` writes mask PNG + JSON next to image, clears `dirty`
5. User cancels drawing (Esc key) → `isDrawing` reset, no error

### Vertex dragging

Each region stores its `images.roi.Polygon` handle. When a region is selected in the right-panel list, its polygon becomes interactive — user can drag existing vertices.

**`ROIMoved` event handler:**
- Update `region.points = roi.Position` to keep coordinates in sync with the dragged vertices
- Regenerate mask for that region from the polygon's new position
- If new mask has zero non-zero pixels, skip update: revert `region.points` to previous value, keep previous mask, status: "Invalid polygon shape — reverted."
- `updateOverlay()` re-renders (with valid mask)
- Set `dirty` but do NOT auto-save during drag
- Restart debounce timer

**Undo note:** Individual vertex drags do NOT push to the undo stack (would flood it with intermediate states). Only the final position when the debounce timer fires is persisted via `autoSave()`. Pressing Ctrl+Z after a drag removes the entire region (restores pre-region-creation snapshot). The user can then redraw.

**Debounce timer (`app.saveDebounceTimer`):**
A `timer` object stored as an app property, created on first use in `startAnnotation`:
```matlab
app.saveDebounceTimer = timer('ExecutionMode', 'singleShot', ...
    'StartDelay', 0.5, 'TimerFcn', @(~,~) autoSave(app));
```
- ROIMoved handler: guard with `isvalid(app.saveDebounceTimer)` before using timer; recreate if invalid
- On every `ROIMoved`: `stop(app.saveDebounceTimer); start(app.saveDebounceTimer);`
- On timer fire (0.5s of inactivity): `autoSave()` runs, sets `dirty = false`

**Timer stop —** `stop()` the timer in these situations (do NOT delete — keep the handle valid for ROIMoved recreation logic):
- Before navigating to another image (`nextImage`/`prevImage`/`loadImage`/`loadFolder`)
- Before starting a new polygon (`startAnnotation`)
- Before undo/redo
- Before deleting a region
- In `clearRegions()`

**Timer delete —** only in `onClose()` (full cleanup). In all other stop scenarios, the save that the timer would have triggered is replaced by explicit save/navigation logic.

### Region reclassification

Right-click a region in the list (or select it and use a class dropdown in the right panel) → choose new class → `pushUndo()` → update `region.label` → `updateOverlay()` + `updateInfoPanel()` → `autoSave()`. This lets users fix mislabeled regions without deleting and redrawing.

### Region deletion

Select region in right-panel list → click Delete Region (or press Delete key) → `pushUndo()` → remove from `regions` → `updateOverlay()` + `updateInfoPanel()` → `autoSave()`

### Image navigation auto-save

When navigating to another image (Next/Previous/Load Image/Load Folder), before unloading the current image:
1. Cancel any pending `saveDebounceTimer` (stop + delete)
2. If `dirty` is true, run `autoSave()` for the current image
3. Then load the new image and reset session state

### ROI handle cleanup

Two levels of reset:

**`clearRegions()`** — called when navigating to a new image within the same folder (`nextImage`/`prevImage`/`loadImage`):
- Stop any pending `saveDebounceTimer` (`stop(app.saveDebounceTimer)`)
- Delete all `images.roi.Polygon` handles (`delete(region.roi)`)
- Clear `regions`, `undoStack`, `redoStack`, `selectedRegion`, `dirty`

**`resetSession()`** — called when loading from a new source (`loadFolder`, new `loadImage` when no folder is open):
- Calls `clearRegions()`
- Clears `imageList`, resets `currentIdx` to 0

`imageList` survives Next/Previous navigation; it is only replaced by `loadFolder`.

## 7. Export

Three save mechanisms with distinct behaviors:

### Auto-save (automatic, per region change)

Fires after every add/delete/vertex-edit-complete. Overwrites existing output files silently next to the source image:
- `{name}_mask.png` — single-channel uint8 grayscale PNG where pixel values encode class: 0=bg, 1=person, 2=building, 3=sky, 4=plant. (This is the standard pixel-level label map format; no colormap needed.)
- `{name}_meta.json` — full metadata

Sets `dirty = false`. Catches disk errors (permission denied, disk full) and shows status bar warning without crashing.

**Note:** Auto-save silently overwrites `_mask.png` and `_meta.json` on every region change. Any manual edits to these files made outside ArtLabeler will be lost on the next annotation action. This is by design — the app is the source of truth during an annotation session.

### Save button (manual, current image)

Same output as auto-save. Exists so the user can explicitly save without making a region change. Also sets `dirty = false`. Status bar confirms: "Saved 001_mask.png, 001_meta.json". If `regions` is empty, writes an all-zeros mask and an empty `regions: []` JSON (clears any previous annotations for this image).

### Export button (manual, batch)

Opens dialog with format checkboxes: Mask, JSON, LabelMe. If no checkboxes selected on confirm, `uialert`: "Select at least one export format." On confirm with ≥1 format selected, scans the current image's folder for all `*_meta.json` files (not in-memory state). For each found JSON, reads it and regenerates the requested export formats. If output files exist, shows `uiconfirm` overwrite warning. If no `*_meta.json` files exist, shows `uialert`: "No annotations found to export." Does NOT modify `dirty` flag. Area values are recomputed from regenerated masks, not taken from stored JSON.

### JSON format

```json
{
  "image": "001.jpg",
  "width": 1920,
  "height": 1080,
  "regions": [
    {
      "label": "person",
      "mask": "001_mask.png",
      "area": 15432,
      "areaPercent": 0.74,
      "points": [[120,80],[140,90],[160,150]]
    }
  ]
}
```

### LabelMe XML

Standard LabelMe annotation format:
```xml
<annotation>
  <filename>001.jpg</filename>
  <folder>images</folder>
  <source><annotation>ArtLabeler</annotation></source>
  <object>
    <name>person</name>
    <deleted>0</deleted>
    <verified>0</verified>
    <polygon>
      <pt><x>120</x><y>80</y></pt>
      <pt><x>140</x><y>90</y></pt>
      <pt><x>160</x><y>150</y></pt>
    </polygon>
  </object>
</annotation>
```

### Loading previous annotations

When loading any image (single Load Image, Load Folder, or Next/Previous navigation) that has an existing `{name}_meta.json` in the same folder, parse it and reconstruct `regions` and overlays:

1. Read and parse `{name}_meta.json`
2. For each region in the JSON:
   - Create a new `images.roi.Polygon` from the saved `points` array: `roi = drawpolygon(app.UIAxes, 'Position', points)`
   - Set `roi.InteractionsAllowed = 'reshape'` (enables vertex dragging)
   - Set `roi.Visible = 'off'` until selected
   - Generate mask: `mask = createMask(roi)`
   - Append region struct to `app.regions`
3. Call `updateOverlay()` to render combined overlay

This enables resuming annotation sessions with full vertex-dragging support. If JSON parsing fails, treat as fresh image with warning in status bar.

## 8. Combined mask generation (`exportMask.m`)

```matlab
function exportMask(regions, imageSize, filepath)
    combined = zeros(imageSize, 'uint8');
    classIds = containers.Map(...
        {'person', 'building', 'sky', 'plant'}, ...
        {1, 2, 3, 4});
    for i = 1:numel(regions)
        id = classIds(regions{i}.label);
        combined(regions{i}.mask) = id;  % later regions overwrite earlier
    end
    imwrite(combined, filepath);
end
```

## 9. Build Order

| # | Step | Files | Includes |
|---|------|-------|----------|
| 1 | App skeleton — figure, grid, panels, close handler. No-image state disables buttons. | `ArtLabeler.m` | Button enable/disable gating |
| 2 | Image loading (single + folder) with display. Filter to `*.jpg,*.png,*.bmp` only. | `ArtLabeler.m` | try/catch imread, corrupt image skip |
| 3 | Polygon drawing + mask generation. Validate ≥3 vertices and non-zero area. | `ArtLabeler.m` | Cancel/Esc handling, degenerate polygon rejection |
| 4 | Overlay visualization + right panel info. Combined RGB overlay with AlphaData. | `ArtLabeler.m` | Overlap ordering, region list click-to-select |
| 5 | Undo/redo stack. Deep copy of regions. | `undoStack.m` + `ArtLabeler.m` | Empty-stack no-op, redo clear on new action |
| 6 | Export functions (mask, JSON, LabelMe) + auto-save. | `exportMask.m`, `exportJson.m`, `exportLabelMe.m` | Disk error catch, dirty flag management |
| 7 | Navigation + auto-save on switch. Bounds handling (disable Prev on first, Next on last). | `ArtLabeler.m` | Load previous annotations, resetSession on folder change |
| 8 | Dark theme | `darkTheme.m` | Apply on startup |
| 9 | Keyboard shortcuts + vertex dragging. Debounced save on drag-end. | `ArtLabeler.m` | ROIMoved event, 0.5s debounce timer |
| 10 | Save button, Export button, overwrite confirm dialog, close-without-save confirm | `ArtLabeler.m` | dirty flag check on close |

## 10. Error Handling

- **No image loaded:** Annotation/Edit/Export buttons disabled. Status: "Load an image to begin."
- **Folder load filter:** Only `*.jpg`, `*.png`, `*.bmp` files accepted. Non-image files silently skipped.
- **Empty folder / no matching images:** `uialert` warning: "No supported images found in this folder." `imageList` stays empty, navigation buttons remain disabled, status shows "No image loaded."
- **Corrupt image:** `try/catch` around `imread`, `uialert` with filename, skip to next image.
- **Cancelled polygon (Esc):** `drawpolygon` returns empty; reset `isDrawing`, no error.
- **Degenerate polygon (creation):** <3 vertices or zero pixel area after `createMask`; discard, status: "Invalid polygon — too few vertices or zero area."
- **Degenerate polygon (vertex drag):** If dragging vertices produces zero-area mask, skip update, keep previous mask, status: "Invalid polygon shape — reverted."
- **Navigation bounds:** Previous button disabled on first image, Next button disabled on last image.
- **Undo at empty stack:** No-op. Status: "Nothing to undo."
- **Redo at empty stack:** No-op. Status: "Nothing to redo."
- **No region selected:** Delete button no-ops. Status: "No region selected."
- **Disk error on save:** `try/catch` around `imwrite` and `fopen`. Status bar shows error, `dirty` remains true.
- **Close without save:** If `dirty`, show `uiconfirm` dialog: "Unsaved changes. Save before closing?" with Yes/No/Cancel. Yes → `autoSave()` then close. No → close without saving. Cancel → stay open.
- **MATLAB < R2021b:** `verLessThan('matlab', '9.11')` check at startup. If older, `exportJson.m` uses `sprintf`/`fprintf` to build JSON strings manually (escaped strings, formatted numbers). `uialert` warning on startup. Mask PNG and LabelMe XML use standard `imwrite`/`fprintf` which work on any version.
- **Corrupt previous annotation JSON:** On load, if `meta.json` parse fails, warn in status bar, treat as fresh image.
