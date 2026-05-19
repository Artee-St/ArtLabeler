# ArtLabeler Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a MATLAB programmatic GUI tool for polygon-based art image annotation with multi-class mask export.

**Architecture:** Single main app class (`ArtLabeler.m`) inheriting from `matlab.apps.AppBase`, with five standalone utility files for export, theming, and undo/redo. Three-panel uifigure UI: left toolbar, center UIAxes with overlay, right info panel.

**Tech Stack:** MATLAB R2021b+, Image Processing Toolbox, `uifigure`/`uigridlayout` programmatic GUI, `drawpolygon`, `createMask`, `jsonencode`.

**Spec:** `docs/superpowers/specs/2026-05-19-artlabeler-design.md`

**Files to create:**
- `ArtLabeler.m` — main app classdef (~800 lines)
- `exportMask.m` — indexed PNG writer
- `exportJson.m` — JSON metadata writer
- `exportLabelMe.m` — LabelMe XML writer
- `darkTheme.m` — dark color scheme applier
- `undoStack.m` — undo/redo stack dispatch function

---

## Chunk 1: Foundation — undoStack, darkTheme, App Skeleton

### Task 1.1: Create undoStack.m

**Files:** Create `undoStack.m`

- [ ] **Step 1: Write undoStack.m**

```matlab
function varargout = undoStack(action, varargin)
    % undoStack('create', maxDepth) → stack struct
    % undoStack('push',   stack, data) → stack
    % undoStack('pop',    stack) → [stack, data]
    % undoStack('clear',  stack) → empty stack
    % undoStack('isEmpty', stack) → logical

    switch action
        case 'create'
            maxDepth = varargin{1};
            stack = struct('entries', {{}}, 'depth', maxDepth, 'top', 0);
            varargout = {stack};

        case 'push'
            stack = varargin{1};
            data = varargin{2};
            stack.top = stack.top + 1;
            if stack.top > stack.depth
                stack.entries(1) = [];
                stack.top = stack.depth;
            end
            stack.entries{stack.top} = deepCopyRegions(data);
            varargout = {stack};

        case 'pop'
            stack = varargin{1};
            if stack.top == 0
                varargout = {stack, []};
            else
                data = stack.entries{stack.top};
                stack.entries(stack.top) = [];
                stack.top = stack.top - 1;
                varargout = {stack, data};
            end

        case 'clear'
            varargout = {undoStack('create', varargin{1}.depth)};

        case 'isEmpty'
            varargout = {varargin{1}.top == 0};
    end
end

function copy = deepCopyRegions(data)
    if isempty(data)
        copy = {};
        return;
    end
    copy = cell(size(data));
    for i = 1:numel(data)
        r = data{i};
        copy{i} = struct(...
            'points', r.points, ...
            'label', r.label, ...
            'mask', r.mask, ...
            'roi', []);  % roi handles not copied (axes-specific)
    end
end
```

- [ ] **Step 2: Verify undoStack in MATLAB**

Run in MATLAB command window:
```matlab
s = undoStack('create', 3);
tf = undoStack('isEmpty', s);  % should be true
s = undoStack('push', s, [1 2 3]);
tf = undoStack('isEmpty', s);  % should be false
[s, d] = undoStack('pop', s);  % d should be [1 2 3]
```

- [ ] **Step 3: Commit**

---

### Task 1.2: Create darkTheme.m

**Files:** Create `darkTheme.m`

- [ ] **Step 1: Write darkTheme.m**

```matlab
function darkTheme(app)
    % Apply dark color scheme to ArtLabeler UI components
    BG = [0.15 0.15 0.15];
    FG = [0.2 0.2 0.2];
    TXT = [1 1 1];

    app.UIFigure.Color = BG;
    app.LeftPanel.BackgroundColor = BG;
    app.CenterPanel.BackgroundColor = BG;
    app.RightPanel.BackgroundColor = BG;

    if isprop(app, 'StatusBar')
        app.StatusBar.BackgroundColor = [0.1 0.1 0.1];
        app.StatusBar.FontColor = TXT;
    end

    btnNames = {'LoadImageButton', 'LoadFolderButton', ...
        'StartAnnotationButton', 'DeleteRegionButton', ...
        'UndoButton', 'RedoButton', 'PrevButton', ...
        'NextButton', 'SaveButton', 'ExportButton'};
    for i = 1:numel(btnNames)
        if isprop(app, btnNames{i})
            btn = app.(btnNames{i});
            btn.BackgroundColor = FG;
            btn.FontColor = TXT;
        end
    end

    if isprop(app, 'ClassDropdown')
        app.ClassDropdown.BackgroundColor = FG;
        app.ClassDropdown.FontColor = TXT;
    end
    if isprop(app, 'ReclassifyDropdown')
        app.ReclassifyDropdown.BackgroundColor = FG;
        app.ReclassifyDropdown.FontColor = TXT;
    end
    if isprop(app, 'RegionList')
        app.RegionList.BackgroundColor = FG;
        app.RegionList.FontColor = TXT;
    end

    allLabels = findobj(app.UIFigure, 'Type', 'uilabel');
    for i = 1:numel(allLabels)
        allLabels(i).FontColor = TXT;
    end

    app.UIAxes.Color = BG;
    if isprop(app, 'MaskPreviewAxes')
        app.MaskPreviewAxes.Color = BG;
    end
end
```

- [ ] **Step 2: Test darkTheme in MATLAB**

```matlab
f = uifigure('Name', 'Test');
b = uibutton(f, 'push', 'Text', 'Test');
s.app.UIFigure = f;
s.app.LeftPanel.CenterPanel.RightPanel = [];
darkTheme(s);  % should not error on fields that don't exist
close(f);
```

- [ ] **Step 3: Commit**

---

### Task 1.3: Create ArtLabeler.m skeleton

**Files:** Create `ArtLabeler.m`

- [ ] **Step 1: Write ArtLabeler constructor and createComponents skeleton**

```matlab
classdef ArtLabeler < matlab.apps.AppBase

    properties (Access = public)
        UIFigure        matlab.ui.Figure
        LeftPanel       matlab.ui.container.Panel
        CenterPanel     matlab.ui.container.Panel
        RightPanel      matlab.ui.container.Panel
        UIAxes          matlab.ui.control.UIAxes
        MaskPreviewAxes matlab.ui.control.UIAxes

        LoadImageButton       matlab.ui.control.Button
        LoadFolderButton      matlab.ui.control.Button
        StartAnnotationButton matlab.ui.control.Button
        DeleteRegionButton    matlab.ui.control.Button
        UndoButton            matlab.ui.control.Button
        RedoButton            matlab.ui.control.Button
        PrevButton            matlab.ui.control.Button
        NextButton            matlab.ui.control.Button
        SaveButton            matlab.ui.control.Button
        ExportButton          matlab.ui.control.Button

        ClassDropdown     matlab.ui.control.DropDown
        ReclassifyDropdown matlab.ui.control.DropDown
        RegionList        matlab.ui.control.ListBox
        RegionCountLabel  matlab.ui.control.Label
        AreaStatsLabel    matlab.ui.control.Label
        StatusBar         matlab.ui.control.Label
    end

    properties (Access = public)
        regions           {}     % cell array of region structs
        imageList         {}     % full paths to images
        currentIdx        = 0
        currentImg        = []
        currentClass      = 'person'
        undoStack         struct
        redoStack         struct
        isDrawing         = false
        dirty             = false
        selectedRegion    = 0
        saveDebounceTimer = []
        imageDir          = ''   % current working directory
    end

    methods (Access = public)
        function app = ArtLabeler()
            % Check MATLAB version
            if verLessThan('matlab', '9.11')
                uialert(uifigure('Visible','off'), ...
                    'MATLAB R2021b or newer recommended for jsonencode support.', ...
                    'Version Warning');
            end
            app.createComponents();
            darkTheme(app);
            app.updateButtonStates();
            app.updateStatusBar();
        end
    end

    methods (Access = private)
        function createComponents(app)
            % Create figure
            app.UIFigure = uifigure('Name', 'ArtLabeler', ...
                'Position', [100 100 1280 720], ...
                'CloseRequestFcn', @(~,~) onClose(app));

            % Main grid: left | center | right
            mainGrid = uigridlayout(app.UIFigure, [1 3]);
            mainGrid.ColumnWidth = {200, '1x', 220};
            mainGrid.RowHeight = {'1x', 22};
            mainGrid.Padding = [4 4 4 4];
            mainGrid.ColumnSpacing = 4;

            % Left panel
            app.LeftPanel = uipanel(mainGrid);
            app.LeftPanel.Layout.Row = 1;
            app.LeftPanel.Layout.Column = 1;

            leftGrid = uigridlayout(app.LeftPanel, [14 1]);
            leftGrid.RowHeight = repmat({25}, 1, 13);
            leftGrid.RowHeight{14} = '1x';
            leftGrid.Padding = [4 4 4 4];
            leftGrid.RowSpacing = 4;

            app.ClassDropdown = uidropdown(leftGrid, ...
                'Items', {'person', 'building', 'sky', 'plant'}, ...
                'Value', 'person', ...
                'ValueChangedFcn', @(~,~) onClassChanged(app));
            app.ClassDropdown.Layout.Row = 1;

            app.LoadImageButton = uibutton(leftGrid, 'push', ...
                'Text', 'Load Image', ...
                'ButtonPushedFcn', @(~,~) loadImage(app));
            app.LoadImageButton.Layout.Row = 2;

            app.LoadFolderButton = uibutton(leftGrid, 'push', ...
                'Text', 'Load Folder', ...
                'ButtonPushedFcn', @(~,~) loadFolder(app));
            app.LoadFolderButton.Layout.Row = 3;

            % Separator row 4 (empty uilabel)
            uilabel(leftGrid, 'Text', '', 'HorizontalAlignment', 'center').Layout.Row = 4;

            app.StartAnnotationButton = uibutton(leftGrid, 'push', ...
                'Text', 'Start Annotation', ...
                'ButtonPushedFcn', @(~,~) startAnnotation(app));
            app.StartAnnotationButton.Layout.Row = 5;

            app.DeleteRegionButton = uibutton(leftGrid, 'push', ...
                'Text', 'Delete Region', ...
                'ButtonPushedFcn', @(~,~) deleteRegion(app));
            app.DeleteRegionButton.Layout.Row = 6;

            app.UndoButton = uibutton(leftGrid, 'push', ...
                'Text', 'Undo', ...
                'ButtonPushedFcn', @(~,~) undoAction(app));
            app.UndoButton.Layout.Row = 7;

            app.RedoButton = uibutton(leftGrid, 'push', ...
                'Text', 'Redo', ...
                'ButtonPushedFcn', @(~,~) redoAction(app));
            app.RedoButton.Layout.Row = 8;

            % Separator row 9
            uilabel(leftGrid, 'Text', '', 'HorizontalAlignment', 'center').Layout.Row = 9;

            app.PrevButton = uibutton(leftGrid, 'push', ...
                'Text', char(9664) + " Previous", ...
                'ButtonPushedFcn', @(~,~) prevImage(app));
            app.PrevButton.Layout.Row = 10;

            app.NextButton = uibutton(leftGrid, 'push', ...
                'Text', 'Next " + char(9654), ...
                'ButtonPushedFcn', @(~,~) nextImage(app));
            app.NextButton.Layout.Row = 11;

            % Separator row 12
            uilabel(leftGrid, 'Text', '', 'HorizontalAlignment', 'center').Layout.Row = 12;

            app.SaveButton = uibutton(leftGrid, 'push', ...
                'Text', 'Save', ...
                'ButtonPushedFcn', @(~,~) saveCurrent(app));
            app.SaveButton.Layout.Row = 13;

            app.ExportButton = uibutton(leftGrid, 'push', ...
                'Text', 'Export', ...
                'ButtonPushedFcn', @(~,~) exportAll(app));
            app.ExportButton.Layout.Row = 14;

            % Center panel — UIAxes
            app.CenterPanel = uipanel(mainGrid);
            app.CenterPanel.Layout.Row = 1;
            app.CenterPanel.Layout.Column = 2;
            app.UIAxes = uiaxes(app.CenterPanel);
            app.UIAxes.Position = [0 0 app.CenterPanel.Position(3) app.CenterPanel.Position(4)];
            app.UIAxes.XTick = [];
            app.UIAxes.YTick = [];
            app.UIAxes.Box = 'on';

            % Right panel
            app.RightPanel = uipanel(mainGrid);
            app.RightPanel.Layout.Row = 1;
            app.RightPanel.Layout.Column = 3;

            rightGrid = uigridlayout(app.RightPanel, [6 1]);
            rightGrid.RowHeight = {25, 25, 120, 25, '1x', 180};
            rightGrid.Padding = [4 4 4 4];
            rightGrid.RowSpacing = 4;

            app.ReclassifyDropdown = uidropdown(rightGrid, ...
                'Items', {'person', 'building', 'sky', 'plant'}, ...
                'Value', 'person', ...
                'ValueChangedFcn', @(~,~) reclassifyRegion(app));
            app.ReclassifyDropdown.Layout.Row = 1;

            app.RegionCountLabel = uilabel(rightGrid, ...
                'Text', 'Regions: 0', ...
                'HorizontalAlignment', 'left');
            app.RegionCountLabel.Layout.Row = 2;

            app.RegionList = uilistbox(rightGrid, ...
                'Items', {}, ...
                'ValueChangedFcn', @(~,~) onRegionSelected(app));
            app.RegionList.Layout.Row = 3;

            app.AreaStatsLabel = uilabel(rightGrid, ...
                'Text', 'Area Stats:', ...
                'HorizontalAlignment', 'left');
            app.AreaStatsLabel.Layout.Row = 4;

            % Mask preview
            app.MaskPreviewAxes = uiaxes(rightGrid);
            app.MaskPreviewAxes.Layout.Row = 6;
            app.MaskPreviewAxes.XTick = [];
            app.MaskPreviewAxes.YTick = [];
            title(app.MaskPreviewAxes, 'Mask Preview');

            % Status bar
            app.StatusBar = uilabel(mainGrid, ...
                'Text', 'No image loaded', ...
                'HorizontalAlignment', 'left');
            app.StatusBar.Layout.Row = 2;
            app.StatusBar.Layout.Column = [1 3];
        end
    end
end
```

- [ ] **Step 2: Create stub methods so the file is runnable**

Add empty method stubs for all callbacks referenced in createComponents (add to the classdef before the final `end`):

```matlab
    methods (Access = private)
        function onClassChanged(app)
            app.currentClass = app.ClassDropdown.Value;
        end

        function loadImage(app)
            % stub — implemented in Task 2.1
        end

        function loadFolder(app)
            % stub — implemented in Task 2.2
        end

        function startAnnotation(app)
            % stub — implemented in Task 3.1
        end

        function deleteRegion(app)
            % stub — implemented in Task 5.3
        end

        function undoAction(app)
            % stub — implemented in Task 5.1
        end

        function redoAction(app)
            % stub — implemented in Task 5.2
        end

        function prevImage(app)
            % stub — implemented in Task 5.4
        end

        function nextImage(app)
            % stub — implemented in Task 5.4
        end

        function saveCurrent(app)
            % stub — implemented in Task 4.3
        end

        function exportAll(app)
            % stub — implemented in Task 4.4
        end

        function reclassifyRegion(app)
            % stub — implemented in Task 5.5
        end

        function onRegionSelected(app)
            % stub — implemented in Task 4.1
        end

        function onClose(app)
            % stub — implemented in Task 4.5
        end

        function updateButtonStates(app)
            hasImg = ~isempty(app.currentImg);
            app.StartAnnotationButton.Enable = hasImg;
            app.DeleteRegionButton.Enable = hasImg && app.selectedRegion > 0;
            app.UndoButton.Enable = hasImg && ~undoStack('isEmpty', app.undoStack);
            app.RedoButton.Enable = hasImg && ~undoStack('isEmpty', app.redoStack);
            app.SaveButton.Enable = hasImg;
            app.ExportButton.Enable = hasImg;
            app.PrevButton.Enable = hasImg && app.currentIdx > 1;
            app.NextButton.Enable = hasImg && app.currentIdx < numel(app.imageList);
            app.ReclassifyDropdown.Enable = hasImg && app.selectedRegion > 0;
        end

        function updateStatusBar(app)
            if isempty(app.currentImg)
                app.StatusBar.Text = 'No image loaded';
            elseif isempty(app.imageList)
                app.StatusBar.Text = sprintf('%s | %d regions | %s', ...
                    app.getCurrentFilename(), numel(app.regions), ...
                    conditional(app.dirty, 'Unsaved', 'Saved'));
            else
                app.StatusBar.Text = sprintf('%s | %d/%d | %d regions | %s', ...
                    app.getCurrentFilename(), app.currentIdx, numel(app.imageList), ...
                    numel(app.regions), conditional(app.dirty, 'Unsaved', 'Saved'));
            end
        end

        function name = getCurrentFilename(app)
            if app.currentIdx > 0 && app.currentIdx <= numel(app.imageList)
                [~, name, ext] = fileparts(app.imageList{app.currentIdx});
                name = [name ext];
            else
                name = '';
            end
        end
    end
```

```matlab
% Helper: inline conditional (no ternary in MATLAB)
function out = conditional(cond, t, f)
    if cond, out = t; else, out = f; end
end
```
Place the `conditional` helper as a local function at the bottom of `ArtLabeler.m` (outside the classdef).

- [ ] **Step 3: Test — run ArtLabeler() in MATLAB**

Run: `ArtLabeler` in MATLAB command window.
Expected: Figure opens with left/center/right panels. Buttons disabled. Status "No image loaded."

- [ ] **Step 4: Commit**

---

## Chunk 2: Image Loading & Display

### Task 2.1: Implement loadImage()

**Files:** Modify `ArtLabeler.m`

- [ ] **Step 1: Replace the loadImage stub with full implementation**

```matlab
function loadImage(app)
    [filename, pathname] = uigetfile({'*.jpg;*.png;*.bmp', 'Image Files (*.jpg,*.png,*.bmp)'});
    if isequal(filename, 0)
        return;  % user cancelled
    end

    fullpath = fullfile(pathname, filename);
    try
        img = imread(fullpath);
    catch
        uialert(app.UIFigure, ['Failed to read: ' filename], 'Load Error');
        return;
    end

    % Save current before switching
    if app.dirty
        app.saveCurrent();
    end

    app.clearRegions();
    app.imageList = {fullpath};
    app.currentIdx = 1;
    app.imageDir = pathname;
    app.currentImg = img;

    imshow(app.currentImg, 'Parent', app.UIAxes);
    app.updateButtonStates();
    app.updateStatusBar();
    app.updateInfoPanel();

    % Load annotations if exist
    app.loadAnnotations();
end
```

- [ ] **Step 2: Test — click "Load Image"**

Run: `ArtLabeler`, click "Load Image", select a .jpg file.
Expected: Image displays in UIAxes. Buttons enable. Status shows filename.

- [ ] **Step 3: Commit**

---

### Task 2.2: Implement loadFolder()

**Files:** Modify `ArtLabeler.m`

- [ ] **Step 1: Replace the loadFolder stub**

```matlab
function loadFolder(app)
    pathname = uigetdir(pwd, 'Select Image Folder');
    if isequal(pathname, 0)
        return;  % user cancelled
    end

    files = dir(fullfile(pathname, '*.jpg'));
    files = [files; dir(fullfile(pathname, '*.png'))];
    files = [files; dir(fullfile(pathname, '*.bmp'))];

    if isempty(files)
        uialert(app.UIFigure, 'No supported images found in this folder.', 'Empty Folder');
        return;
    end

    % Save current before switching
    if app.dirty && ~isempty(app.currentImg)
        app.saveCurrent();
    end

    app.resetSession();
    app.imageDir = pathname;
    app.imageList = cell(1, numel(files));
    for i = 1:numel(files)
        app.imageList{i} = fullfile(pathname, files(i).name);
    end
    app.currentIdx = 1;

    app.loadCurrentImage();
end
```

- [ ] **Step 2: Add loadCurrentImage() helper**

```matlab
function loadCurrentImage(app)
    if isempty(app.imageList) || app.currentIdx < 1
        return;
    end
    try
        app.currentImg = imread(app.imageList{app.currentIdx});
    catch
        uialert(app.UIFigure, ...
            ['Failed to read: ' app.imageList{app.currentIdx}], 'Load Error');
        app.currentImg = [];
        return;
    end
    imshow(app.currentImg, 'Parent', app.UIAxes);
    app.updateButtonStates();
    app.updateStatusBar();
    app.updateInfoPanel();
    app.loadAnnotations();
end
```

- [ ] **Step 3: Add resetSession() and clearRegions()**

```matlab
function resetSession(app)
    app.clearRegions();
    app.imageList = {};
    app.currentIdx = 0;
    app.imageDir = '';
    app.currentImg = [];
end

function clearRegions(app)
    if ~isempty(app.saveDebounceTimer) && isvalid(app.saveDebounceTimer)
        stop(app.saveDebounceTimer);
    end
    for i = 1:numel(app.regions)
        if ~isempty(app.regions{i}.roi) && isvalid(app.regions{i}.roi)
            delete(app.regions{i}.roi);
        end
    end
    app.regions = {};
    app.undoStack = undoStack('create', 50);
    app.redoStack = undoStack('create', 50);
    app.selectedRegion = 0;
    app.dirty = false;
end
```

- [ ] **Step 4: Add loadAnnotations() stub** (implemented in Task 4.6)

```matlab
function loadAnnotations(app)
    % stub — implemented in Task 4.6
end
```

- [ ] **Step 5: Test — click "Load Folder"**

Run: `ArtLabeler`, click "Load Folder", select a folder with images.
Expected: First image displays. Buttons enable. Status shows "1/N".

- [ ] **Step 6: Commit**

---

## Chunk 3: Core Annotation — Polygon Drawing + Mask + Overlay

### Task 3.1: Implement startAnnotation() and polygon completion

**Files:** Modify `ArtLabeler.m`

- [ ] **Step 1: Replace startAnnotation stub**

```matlab
function startAnnotation(app)
    if isempty(app.currentImg)
        app.StatusBar.Text = 'Load an image first.';
        return;
    end
    if app.isDrawing
        app.StatusBar.Text = 'Already drawing — double-click to finish current polygon.';
        return;
    end
    % Deselect any selected region
    if app.selectedRegion > 0
        app.deselectRegion();
    end

    app.isDrawing = true;
    % Create debounce timer on first annotation
    if isempty(app.saveDebounceTimer) || ~isvalid(app.saveDebounceTimer)
        app.saveDebounceTimer = timer('ExecutionMode', 'singleShot', ...
            'StartDelay', 0.5, 'TimerFcn', @(~,~) autoSave(app));
    end
    app.StatusBar.Text = 'Click to add vertices. Double-click to finish. Esc to cancel.';

    roi = drawpolygon(app.UIAxes);
    app.isDrawing = false;

    if isempty(roi) || ~isvalid(roi) || size(roi.Position, 1) < 3
        app.StatusBar.Text = 'Polygon cancelled or too few vertices.';
        return;
    end

    mask = createMask(roi);
    if sum(mask(:)) == 0
        delete(roi);
        app.StatusBar.Text = 'Invalid polygon — too few vertices or zero area.';
        return;
    end

    % Push undo before appending
    app.pushUndo();

    roi.InteractionsAllowed = 'reshape';
    region = struct('points', roi.Position, 'label', app.currentClass, ...
        'mask', mask, 'roi', roi);
    app.regions{end+1} = region;
    app.dirty = true;

    app.updateOverlay();
    app.updateInfoPanel();
    app.autoSave();
end
```

- [ ] **Step 2: Add deselectRegion() helper**

```matlab
function deselectRegion(app)
    if app.selectedRegion > 0 && app.selectedRegion <= numel(app.regions)
        r = app.regions{app.selectedRegion};
        if ~isempty(r.roi) && isvalid(r.roi)
            r.roi.Visible = 'off';
        end
    end
    app.selectedRegion = 0;
    app.RegionList.Value = {};
end
```

- [ ] **Step 3: Test drawing**

Run: `ArtLabeler`, load image, select class from dropdown, click "Start Annotation".
Expected: Crosshair cursor. Click vertices, double-click to finish. No crash.

- [ ] **Step 4: Commit**

---

### Task 3.2: Implement updateOverlay()

**Files:** Modify `ArtLabeler.m`

- [ ] **Step 1: Add updateOverlay()**

```matlab
function updateOverlay(app)
    % Remove old overlay image if exists
    existing = findobj(app.UIAxes, 'Type', 'Image');
    if numel(existing) > 1
        delete(existing(2:end));  % delete overlay, keep base image
    end

    if isempty(app.regions)
        return;
    end

    colors = containers.Map(...
        {'person', 'building', 'sky', 'plant'}, ...
        {[1 0 0], [0 0 1], [0.5 0.8 1], [0 0.6 0]});

    [h, w, ~] = size(app.currentImg);
    overlay = zeros(h, w, 3);

    for i = 1:numel(app.regions)
        c = colors(app.regions{i}.label);
        mask = app.regions{i}.mask;
        for ch = 1:3
            chOverlay = overlay(:,:,ch);
            chOverlay(mask) = c(ch);
            overlay(:,:,ch) = chOverlay;
        end
    end

    hold(app.UIAxes, 'on');
    hImg = imshow(overlay, 'Parent', app.UIAxes);
    set(hImg, 'AlphaData', 0.4);
    hold(app.UIAxes, 'off');
end
```

- [ ] **Step 2: Test overlay**

Run: `ArtLabeler`, load image, draw polygon.
Expected: Semi-transparent colored overlay appears over the drawn region.

- [ ] **Step 3: Commit**

---

### Task 3.3: Implement updateInfoPanel() and mask preview

**Files:** Modify `ArtLabeler.m`

- [ ] **Step 1: Add updateInfoPanel()**

```matlab
function updateInfoPanel(app)
    n = numel(app.regions);
    app.RegionCountLabel.Text = sprintf('Regions: %d', n);

    % Build region list
    items = cell(1, n);
    for i = 1:n
        areaPx = sum(app.regions{i}.mask(:));
        totalPx = numel(app.regions{i}.mask);
        pct = 100 * areaPx / totalPx;
        items{i} = sprintf('%s — %.1f%%', app.regions{i}.label, pct);
    end
    app.RegionList.Items = items;

    % Build area stats
    if n == 0
        app.AreaStatsLabel.Text = 'Area Stats: —';
    else
        stats = cell(1, n+1);
        stats{1} = 'Area Stats:';
        for i = 1:n
            areaPx = sum(app.regions{i}.mask(:));
            totalPx = numel(app.regions{i}.mask);
            pct = 100 * areaPx / totalPx;
            stats{i+1} = sprintf('  %s: %d px (%.1f%%)', ...
                app.regions{i}.label, areaPx, pct);
        end
        app.AreaStatsLabel.Text = strjoin(stats, newline);
    end

    app.updateMaskPreview();
    app.updateButtonStates();
    app.updateStatusBar();
end
```

- [ ] **Step 2: Add updateMaskPreview()**

```matlab
function updateMaskPreview(app)
    cla(app.MaskPreviewAxes);
    if isempty(app.regions) || isempty(app.currentImg)
        return;
    end

    [h, w, ~] = size(app.currentImg);
    combined = zeros(h, w, 'uint8');
    classIds = containers.Map(...
        {'person', 'building', 'sky', 'plant'}, ...
        {1, 2, 3, 4});
    for i = 1:numel(app.regions)
        id = classIds(app.regions{i}.label);
        combined(app.regions{i}.mask) = id;
    end

    imagesc(app.MaskPreviewAxes, combined);
    axis(app.MaskPreviewAxes, 'equal');
    colormap(app.MaskPreviewAxes, [0 0 0; 1 0 0; 0 0 1; 0.5 0.8 1; 0 0.6 0]);
    caxis(app.MaskPreviewAxes, [0 4]);
    app.MaskPreviewAxes.XTick = [];
    app.MaskPreviewAxes.YTick = [];
    title(app.MaskPreviewAxes, 'Mask Preview');
end
```

- [ ] **Step 3: Test info panel**

Run: `ArtLabeler`, load image, draw polygon.
Expected: Right panel shows "Regions: 1", list item with class + area%, area stats, mask preview.

- [ ] **Step 4: Commit**

---

### Task 3.4: Implement onRegionSelected()

**Files:** Modify `ArtLabeler.m`

- [ ] **Step 1: Replace onRegionSelected stub**

```matlab
function onRegionSelected(app)
    val = app.RegionList.Value;
    if isempty(val)
        % Deselected
        app.deselectRegion();
        return;
    end

    % Find which region was clicked
    idx = find(strcmp(app.RegionList.Items, val), 1);
    if isempty(idx)
        return;
    end

    % If clicking same region, deselect
    if app.selectedRegion == idx
        app.deselectRegion();
        return;
    end

    % Deselect old
    if app.selectedRegion > 0
        old = app.regions{app.selectedRegion};
        if ~isempty(old.roi) && isvalid(old.roi)
            old.roi.Visible = 'off';
        end
    end

    % Select new
    app.selectedRegion = idx;
    r = app.regions{idx};
    if ~isempty(r.roi) && isvalid(r.roi)
        r.roi.Visible = 'on';
    end

    app.ReclassifyDropdown.Value = r.label;
    app.ReclassifyDropdown.Enable = true;
    app.DeleteRegionButton.Enable = true;
    app.updateButtonStates();
end
```

- [ ] **Step 2: Test region selection**

Run: `ArtLabeler`, draw 2 polygons. Click items in region list.
Expected: Clicked polygon highlights. Click again deselects. Selection switches between items.

- [ ] **Step 3: Commit**

---

## Chunk 4: Export & Persistence

### Task 4.1: Create exportMask.m

**Files:** Create `exportMask.m`

- [ ] **Step 1: Write exportMask.m**

```matlab
function exportMask(regions, imageSize, filepath)
    % exportMask  Generate indexed label PNG from annotated regions
    %   exportMask(regions, imageSize, filepath)
    %   regions: cell array of region structs
    %   imageSize: [height, width]
    %   filepath: full output path

    combined = zeros(imageSize, 'uint8');
    classIds = containers.Map(...
        {'person', 'building', 'sky', 'plant'}, ...
        {1, 2, 3, 4});

    for i = 1:numel(regions)
        if isKey(classIds, regions{i}.label)
            id = classIds(regions{i}.label);
            combined(regions{i}.mask) = id;
        end
    end

    imwrite(combined, filepath);
end
```

- [ ] **Step 2: Test exportMask**

In MATLAB:
```matlab
r = {struct('label','person','mask',true(10,10))};
exportMask(r, [10 10], 'test_mask.png');
info = imfinfo('test_mask.png');
% Verify file created
```

- [ ] **Step 3: Commit**

---

### Task 4.2: Create exportJson.m

**Files:** Create `exportJson.m`

- [ ] **Step 1: Write exportJson.m**

```matlab
function exportJson(filename, imageSize, regions, filepath)
    % exportJson  Write annotation metadata as JSON
    %   exportJson(filename, imageSize, regions, filepath)
    %   filename: source image name (e.g. '001.jpg')
    %   imageSize: [height, width]
    %   regions: cell array of region structs
    %   filepath: full output path

    data.image = filename;
    data.width = imageSize(2);
    data.height = imageSize(1);
    data.regions = [];

    totalPx = imageSize(1) * imageSize(2);
    regionsOut = cell(1, numel(regions));

    for i = 1:numel(regions)
        r = regions{i};
        area = sum(r.mask(:));

        % Remove roi handle from points (graphics handle, not serializable)
        points = r.points;

        maskFilename = strrep(filename, '.', '_mask_');
        maskFilename = [maskFilename num2str(i) '.png'];

        regionsOut{i} = struct(...
            'label', r.label, ...
            'mask', maskFilename, ...
            'area', area, ...
            'areaPercent', round(10000 * area / totalPx) / 100, ...
            'points', points);
    end

    if ~isempty(regionsOut)
        data.regions = regionsOut;
    else
        data.regions = {};
    end

    jsonStr = jsonencode(data);
    fid = fopen(filepath, 'w');
    if fid == -1
        error('exportJson:cannotOpen', 'Cannot open %s for writing', filepath);
    end
    fprintf(fid, '%s', jsonStr);
    fclose(fid);
end
```

- [ ] **Step 2: Test exportJson**

In MATLAB:
```matlab
r = {struct('label','person','mask',true(10,10),'points',[1 1; 2 1; 2 2])};
exportJson('test.jpg', [10 10], r, 'test_meta.json');
type test_meta.json
```

- [ ] **Step 3: Commit**

---

### Task 4.3: Implement autoSave() and saveCurrent() in ArtLabeler

**Files:** Modify `ArtLabeler.m`

- [ ] **Step 1: Replace saveCurrent stub and add autoSave**

```matlab
function saveCurrent(app)
    if isempty(app.currentImg) || app.currentIdx < 1
        return;
    end
    [~, name, ext] = fileparts(app.imageList{app.currentIdx});

    maskPath = fullfile(app.imageDir, [name '_mask.png']);
    jsonPath = fullfile(app.imageDir, [name '_meta.json']);

    try
        exportMask(app.regions, size(app.currentImg, [1 2]), maskPath);
        exportJson([name ext], size(app.currentImg, [1 2]), app.regions, jsonPath);
        app.dirty = false;
        app.StatusBar.Text = sprintf('Saved %s_mask.png, %s_meta.json', name, name);
        app.updateStatusBar();
    catch ME
        app.StatusBar.Text = ['Save error: ' ME.message];
    end
end

function pushUndo(app)
    app.redoStack = undoStack('clear', app.redoStack);
    app.undoStack = undoStack('push', app.undoStack, app.regions);
end

function autoSave(app)
    if isempty(app.currentImg)
        return;
    end
    app.saveCurrent();
end
```

- [ ] **Step 2: Test auto-save**

Run: `ArtLabeler`, load image, draw polygon.
Expected: `_mask.png` and `_meta.json` appear next to the source image file.

- [ ] **Step 3: Commit**

---

### Task 4.4: Implement exportAll()

**Files:** Modify `ArtLabeler.m`

- [ ] **Step 1: Replace exportAll stub**

```matlab
function exportAll(app)
    if isempty(app.imageDir)
        uialert(app.UIFigure, 'No image folder loaded.', 'Export Error');
        return;
    end

    % Checkbox dialog for format selection
    [indx, tf] = listdlg('PromptString', 'Select export formats:', ...
        'SelectionMode', 'multiple', ...
        'ListString', {'Mask PNG', 'JSON', 'LabelMe XML'}, ...
        'Name', 'Export', 'ListSize', [200 100]);
    if tf == 0
        return;  % cancelled
    end
    if isempty(indx)
        uialert(app.UIFigure, 'Select at least one export format.', 'Export');
        return;
    end

    % Scan for meta.json files
    metaFiles = dir(fullfile(app.imageDir, '*_meta.json'));
    if isempty(metaFiles)
        uialert(app.UIFigure, 'No annotations found to export.', 'Export');
        return;
    end

    % Overwrite check
    choice = uiconfirm(app.UIFigure, ...
        'Existing export files will be overwritten. Continue?', ...
        'Export', 'Options', {'Continue', 'Cancel'}, ...
        'DefaultOption', 1, 'CancelOption', 2);
    if strcmp(choice, 'Cancel'), return; end

    exportMaskFmt = ismember(1, indx);
    exportJsonFmt = ismember(2, indx);
    exportLabelMeFmt = ismember(3, indx);

    count = 0;
    for i = 1:numel(metaFiles)
        jsonPath = fullfile(app.imageDir, metaFiles(i).name);
        try
            txt = fileread(jsonPath);
            data = jsondecode(txt);

            % Recompute areas from regenerated masks where applicable
            if exportMaskFmt
                combined = zeros(data.height, data.width, 'uint8');
                classIds = containers.Map(...
                    {'person', 'building', 'sky', 'plant'}, ...
                    {1, 2, 3, 4});
                for j = 1:numel(data.regions)
                    pts = data.regions{j}.points;
                    if size(pts, 1) >= 3
                        roi = images.roi.Polygon('Position', pts);
                        mask = createMask(roi, data.height, data.width);
                        if isKey(classIds, data.regions{j}.label)
                            combined(mask) = classIds(data.regions{j}.label);
                        end
                        delete(roi);
                    end
                end
                maskPath = strrep(jsonPath, '_meta.json', '_mask.png');
                imwrite(combined, maskPath);
            end

            if exportJsonFmt
                % Regenerate JSON: build proper region structs from points
                regionsForJson = {};
                for j = 1:numel(data.regions)
                    pts = data.regions{j}.points;
                    if size(pts, 1) >= 3
                        roi = images.roi.Polygon('Position', pts);
                        m = createMask(roi, data.height, data.width);
                        regionsForJson{end+1} = struct(...
                            'label', data.regions{j}.label, ...
                            'points', pts, 'mask', m);
                        delete(roi);
                    end
                end
                exportJson(data.image, [data.height data.width], regionsForJson, jsonPath);
            end

            if exportLabelMeFmt
                [~, name] = fileparts(strrep(metaFiles(i).name, '_meta', ''));
                xmlPath = fullfile(app.imageDir, [name '.xml']);
                exportLabelMe(data.image, [data.height data.width], data.regions, xmlPath);
            end

            count = count + 1;
        catch ME
            warning('Export failed for %s: %s', metaFiles(i).name, ME.message);
        end
    end

    uialert(app.UIFigure, ...
        sprintf('Exported %d annotated images.', numel(metaFiles)), ...
        'Export Complete');
end
```

- [ ] **Step 2: Test export**

Run: `ArtLabeler`, load folder with annotated images, click Export.
Expected: Dialog appears. Exports regenerated masks + LabelMe XML.

- [ ] **Step 3: Commit**

---

### Task 4.5: Implement onClose()

**Files:** Modify `ArtLabeler.m`

- [ ] **Step 1: Replace onClose stub**

```matlab
function onClose(app)
    if app.dirty
        choice = uiconfirm(app.UIFigure, ...
            'Unsaved changes. Save before closing?', ...
            'Close', 'Options', {'Yes', 'No', 'Cancel'}, ...
            'DefaultOption', 1, 'CancelOption', 3);
        switch choice
            case 'Yes'
                app.saveCurrent();
            case 'Cancel'
                return;
        end
    end
    % Clean up timer
    if ~isempty(app.saveDebounceTimer) && isvalid(app.saveDebounceTimer)
        stop(app.saveDebounceTimer);
        delete(app.saveDebounceTimer);
    end
    % Delete ROI handles
    for i = 1:numel(app.regions)
        if ~isempty(app.regions{i}.roi) && isvalid(app.regions{i}.roi)
            delete(app.regions{i}.roi);
        end
    end
    delete(app.UIFigure);
end
```

- [ ] **Step 2: Test close**

Run: `ArtLabeler`, load image, draw polygon (dirty=true), click X to close.
Expected: Confirm dialog appears. Yes saves. No closes without save. Cancel stays open.

- [ ] **Step 5: Commit**

---

### Task 4.6: Implement loadAnnotations()

**Files:** Modify `ArtLabeler.m`

- [ ] **Step 1: Replace loadAnnotations stub**

```matlab
function loadAnnotations(app)
    if isempty(app.currentImg) || app.currentIdx < 1
        return;
    end
    [~, name] = fileparts(app.imageList{app.currentIdx});
    jsonPath = fullfile(app.imageDir, [name '_meta.json']);

    if ~isfile(jsonPath)
        return;
    end

    try
        txt = fileread(jsonPath);
        data = jsondecode(txt);

        for i = 1:numel(data.regions)
            pts = data.regions{i}.points;
            if size(pts, 1) < 3
                continue;
            end
            roi = drawpolygon(app.UIAxes, 'Position', pts);
            roi.InteractionsAllowed = 'reshape';
            roi.Visible = 'off';
            mask = createMask(roi);

            region = struct('points', roi.Position, ...
                'label', data.regions{i}.label, ...
                'mask', mask, 'roi', roi);
            app.regions{end+1} = region;
        end

        app.updateOverlay();
        app.updateInfoPanel();
    catch ME
        app.StatusBar.Text = ['Warning: Could not load annotations — ' ME.message];
    end
end
```

- [ ] **Step 2: Test annotation loading**

Run: `ArtLabeler`, load folder, draw some polygons on image 1, navigate to image 2, then back to image 1.
Expected: Annotations restore on image 1 with polygons and overlay.

- [ ] **Step 3: Commit**

---

### Task 4.7: Create exportLabelMe.m

**Files:** Create `exportLabelMe.m`

- [ ] **Step 1: Write exportLabelMe.m**

```matlab
function exportLabelMe(filename, imageSize, regions, filepath)
    % exportLabelMe  Write LabelMe-compatible XML annotation
    %   exportLabelMe(filename, imageSize, regions, filepath)

    fid = fopen(filepath, 'w');
    if fid == -1
        error('exportLabelMe:cannotOpen', 'Cannot open %s', filepath);
    end

    fprintf(fid, '<annotation>\n');
    fprintf(fid, '  <filename>%s</filename>\n', filename);
    fprintf(fid, '  <folder>%s</folder>\n', fileparts(filepath));
    fprintf(fid, '  <source><annotation>ArtLabeler</annotation></source>\n');
    fprintf(fid, '  <imagesize><nrows>%d</nrows><ncols>%d</ncols></imagesize>\n', ...
        imageSize(1), imageSize(2));

    for i = 1:numel(regions)
        fprintf(fid, '  <object>\n');
        fprintf(fid, '    <name>%s</name>\n', regions{i}.label);
        fprintf(fid, '    <deleted>0</deleted>\n');
        fprintf(fid, '    <verified>0</verified>\n');
        fprintf(fid, '    <polygon>\n');
        pts = regions{i}.points;
        for j = 1:size(pts, 1)
            fprintf(fid, '      <pt><x>%d</x><y>%d</y></pt>\n', round(pts(j,1)), round(pts(j,2)));
        end
        fprintf(fid, '    </polygon>\n');
        fprintf(fid, '  </object>\n');
    end

    fprintf(fid, '</annotation>\n');
    fclose(fid);
end
```

- [ ] **Step 2: Test exportLabelMe**

In MATLAB:
```matlab
r = {struct('label','person','points',[1 1;2 1;2 2],'mask',true(10,10))};
exportLabelMe('test.jpg', [10 10], r, 'test.xml');
```

- [ ] **Step 3: Commit**

---

## Chunk 5: Edit Operations & Navigation

### Task 5.1: Implement undoAction()

**Files:** Modify `ArtLabeler.m`

- [ ] **Step 1: Replace undoAction stub**

```matlab
function undoAction(app)
    if undoStack('isEmpty', app.undoStack)
        app.StatusBar.Text = 'Nothing to undo.';
        return;
    end
    % Save current state to redo before popping
    app.redoStack = undoStack('push', app.redoStack, app.regions);
    [app.undoStack, snapshot] = undoStack('pop', app.undoStack);

    if isempty(snapshot)
        snapshot = {};
    end

    % Clean up ROI handles from current regions
    for i = 1:numel(app.regions)
        if ~isempty(app.regions{i}.roi) && isvalid(app.regions{i}.roi)
            delete(app.regions{i}.roi);
        end
    end

    % Restore from snapshot (roi fields are [] in snapshots — need to recreate)
    app.regions = {};
    for i = 1:numel(snapshot)
        r = snapshot{i};
        roi = drawpolygon(app.UIAxes, 'Position', r.points);
        roi.InteractionsAllowed = 'reshape';
        roi.Visible = 'off';
        r.roi = roi;
        r.mask = createMask(roi);
        app.regions{i} = r;
    end

    app.selectedRegion = 0;
    app.updateOverlay();
    app.updateInfoPanel();
    app.autoSave();
end
```

- [ ] **Step 2: Test undo**

Run: `ArtLabeler`, draw polygon, press Ctrl+Z or click Undo.
Expected: Polygon removed. Redo button enables. Draw again, undo removes it.

- [ ] **Step 3: Commit**

---

### Task 5.2: Implement redoAction()

**Files:** Modify `ArtLabeler.m`

- [ ] **Step 1: Replace redoAction stub**

```matlab
function redoAction(app)
    if undoStack('isEmpty', app.redoStack)
        app.StatusBar.Text = 'Nothing to redo.';
        return;
    end
    % Save current state to undo
    app.undoStack = undoStack('push', app.undoStack, app.regions);
    [app.redoStack, snapshot] = undoStack('pop', app.redoStack);

    % Clean up current ROI handles
    for i = 1:numel(app.regions)
        if ~isempty(app.regions{i}.roi) && isvalid(app.regions{i}.roi)
            delete(app.regions{i}.roi);
        end
    end

    % Restore from snapshot
    app.regions = {};
    for i = 1:numel(snapshot)
        r = snapshot{i};
        roi = drawpolygon(app.UIAxes, 'Position', r.points);
        roi.InteractionsAllowed = 'reshape';
        roi.Visible = 'off';
        r.roi = roi;
        r.mask = createMask(roi);
        app.regions{i} = r;
    end

    app.selectedRegion = 0;
    app.updateOverlay();
    app.updateInfoPanel();
    app.autoSave();
end
```

- [ ] **Step 2: Test redo**

Run: `ArtLabeler`, draw polygon, undo, then Ctrl+Y or click Redo.
Expected: Polygon reappears.

- [ ] **Step 3: Commit**

---

### Task 5.3: Implement deleteRegion()

**Files:** Modify `ArtLabeler.m`

- [ ] **Step 1: Replace deleteRegion stub**

```matlab
function deleteRegion(app)
    if app.selectedRegion < 1 || app.selectedRegion > numel(app.regions)
        app.StatusBar.Text = 'No region selected.';
        return;
    end

    app.pushUndo();

    % Delete ROI handle
    r = app.regions{app.selectedRegion};
    if ~isempty(r.roi) && isvalid(r.roi)
        delete(r.roi);
    end

    app.regions(app.selectedRegion) = [];
    app.selectedRegion = 0;
    app.dirty = true;

    app.updateOverlay();
    app.updateInfoPanel();
    app.autoSave();
end
```

- [ ] **Step 2: Test delete**

Run: `ArtLabeler`, draw polygon, select it in list, click Delete Region or press Delete.
Expected: Region removed. Overlay updates.

- [ ] **Step 3: Commit**

---

### Task 5.4: Implement nextImage() and prevImage()

**Files:** Modify `ArtLabeler.m`

- [ ] **Step 1: Replace nextImage and prevImage stubs**

```matlab
function nextImage(app)
    if app.currentIdx >= numel(app.imageList)
        return;
    end
    % Save current before switching
    if app.dirty
        app.saveCurrent();
    end
    app.clearRegions();
    app.currentIdx = app.currentIdx + 1;
    app.loadCurrentImage();
end

function prevImage(app)
    if app.currentIdx <= 1
        return;
    end
    if app.dirty
        app.saveCurrent();
    end
    app.clearRegions();
    app.currentIdx = app.currentIdx - 1;
    app.loadCurrentImage();
end
```

- [ ] **Step 2: Test navigation**

Run: `ArtLabeler`, load folder, draw polygon on image 1, click Next, click Previous.
Expected: Polygon saved on image 1. Image 2 loads. Back to image 1 restores annotation.

- [ ] **Step 3: Commit**

---

### Task 5.5: Implement reclassifyRegion()

**Files:** Modify `ArtLabeler.m`

- [ ] **Step 1: Replace reclassifyRegion stub**

```matlab
function reclassifyRegion(app)
    if app.selectedRegion < 1 || app.selectedRegion > numel(app.regions)
        return;
    end
    newLabel = app.ReclassifyDropdown.Value;
    oldLabel = app.regions{app.selectedRegion}.label;
    if strcmp(newLabel, oldLabel)
        return;
    end

    app.pushUndo();

    app.regions{app.selectedRegion}.label = newLabel;
    app.dirty = true;

    app.updateOverlay();
    app.updateInfoPanel();
    app.autoSave();
end
```

- [ ] **Step 2: Test reclassification**

Run: `ArtLabeler`, draw polygon as "person", select it, change reclassify dropdown to "building".
Expected: Overlay color changes from red to blue. List updates.

- [ ] **Step 3: Commit**

---

## Chunk 6: Advanced Features — Dark Theme, Shortcuts, Vertex Dragging

### Task 6.1: Apply dark theme on startup

**Files:** Modify `ArtLabeler.m`

Already called in constructor (`darkTheme(app)`). Verify it works.

- [ ] **Step 1: Test dark theme**

Run: `ArtLabeler`.
Expected: Dark background, light text, dark buttons.

- [ ] **Step 2: Commit**

---

### Task 6.2: Implement keyboard shortcuts

**Files:** Modify `ArtLabeler.m`

- [ ] **Step 1: Add KeyPressFcn setup in createComponents**

Add after `app.UIFigure = uifigure(...)`:
```matlab
app.UIFigure.KeyPressFcn = @(~, evt) onKeyPress(app, evt);
```

- [ ] **Step 2: Add onKeyPress method**

```matlab
function onKeyPress(app, evt)
    switch evt.Key
        case 'z'
            if any(strcmp(evt.Modifier, 'control'))
                app.undoAction();
            end
        case 'y'
            if any(strcmp(evt.Modifier, 'control'))
                app.redoAction();
            end
        case 'delete'
            app.deleteRegion();
        case 's'
            app.saveCurrent();
        case 'n'
            app.nextImage();
        case 'p'
            app.prevImage();
        case 'e'
            app.exportAll();
    end
end
```

- [ ] **Step 3: Test shortcuts**

Run: `ArtLabeler`, load image. Press S (save), N (next), P (prev), Ctrl+Z (undo).
Expected: Each shortcut triggers the corresponding action.

- [ ] **Step 4: Commit**

---

### Task 6.3: Implement vertex dragging with debounced save

**Files:** Modify `ArtLabeler.m`

- [ ] **Step 1: Add ROIMoved listener setup in startAnnotation**

Replace `roi.InteractionsAllowed = 'reshape';` section in `startAnnotation()`:

```matlab
roi.InteractionsAllowed = 'reshape';
addlistener(roi, 'ROIMoved', @(src, ~) onVertexDragged(app, src));
```

Also add the same listener in `undoAction()`, `redoAction()`, and `loadAnnotations()` where polygons are recreated from snapshots.

- [ ] **Step 2: Add onVertexDragged method**

```matlab
function onVertexDragged(app, roi)
    % Find which region this ROI belongs to
    idx = 0;
    for i = 1:numel(app.regions)
        if app.regions{i}.roi == roi
            idx = i;
            break;
        end
    end
    if idx == 0
        return;
    end

    % Update points
    oldPoints = app.regions{idx}.points;
    app.regions{idx}.points = roi.Position;
    newMask = createMask(roi);

    if sum(newMask(:)) == 0
        % Degenerate — revert
        app.regions{idx}.points = oldPoints;
        roi.Position = oldPoints;
        app.StatusBar.Text = 'Invalid polygon shape — reverted.';
        return;
    end

    app.regions{idx}.mask = newMask;
    app.dirty = true;
    app.updateOverlay();
    app.updateInfoPanel();

    % Debounce timer (created in startAnnotation)
    if ~isempty(app.saveDebounceTimer) && isvalid(app.saveDebounceTimer)
        stop(app.saveDebounceTimer);
        start(app.saveDebounceTimer);
    end
end
```

- [ ] **Step 3: Test vertex dragging**

Run: `ArtLabeler`, draw polygon, select it in list, drag a vertex.
Expected: Mask updates during drag. After 0.5s of inactivity, auto-save fires.

- [ ] **Step 4: Commit**

---

### Task 6.4: Final polish — error handling and edge cases

**Files:** Modify `ArtLabeler.m`

- [ ] **Step 1: Verify all error handling cases from the spec**

Review and test each case:
- Load corrupt image → uialert, skip
- Empty folder → uialert
- Navigation bounds → buttons disabled at ends
- Undo at empty stack → "Nothing to undo"
- Redo at empty stack → "Nothing to redo"
- Delete with no selection → "No region selected"
- Close with unsaved → confirm dialog
- Empty regions save → all-zeros mask
- Restore corrupt JSON → warning, treat as fresh

- [ ] **Step 2: Add pixel density fix for high-DPI displays**

In `createComponents()`, after creating UIAxes:
```matlab
app.UIAxes.DataAspectRatio = [1 1 1];
```

- [ ] **Step 3: Final end-to-end test**

Run full workflow:
1. `ArtLabeler`
2. Load Folder → select folder with images
3. Draw "person" polygon → verify red overlay, stats, auto-save
4. Draw "sky" polygon → verify blue overlay
5. Select first region → reclassify to "building"
6. Undo → verify reclassify undone
7. Navigate Next → Previous → verify annotations restore
8. Keyboard shortcuts: N, P, Ctrl+Z, Delete, S
9. Close → verify save prompt
10. Check output folder for _mask.png, _meta.json, .xml

- [ ] **Step 4: Commit**
