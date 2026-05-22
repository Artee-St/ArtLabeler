classdef ArtLabeler < matlab.apps.AppBase
    % ArtLabeler  Interactive polygon-based image annotation tool.
    %
    %   ArtLabeler() launches the GUI. Draw polygon regions on images,
    %   assign class labels, and export pixel-level masks with JSON
    %   and LabelMe XML metadata.

    properties (Access = public)
        % UI components
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
        ManageTagsButton      matlab.ui.control.Button

        ClassDropdown      matlab.ui.control.DropDown
        ReclassifyDropdown matlab.ui.control.DropDown
        RegionList         matlab.ui.control.ListBox
        RegionCountLabel   matlab.ui.control.Label
        AreaStatsLabel     matlab.ui.control.Label
        StatusBar          matlab.ui.control.Label
    end

    properties (Access = public)
        regions        cell   = {}     % cell array of region structs
        imageList      cell   = {}     % full paths to images
        currentIdx     double = 0
        currentImg     double = []
        currentClass   char   = 'person'
        undoHistory    struct           % undo stack (renamed to avoid shadowing undoStack.m)
        redoHistory    struct           % redo stack
        isDrawing      logical = false
        dirty          logical = false
        selectedRegion double = 0
        saveTimer      timer            % debounce timer for vertex-drag auto-save
        imageDir       char   = ''
        classCfg       struct           % cached classConfig()
        overlayHandle    matlab.graphics.primitive.Image  % handle to overlay image
        baseImageHandle  matlab.graphics.primitive.Image  % handle to base image
    end

    methods (Access = public)

        function app = ArtLabeler()
            if ~isMATLABReleaseOlderThan('R2021b')
                % jsonencode supported natively
            else
                uialert(uifigure('Visible', 'off'), ...
                    'MATLAB R2021b or newer is recommended for full jsonencode support.', ...
                    'Version Warning');
            end

            app.classCfg = classConfig();

            app.createComponents();
            darkTheme(app);
            app.undoHistory = undoStack('create', 50);
            app.redoHistory = undoStack('create', 50);
            app.updateButtonStates();
            app.updateStatusBar();
            drawnow;
        end

    end

    methods (Access = private)

        % ================================================================
        %  UI Construction
        % ================================================================

        function createComponents(app)
            app.UIFigure = uifigure('Name', 'ArtLabeler', ...
                'Position', [100 100 1280 720], ...
                'CloseRequestFcn', @(~,~) onClose(app), ...
                'KeyPressFcn', @(~, evt) onKeyPress(app, evt));

            mainGrid = uigridlayout(app.UIFigure, [2 3]);
            mainGrid.ColumnWidth = {200, '1x', 220};
            mainGrid.RowHeight = {'1x', 22};
            mainGrid.Padding = [4 4 4 4];
            mainGrid.ColumnSpacing = 4;

            buildLeftPanel(app, mainGrid);
            buildCenterPanel(app, mainGrid);
            buildRightPanel(app, mainGrid);
            buildStatusBar(app, mainGrid);
        end

        function buildLeftPanel(app, mainGrid)
            app.LeftPanel = uipanel(mainGrid);
            app.LeftPanel.Layout.Row = 1;
            app.LeftPanel.Layout.Column = 1;

            leftGrid = uigridlayout(app.LeftPanel, [16 1]);
            leftGrid.RowHeight = repmat({25}, 1, 15);
            leftGrid.RowHeight{16} = '1x';
            leftGrid.Padding = [4 4 4 4];
            leftGrid.RowSpacing = 4;

            app.ClassDropdown = uidropdown(leftGrid, ...
                'Items', app.classCfg.classes, ...
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

            lbl = uilabel(leftGrid, 'Text', '', 'HorizontalAlignment', 'center');
            lbl.Layout.Row = 4;

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

            lbl = uilabel(leftGrid, 'Text', '', 'HorizontalAlignment', 'center');
            lbl.Layout.Row = 9;

            app.PrevButton = uibutton(leftGrid, 'push', ...
                'Text', [char(9664) ' Previous'], ...
                'ButtonPushedFcn', @(~,~) prevImage(app));
            app.PrevButton.Layout.Row = 10;

            app.NextButton = uibutton(leftGrid, 'push', ...
                'Text', ['Next ' char(9654)], ...
                'ButtonPushedFcn', @(~,~) nextImage(app));
            app.NextButton.Layout.Row = 11;

            lbl = uilabel(leftGrid, 'Text', '', 'HorizontalAlignment', 'center');
            lbl.Layout.Row = 13;

            app.ManageTagsButton = uibutton(leftGrid, 'push', ...
                'Text', 'Manage Tags', ...
                'ButtonPushedFcn', @(~,~) manageTags(app));
            app.ManageTagsButton.Layout.Row = 14;

            app.SaveButton = uibutton(leftGrid, 'push', ...
                'Text', 'Save', ...
                'ButtonPushedFcn', @(~,~) saveCurrent(app));
            app.SaveButton.Layout.Row = 15;

            app.ExportButton = uibutton(leftGrid, 'push', ...
                'Text', 'Export', ...
                'ButtonPushedFcn', @(~,~) exportAll(app));
            app.ExportButton.Layout.Row = 16;
        end

        function buildCenterPanel(app, mainGrid)
            app.CenterPanel = uipanel(mainGrid);
            app.CenterPanel.Layout.Row = 1;
            app.CenterPanel.Layout.Column = 2;

            app.UIAxes = uiaxes(app.CenterPanel, 'Units', 'normalized', ...
                'Position', [0 0 1 1]);
            app.UIAxes.XTick = [];
            app.UIAxes.YTick = [];
            app.UIAxes.Box = 'on';
            app.UIAxes.DataAspectRatio = [1 1 1];
        end

        function buildRightPanel(app, mainGrid)
            app.RightPanel = uipanel(mainGrid);
            app.RightPanel.Layout.Row = 1;
            app.RightPanel.Layout.Column = 3;

            rightGrid = uigridlayout(app.RightPanel, [6 1]);
            rightGrid.RowHeight = {25, 25, 120, 25, '1x', 180};
            rightGrid.Padding = [4 4 4 4];
            rightGrid.RowSpacing = 4;

            app.ReclassifyDropdown = uidropdown(rightGrid, ...
                'Items', app.classCfg.classes, ...
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

            app.MaskPreviewAxes = uiaxes(rightGrid);
            app.MaskPreviewAxes.Layout.Row = 6;
            app.MaskPreviewAxes.XTick = [];
            app.MaskPreviewAxes.YTick = [];
            title(app.MaskPreviewAxes, 'Mask Preview');
        end

        function buildStatusBar(app, mainGrid)
            app.StatusBar = uilabel(mainGrid, ...
                'Text', 'No image loaded', ...
                'HorizontalAlignment', 'left');
            app.StatusBar.Layout.Row = 2;
            app.StatusBar.Layout.Column = [1 3];
        end

        % ================================================================
        %  Image I/O
        % ================================================================

        function loadImage(app)
            [filename, pathname] = uigetfile(...
                {'*.jpg;*.png;*.bmp', 'Image Files (*.jpg,*.png,*.bmp)'});
            if isequal(filename, 0)
                return;
            end

            fullpath = fullfile(pathname, filename);
            try
                img = imread(fullpath);
            catch
                uialert(app.UIFigure, ['Failed to read: ' filename], 'Load Error');
                return;
            end

            if app.dirty
                app.saveCurrent();
            end

            app.clearRegions();
            app.imageList = {fullpath};
            app.currentIdx = 1;
            app.imageDir = pathname;
            app.currentImg = img;

            if ~isempty(app.baseImageHandle) && isvalid(app.baseImageHandle)
                delete(app.baseImageHandle);
            end
            dispImg = prepareForDisplay(app.currentImg);
            app.baseImageHandle = imshow(dispImg, 'Parent', app.UIAxes);
            drawnow;
            app.updateButtonStates();
            app.updateStatusBar();
            app.updateInfoPanel();
            app.loadAnnotations();
        end

        function loadFolder(app)
            pathname = uigetdir(pwd, 'Select Image Folder');
            if isequal(pathname, 0)
                return;
            end

            files = dir(fullfile(pathname, '*.jpg'));
            files = [files; dir(fullfile(pathname, '*.png'))];
            files = [files; dir(fullfile(pathname, '*.bmp'))];

            if isempty(files)
                uialert(app.UIFigure, ...
                    'No supported images found in this folder.', 'Empty Folder');
                return;
            end

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
            if ~isempty(app.baseImageHandle) && isvalid(app.baseImageHandle)
                delete(app.baseImageHandle);
            end
            dispImg = prepareForDisplay(app.currentImg);
            app.baseImageHandle = imshow(dispImg, 'Parent', app.UIAxes);
            drawnow;
            app.updateButtonStates();
            app.updateStatusBar();
            app.updateInfoPanel();
            app.loadAnnotations();
        end

        function nextImage(app)
            if app.currentIdx >= numel(app.imageList)
                return;
            end
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
                regions = normalizeRegions(data.regions);

                for i = 1:numel(regions)
                    pts = regions{i}.points;
                    if size(pts, 1) < 3
                        continue;
                    end
                    roi = drawpolygon(app.UIAxes, 'Position', pts);
                    roi.InteractionsAllowed = 'reshape';
                    addlistener(roi, 'ROIMoved', @(src, ~) onVertexDragged(app, src));
                    roi.Visible = 'off';
                    mask = createMask(roi, app.baseImageHandle);

                    region = struct('points', roi.Position, ...
                        'label', regions{i}.label, ...
                        'mask', mask, 'roi', roi);
                    app.regions{end+1} = region;
                end

                app.updateOverlay();
                app.updateInfoPanel();
            catch ME
                app.StatusBar.Text = ['Warning: Could not load annotations - ' ME.message];
            end
        end

        % ================================================================
        %  Session Management
        % ================================================================

        function resetSession(app)
            app.clearRegions();
            app.imageList = {};
            app.currentIdx = 0;
            app.imageDir = '';
            app.currentImg = [];
        end

        function clearRegions(app)
            stopTimer(app);
            for i = 1:numel(app.regions)
                if ~isempty(app.regions{i}.roi) && isvalid(app.regions{i}.roi)
                    delete(app.regions{i}.roi);
                end
            end
            if ~isempty(app.overlayHandle) && isvalid(app.overlayHandle)
                delete(app.overlayHandle);
            end
            app.overlayHandle = matlab.graphics.primitive.Image.empty;
            if ~isempty(app.baseImageHandle) && isvalid(app.baseImageHandle)
                delete(app.baseImageHandle);
            end
            app.baseImageHandle = matlab.graphics.primitive.Image.empty;
            app.regions = {};
            app.undoHistory = undoStack('create', 50);
            app.redoHistory = undoStack('create', 50);
            app.selectedRegion = 0;
            app.dirty = false;
        end

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
            deleteTimer(app);
            for i = 1:numel(app.regions)
                if ~isempty(app.regions{i}.roi) && isvalid(app.regions{i}.roi)
                    delete(app.regions{i}.roi);
                end
            end
            delete(app.UIFigure);
        end

        % ================================================================
        %  Annotation
        % ================================================================

        function startAnnotation(app)
            if isempty(app.currentImg)
                app.StatusBar.Text = 'Load an image first.';
                return;
            end
            if app.isDrawing
                app.StatusBar.Text = ...
                    'Already drawing - double-click to finish current polygon.';
                return;
            end
            if app.selectedRegion > 0
                app.deselectRegion();
            end

            app.isDrawing = true;
            ensureTimer(app);
            app.StatusBar.Text = ...
                'Click to add vertices. Double-click to finish. Esc to cancel.';

            roi = drawpolygon(app.UIAxes);
            app.isDrawing = false;

            if isempty(roi) || ~isvalid(roi) || size(roi.Position, 1) < 3
                app.StatusBar.Text = 'Polygon cancelled or too few vertices.';
                return;
            end

            mask = createMask(roi, app.baseImageHandle);
            if sum(mask(:)) == 0
                delete(roi);
                app.StatusBar.Text = 'Invalid polygon - too few vertices or zero area.';
                return;
            end

            app.pushUndo();

            roi.InteractionsAllowed = 'reshape';
            addlistener(roi, 'ROIMoved', @(src, ~) onVertexDragged(app, src));
            region = struct('points', roi.Position, ...
                'label', app.currentClass, 'mask', mask, 'roi', roi);
            app.regions{end+1} = region;
            app.dirty = true;

            app.updateOverlay();
            app.updateInfoPanel();
            app.autoSave();
        end

        function reclassifyRegion(app)
            if app.selectedRegion < 1 || app.selectedRegion > numel(app.regions)
                return;
            end
            newLabel = app.ReclassifyDropdown.Value;
            if strcmp(newLabel, app.regions{app.selectedRegion}.label)
                return;
            end

            app.pushUndo();
            app.regions{app.selectedRegion}.label = newLabel;
            app.dirty = true;

            app.updateOverlay();
            app.updateInfoPanel();
            app.autoSave();
        end

        function deleteRegion(app)
            if app.selectedRegion < 1 || app.selectedRegion > numel(app.regions)
                app.StatusBar.Text = 'No region selected.';
                return;
            end

            app.pushUndo();

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

        function onRegionSelected(app)
            val = app.RegionList.Value;
            if isempty(val)
                app.deselectRegion();
                return;
            end

            idx = find(strcmp(app.RegionList.Items, val), 1);
            if isempty(idx)
                return;
            end

            if app.selectedRegion == idx
                app.deselectRegion();
                return;
            end

            if app.selectedRegion > 0
                old = app.regions{app.selectedRegion};
                if ~isempty(old.roi) && isvalid(old.roi)
                    old.roi.Visible = 'off';
                end
            end

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

        function onVertexDragged(app, roi)
            idx = findRegionByRoi(app, roi);
            if idx == 0
                return;
            end

            oldPoints = app.regions{idx}.points;
            app.regions{idx}.points = roi.Position;
            newMask = createMask(roi, app.baseImageHandle);

            if sum(newMask(:)) == 0
                app.regions{idx}.points = oldPoints;
                roi.Position = oldPoints;
                app.StatusBar.Text = 'Invalid polygon shape - reverted.';
                return;
            end

            app.regions{idx}.mask = newMask;
            app.dirty = true;
            app.updateOverlay();
            app.updateInfoPanel();

            if ~isempty(app.saveTimer) && isvalid(app.saveTimer)
                stop(app.saveTimer);
                start(app.saveTimer);
            end
        end

        % ================================================================
        %  Undo / Redo
        % ================================================================

        function pushUndo(app)
            app.redoHistory = undoStack('clear', app.redoHistory);
            app.undoHistory = undoStack('push', app.undoHistory, app.regions);
        end

        function undoAction(app)
            if undoStack('isEmpty', app.undoHistory)
                app.StatusBar.Text = 'Nothing to undo.';
                return;
            end
            app.redoHistory = undoStack('push', app.redoHistory, app.regions);
            [app.undoHistory, snapshot] = undoStack('pop', app.undoHistory);
            app.restoreRegions(snapshot);
            app.autoSave();
        end

        function redoAction(app)
            if undoStack('isEmpty', app.redoHistory)
                app.StatusBar.Text = 'Nothing to redo.';
                return;
            end
            app.undoHistory = undoStack('push', app.undoHistory, app.regions);
            [app.redoHistory, snapshot] = undoStack('pop', app.redoHistory);
            app.restoreRegions(snapshot);
            app.autoSave();
        end

        function restoreRegions(app, snapshot)
            if isempty(snapshot)
                snapshot = {};
            end

            for i = 1:numel(app.regions)
                if ~isempty(app.regions{i}.roi) && isvalid(app.regions{i}.roi)
                    delete(app.regions{i}.roi);
                end
            end

            app.regions = {};
            for i = 1:numel(snapshot)
                r = snapshot{i};
                roi = drawpolygon(app.UIAxes, 'Position', r.points);
                roi.InteractionsAllowed = 'reshape';
                addlistener(roi, 'ROIMoved', @(src, ~) onVertexDragged(app, src));
                roi.Visible = 'off';
                r.roi = roi;
                r.mask = createMask(roi, app.baseImageHandle);
                app.regions{i} = r;
            end

            app.selectedRegion = 0;
            app.updateOverlay();
            app.updateInfoPanel();
        end

        % ================================================================
        %  Display Updates
        % ================================================================

        function updateOverlay(app)
            % Remove previous overlay image if it exists
            if ~isempty(app.overlayHandle) && isvalid(app.overlayHandle)
                delete(app.overlayHandle);
            end
            app.overlayHandle = matlab.graphics.primitive.Image.empty;

            if isempty(app.regions)
                return;
            end

            [h, w, ~] = size(app.currentImg);
            overlay = zeros(h, w, 3, 'uint8');

            for i = 1:numel(app.regions)
                if isKey(app.classCfg.colors, app.regions{i}.label)
                    c = app.classCfg.colors(app.regions{i}.label);
                else
                    c = [1 1 0];
                end
                c = uint8(255 * c);
                mask = app.regions{i}.mask;
                for ch = 1:3
                    chOverlay = overlay(:,:,ch);
                    chOverlay(mask) = c(ch);
                    overlay(:,:,ch) = chOverlay;
                end
            end

            alphaMatrix = zeros(h, w);
            for i = 1:numel(app.regions)
                alphaMatrix(app.regions{i}.mask) = 0.4;
            end

            hold(app.UIAxes, 'on');
            hImg = imshow(overlay, 'Parent', app.UIAxes);
            set(hImg, 'AlphaData', alphaMatrix);
            hold(app.UIAxes, 'off');
            app.overlayHandle = hImg;
            drawnow;
        end

        function updateInfoPanel(app)
            n = numel(app.regions);
            app.RegionCountLabel.Text = sprintf('Regions: %d', n);

            items = cell(1, n);
            for i = 1:n
                areaPx = sum(app.regions{i}.mask(:));
                totalPx = numel(app.regions{i}.mask);
                pct = 100 * areaPx / totalPx;
                items{i} = sprintf('%s - %.1f%%', char(app.regions{i}.label), pct);
            end
            app.RegionList.Items = items;

            if n == 0
                app.AreaStatsLabel.Text = 'Area Stats:';
            else
                stats = cell(1, n + 1);
                stats{1} = 'Area Stats:';
                for i = 1:n
                    areaPx = sum(app.regions{i}.mask(:));
                    totalPx = numel(app.regions{i}.mask);
                    pct = 100 * areaPx / totalPx;
                    stats{i + 1} = sprintf('  %s: %d px (%.1f%%)', ...
                        char(app.regions{i}.label), areaPx, pct);
                end
                app.AreaStatsLabel.Text = strjoin(stats, newline);
            end

            app.updateMaskPreview();
            app.updateButtonStates();
            app.updateStatusBar();
        end

        function updateMaskPreview(app)
            cla(app.MaskPreviewAxes);
            if isempty(app.regions) || isempty(app.currentImg)
                return;
            end

            [h, w, ~] = size(app.currentImg);
            combined = zeros(h, w, 'uint8');
            for i = 1:numel(app.regions)
                if isKey(app.classCfg.classIds, app.regions{i}.label)
                    id = app.classCfg.classIds(app.regions{i}.label);
                    combined(app.regions{i}.mask) = id;
                end
            end

            imagesc(app.MaskPreviewAxes, combined);
            axis(app.MaskPreviewAxes, 'equal');
            colormap(app.MaskPreviewAxes, app.classCfg.colormap);
            clim(app.MaskPreviewAxes, [0 app.classCfg.numClasses]);
            app.MaskPreviewAxes.XTick = [];
            app.MaskPreviewAxes.YTick = [];
            title(app.MaskPreviewAxes, 'Mask Preview');
        end

        function updateButtonStates(app)
            hasImg = ~isempty(app.currentImg);
            app.StartAnnotationButton.Enable = hasImg;
            app.DeleteRegionButton.Enable = hasImg && app.selectedRegion > 0;
            app.UndoButton.Enable = hasImg && ~undoStack('isEmpty', app.undoHistory);
            app.RedoButton.Enable = hasImg && ~undoStack('isEmpty', app.redoHistory);
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
                    ternary(app.dirty, 'Unsaved', 'Saved'));
            else
                app.StatusBar.Text = sprintf('%s | %d/%d | %d regions | %s', ...
                    app.getCurrentFilename(), app.currentIdx, numel(app.imageList), ...
                    numel(app.regions), ternary(app.dirty, 'Unsaved', 'Saved'));
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

        % ================================================================
        %  Tag Management
        % ================================================================

        function manageTags(app)
            configPath = fullfile(fileparts(mfilename('fullpath')), 'tag_config.json');

            dlg = uifigure('Name', 'Manage Tags', ...
                'Position', [300 300 420 380], ...
                'Resize', 'off', ...
                'WindowStyle', 'modal', ...
                'Color', [0.15 0.15 0.15]);

            grid = uigridlayout(dlg, [4 3]);
            grid.BackgroundColor = [0.15 0.15 0.15];
            grid.RowHeight = {25, '1x', 25, 25};
            grid.ColumnWidth = {'1x', 70, 70};
            grid.Padding = [8 8 8 8];
            grid.RowSpacing = 6;
            grid.ColumnSpacing = 6;

            lbl = uilabel(grid, 'Text', 'Tags:', ...
                'FontWeight', 'bold', 'HorizontalAlignment', 'left', ...
                'FontColor', [1 1 1]);
            lbl.Layout.Row = 1;
            lbl.Layout.Column = 1;

            tagList = uilistbox(grid, ...
                'Items', app.classCfg.classes, ...
                'Value', app.classCfg.classes{1});
            tagList.Layout.Row = 2;
            tagList.Layout.Column = [1 3];
            tagList.BackgroundColor = [0.2 0.2 0.2];
            tagList.FontColor = [1 1 1];

            btnBG = [0.2 0.2 0.2];
            btnFG = [1 1 1];

            addBtn = uibutton(grid, 'push', ...
                'Text', 'Add', ...
                'BackgroundColor', btnBG, 'FontColor', btnFG, ...
                'ButtonPushedFcn', @(~,~) addTag());
            addBtn.Layout.Row = 3;
            addBtn.Layout.Column = 1;

            editBtn = uibutton(grid, 'push', ...
                'Text', 'Edit', ...
                'BackgroundColor', btnBG, 'FontColor', btnFG, ...
                'ButtonPushedFcn', @(~,~) editTag());
            editBtn.Layout.Row = 3;
            editBtn.Layout.Column = 2;

            deleteBtn = uibutton(grid, 'push', ...
                'Text', 'Delete', ...
                'BackgroundColor', btnBG, 'FontColor', btnFG, ...
                'ButtonPushedFcn', @(~,~) deleteTag());
            deleteBtn.Layout.Row = 3;
            deleteBtn.Layout.Column = 3;

            resetBtn = uibutton(grid, 'push', ...
                'Text', 'Reset to Defaults', ...
                'BackgroundColor', btnBG, 'FontColor', btnFG, ...
                'ButtonPushedFcn', @(~,~) resetTags());
            resetBtn.Layout.Row = 4;
            resetBtn.Layout.Column = 1;

            closeBtn = uibutton(grid, 'push', ...
                'Text', 'Close', ...
                'BackgroundColor', btnBG, 'FontColor', btnFG, ...
                'ButtonPushedFcn', @(~,~) delete(dlg));
            closeBtn.Layout.Row = 4;
            closeBtn.Layout.Column = 3;

            function addTag()
                name = inputName();
                if isempty(name), return; end
                if any(strcmp(app.classCfg.classes, name))
                    uialert(dlg, ['Tag "' name '" already exists.'], 'Duplicate');
                    return;
                end
                c = uisetcolor([1 1 0], 'Choose tag color');
                if isequal(c, 0), return; end
                app.classCfg.classes{end+1} = name;
                app.classCfg.colors(name) = c;
                classConfig(app.classCfg);
                refreshTagUI(app);
                tagList.Items = app.classCfg.classes;
                tagList.Value = name;
            end

            function editTag()
                oldName = tagList.Value;
                newName = inputName(oldName);
                if isempty(newName), return; end
                if ~strcmp(newName, oldName) && any(strcmp(app.classCfg.classes, newName))
                    uialert(dlg, ['Tag "' newName '" already exists.'], 'Duplicate');
                    return;
                end
                oldColor = app.classCfg.colors(oldName);
                c = uisetcolor(oldColor, ['Choose color for "' newName '"']);
                if isequal(c, 0), return; end
                idx = find(strcmp(app.classCfg.classes, oldName));
                app.classCfg.classes{idx} = newName;
                app.classCfg.colors(newName) = c;
                if ~strcmp(newName, oldName)
                    remove(app.classCfg.colors, oldName);
                    for ri = 1:numel(app.regions)
                        if strcmp(app.regions{ri}.label, oldName)
                            app.regions{ri}.label = newName;
                        end
                    end
                    app.dirty = true;
                end
                app.classCfg = rebuildClassCfg(app.classCfg);
                classConfig(app.classCfg);
                refreshTagUI(app);
                tagList.Items = app.classCfg.classes;
                tagList.Value = newName;
            end

            function deleteTag()
                name = tagList.Value;
                if numel(app.classCfg.classes) <= 1
                    uialert(dlg, 'Must have at least one tag.', 'Cannot Delete');
                    return;
                end
                choice = uiconfirm(dlg, ...
                    ['Delete tag "' name '"? Regions using this tag will keep ' ...
                     'their labels but will not display until recreated.'], ...
                    'Delete Tag', 'Options', {'Delete', 'Cancel'}, ...
                    'DefaultOption', 2, 'CancelOption', 2);
                if ~strcmp(choice, 'Delete'), return; end
                idx = find(strcmp(app.classCfg.classes, name));
                app.classCfg.classes(idx) = [];
                remove(app.classCfg.colors, name);
                app.classCfg = rebuildClassCfg(app.classCfg);
                classConfig(app.classCfg);
                refreshTagUI(app);
                tagList.Items = app.classCfg.classes;
                tagList.Value = app.classCfg.classes{1};
            end

            function resetTags()
                choice = uiconfirm(dlg, ...
                    'Reset all tags to defaults? Custom tags will be lost.', ...
                    'Reset Tags', 'Options', {'Reset', 'Cancel'}, ...
                    'DefaultOption', 2, 'CancelOption', 2);
                if ~strcmp(choice, 'Reset'), return; end
                delete(configPath);
                app.classCfg = classConfig();
                refreshTagUI(app);
                tagList.Items = app.classCfg.classes;
                tagList.Value = app.classCfg.classes{1};
            end

            function name = inputName(current)
                if nargin < 1, current = ''; end
                prompt = uifigure('Name', 'Tag Name', ...
                    'Position', [400 400 280 110], ...
                    'Resize', 'off', 'WindowStyle', 'modal', ...
                    'Color', [0.15 0.15 0.15]);
                pg = uigridlayout(prompt, [3 1]);
                pg.BackgroundColor = [0.15 0.15 0.15];
                pg.RowHeight = {22, 22, 22};
                pg.Padding = [8 8 8 8];
                pg.RowSpacing = 6;
                lbl = uilabel(pg, 'Text', 'Enter tag name:', ...
                    'HorizontalAlignment', 'left');
                lbl.FontColor = [1 1 1];
                field = uieditfield(pg, 'Value', current);
                btnRow = uigridlayout(pg, [1 2]);
                btnRow.BackgroundColor = [0.15 0.15 0.15];
                btnRow.ColumnWidth = {'1x', '1x'};
                btnRow.Padding = [0 0 0 0];
                btnRow.ColumnSpacing = 6;
                result = '';
                ok = false;
                okBtn = uibutton(btnRow, 'push', 'Text', 'OK', ...
                    'ButtonPushedFcn', @(~,~) commit());
                okBtn.BackgroundColor = [0.2 0.2 0.2];
                okBtn.FontColor = [1 1 1];
                cancelBtn = uibutton(btnRow, 'push', 'Text', 'Cancel', ...
                    'ButtonPushedFcn', @(~,~) delete(prompt));
                cancelBtn.BackgroundColor = [0.2 0.2 0.2];
                cancelBtn.FontColor = [1 1 1];
                uiwait(prompt);
                if ok
                    name = result;
                else
                    name = [];
                end
                function commit()
                    result = strtrim(field.Value);
                    ok = true;
                    delete(prompt);
                end
            end
        end

        function refreshTagUI(app)
            app.classCfg = classConfig();
            app.ClassDropdown.Items = app.classCfg.classes;
            app.ClassDropdown.Value = app.classCfg.classes{1};
            app.currentClass = app.classCfg.classes{1};
            app.ReclassifyDropdown.Items = app.classCfg.classes;
            app.ReclassifyDropdown.Value = app.classCfg.classes{1};
            if ~isempty(app.currentImg)
                app.updateOverlay();
                app.updateMaskPreview();
            end
        end

        % ================================================================
        %  Save / Export
        % ================================================================

        function autoSave(app)
            if isempty(app.currentImg)
                return;
            end
            app.saveCurrent();
        end

        function saveCurrent(app)
            if isempty(app.currentImg) || app.currentIdx < 1
                return;
            end
            [~, name, ext] = fileparts(app.imageList{app.currentIdx});

            maskPath = fullfile(app.imageDir, [name '_mask.png']);
            jsonPath = fullfile(app.imageDir, [name '_meta.json']);

            try
                imgSize = size(app.currentImg);
                imgSize = imgSize(1:2);
                exportMask(app.regions, imgSize, maskPath);
                exportJson([name ext], imgSize, app.regions, jsonPath);
                app.dirty = false;
                app.StatusBar.Text = sprintf('Saved %s_mask.png, %s_meta.json', name, name);
                app.updateStatusBar();
            catch ME
                app.StatusBar.Text = ['Save error: ' ME.message];
            end
        end

        function exportAll(app)
            if isempty(app.imageDir)
                uialert(app.UIFigure, 'No image folder loaded.', 'Export Error');
                return;
            end

            [indx, tf] = listdlg('PromptString', 'Select export formats:', ...
                'SelectionMode', 'multiple', ...
                'ListString', {'Mask PNG', 'JSON', 'LabelMe XML'}, ...
                'Name', 'Export', 'ListSize', [200 100]);
            if tf == 0
                return;
            end
            if isempty(indx)
                uialert(app.UIFigure, 'Select at least one export format.', 'Export');
                return;
            end

            metaFiles = dir(fullfile(app.imageDir, '*_meta.json'));
            if isempty(metaFiles)
                uialert(app.UIFigure, 'No annotations found to export.', 'Export');
                return;
            end

            choice = uiconfirm(app.UIFigure, ...
                'Existing export files will be overwritten. Continue?', ...
                'Export', 'Options', {'Continue', 'Cancel'}, ...
                'DefaultOption', 1, 'CancelOption', 2);
            if strcmp(choice, 'Cancel')
                return;
            end

            doMask = ismember(1, indx);
            doJson = ismember(2, indx);
            doXml  = ismember(3, indx);

            count = 0;
            for i = 1:numel(metaFiles)
                jsonPath = fullfile(app.imageDir, metaFiles(i).name);
                try
                    txt = fileread(jsonPath);
                    data = jsondecode(txt);
                    regions = normalizeRegions(data.regions);

                    if doMask
                        combined = zeros(data.height, data.width, 'uint8');
                        for j = 1:numel(regions)
                            pts = regions{j}.points;
                            if size(pts, 1) >= 3
                                roi = images.roi.Polygon('Position', pts);
                                m = createMask(roi, data.height, data.width);
                                if isKey(app.classCfg.classIds, regions{j}.label)
                                    combined(m) = app.classCfg.classIds(regions{j}.label);
                                end
                                delete(roi);
                            end
                        end
                        maskPath = strrep(jsonPath, '_meta.json', '_mask.png');
                        imwrite(combined, maskPath);
                    end

                    if doJson
                        regionsForJson = cell(1, numel(regions));
                        for j = 1:numel(regions)
                            pts = regions{j}.points;
                            if size(pts, 1) >= 3
                                roi = images.roi.Polygon('Position', pts);
                                m = createMask(roi, data.height, data.width);
                                regionsForJson{j} = struct(...
                                    'label',  regions{j}.label, ...
                                    'points', pts, 'mask', m);
                                delete(roi);
                            end
                        end
                        exportJson(data.image, [data.height data.width], ...
                            regionsForJson, jsonPath);
                    end

                    if doXml
                        [~, name] = fileparts(strrep(metaFiles(i).name, '_meta', ''));
                        xmlPath = fullfile(app.imageDir, [name '.xml']);
                        exportLabelMe(data.image, [data.height data.width], ...
                            regions, xmlPath);
                    end

                    count = count + 1;
                catch ME
                    warning('Export failed for %s: %s', metaFiles(i).name, ME.message);
                end
            end

            app.StatusBar.Text = sprintf('Exported %d annotated images.', count);
            uialert(app.UIFigure, ...
                sprintf('Exported %d annotated images.', count), ...
                'Export Complete');
        end

        % ================================================================
        %  Input Handling
        % ================================================================

        function onClassChanged(app)
            app.currentClass = app.ClassDropdown.Value;
        end

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

        % ================================================================
        %  Timer Helpers
        % ================================================================

        function ensureTimer(app)
            if isempty(app.saveTimer) || ~isvalid(app.saveTimer)
                app.saveTimer = timer('ExecutionMode', 'singleShot', ...
                    'StartDelay', 0.5, 'TimerFcn', @(~,~) autoSave(app));
            end
        end

        function stopTimer(app)
            if ~isempty(app.saveTimer) && isvalid(app.saveTimer)
                stop(app.saveTimer);
            end
        end

        function deleteTimer(app)
            if ~isempty(app.saveTimer) && isvalid(app.saveTimer)
                stop(app.saveTimer);
                delete(app.saveTimer);
            end
        end

        % ================================================================
        %  Utility
        % ================================================================

        function idx = findRegionByRoi(app, roi)
            idx = 0;
            for i = 1:numel(app.regions)
                if app.regions{i}.roi == roi
                    idx = i;
                    return;
                end
            end
        end

    end

end

% ===================================================================
%  Local Helper Functions
% ===================================================================

function out = ternary(cond, t, f)
    if cond
        out = t;
    else
        out = f;
    end
end

function regions = normalizeRegions(regions)
    % normalizeRegions  Ensure regions is always a cell array.
    %   jsondecode may return a struct array for a single region,
    %   or a cell array for multiple. This normalizes both to cell.
    if isstruct(regions)
        regions = num2cell(regions);
    end
    if isempty(regions)
        regions = {};
    end
end

function img = prepareForDisplay(img)
    % If double with values > 1, assume it was uint8 mis-cast.
    if isa(img, 'double') && max(img(:)) > 1
        img = uint8(img);
    end
end

function cfg = rebuildClassCfg(cfg)
    % Rebuild classIds and colormap from classes and colors.
    n = numel(cfg.classes);
    cfg.classIds = containers.Map('KeyType', 'char', 'ValueType', 'double');
    cfg.colormap = zeros(n + 1, 3);
    for i = 1:n
        label = cfg.classes{i};
        cfg.classIds(label) = i;
        if isKey(cfg.colors, label)
            cfg.colormap(i + 1, :) = cfg.colors(label);
        end
    end
    cfg.numClasses = n;
end
