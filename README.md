# ArtLabeler v1.0.0

**A MATLAB app for drawing polygon annotations on images.** Point, click, label — export masks and metadata for computer vision datasets.

## Features

- Draw polygon regions on images and assign class labels
- Navigate image folders with next/previous
- Undo/redo with 50-action history
- **Dynamic tag management** — add, edit, delete, or recolor class tags
- Export masks (indexed PNG), JSON metadata, and LabelMe XML
- Dark theme UI

## Requirements

- MATLAB R2021b or newer

## Quick Start

```matlab
ArtLabeler()
```

1. **Load Image** or **Load Folder**
2. Select a class from the dropdown
3. Click **Start Annotation** and draw a polygon (double-click to finish)
4. Use the right panel to view/reclassify regions
5. **Save** annotations or **Export** the entire folder

## Tag Management

Click **Manage Tags** to customize class labels:

- **Add** — create a new tag with a custom name and color
- **Edit** — rename or recolor an existing tag (regions update automatically)
- **Delete** — remove a tag
- **Reset to Defaults** — restore the original four classes

Tags persist to `tag_config.json` alongside the source files.

## Output Formats

| Format | File | Description |
|--------|------|-------------|
| Mask PNG | `*_mask.png` | Indexed label image (0 = background, 1+ = class IDs) |
| JSON | `*_meta.json` | Regions, labels, points, areas, mask filenames |
| LabelMe XML | `*_annotation.xml` | Polygon annotations in LabelMe format |

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| Ctrl+Z | Undo |
| Ctrl+Y | Redo |
| Delete | Delete selected region |
| S | Save current image |
| N | Next image |
| P | Previous image |
| E | Export all |

## File Structure

```
ArtLabeler.m       Main app class
classConfig.m      Tag configuration (with JSON persistence)
darkTheme.m        Dark color scheme
undoStack.m        Undo/redo stack
exportMask.m       Indexed PNG exporter
exportJson.m       JSON metadata exporter
exportLabelMe.m    LabelMe XML exporter
tag_config.json    Persisted tag definitions
```
