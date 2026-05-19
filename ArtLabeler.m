classdef ArtLabeler < matlab.apps.AppBase

    properties (Access = public)
        % UI components
        UIFigure
        LeftPanel
        CenterPanel
        RightPanel
        UIAxes
        MaskPreviewAxes
        LoadImageButton
        LoadFolderButton
        StartAnnotationButton
        DeleteRegionButton
        UndoButton
        RedoButton
        PrevButton
        NextButton
        SaveButton
        ExportButton
        ClassDropdown
        ReclassifyDropdown
        RegionList
        RegionCountLabel
        AreaStatsLabel
        StatusBar

        % Data
        regions        = {}
        imageList      = {}
        currentIdx     = 0
        currentImg     = []
        currentClass   = 'person'
        undoStack      struct
        redoStack      struct
        isDrawing      = false
        dirty          = false
        selectedRegion = 0
        saveDebounceTimer = []
        imageDir       = ''
    end

    methods (Access = public)

        function app = ArtLabeler()
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
            app.UIFigure = uifigure('Name', 'ArtLabeler', ...
                'Position', [100 100 1280 720], ...
                'CloseRequestFcn', @(~,~) onClose(app));

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

            uilabel(leftGrid, 'Text', '', 'HorizontalAlignment', 'center').Layout.Row = 9;

            app.PrevButton = uibutton(leftGrid, 'push', ...
                'Text', [char(9664) ' Previous'], ...
                'ButtonPushedFcn', @(~,~) prevImage(app));
            app.PrevButton.Layout.Row = 10;

            app.NextButton = uibutton(leftGrid, 'push', ...
                'Text', ['Next ' char(9654)], ...
                'ButtonPushedFcn', @(~,~) nextImage(app));
            app.NextButton.Layout.Row = 11;

            uilabel(leftGrid, 'Text', '', 'HorizontalAlignment', 'center').Layout.Row = 12;

            app.SaveButton = uibutton(leftGrid, 'push', ...
                'Text', 'Save', ...
                'ButtonPushedFcn', @(~,~) saveCurrent(app));
            app.SaveButton.Layout.Row = 13;

            app.ExportButton = uibutton(leftGrid, 'push', ...
                'Text', 'Export', ...
                'ButtonPushedFcn', @(~,~) exportAll(app));
            app.ExportButton.Layout.Row = 14;

            % Center panel
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

        function onClassChanged(app)
            app.currentClass = app.ClassDropdown.Value;
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
                    getCurrentFilename(app), numel(app.regions), ...
                    conditional(app.dirty, 'Unsaved', 'Saved'));
            else
                app.StatusBar.Text = sprintf('%s | %d/%d | %d regions | %s', ...
                    getCurrentFilename(app), app.currentIdx, numel(app.imageList), ...
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

        function loadImage(app)
            [filename, pathname] = uigetfile({'*.jpg;*.png;*.bmp', 'Image Files (*.jpg,*.png,*.bmp)'});
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

            imshow(app.currentImg, 'Parent', app.UIAxes);
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
                uialert(app.UIFigure, 'No supported images found in this folder.', 'Empty Folder');
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
        function startAnnotation(app)
            if isempty(app.currentImg)
                app.StatusBar.Text = 'Load an image first.';
                return;
            end
            if app.isDrawing
                app.StatusBar.Text = 'Already drawing — double-click to finish current polygon.';
                return;
            end
            if app.selectedRegion > 0
                app.deselectRegion();
            end

            app.isDrawing = true;
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
        function deleteRegion(app), end
        function undoAction(app), end
        function redoAction(app), end
        function prevImage(app), end
        function nextImage(app), end
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
                sprintf('Exported %d annotated images.', count), ...
                'Export Complete');
        end
        function reclassifyRegion(app), end
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
            if ~isempty(app.saveDebounceTimer) && isvalid(app.saveDebounceTimer)
                stop(app.saveDebounceTimer);
                delete(app.saveDebounceTimer);
            end
            for i = 1:numel(app.regions)
                if ~isempty(app.regions{i}.roi) && isvalid(app.regions{i}.roi)
                    delete(app.regions{i}.roi);
                end
            end
            delete(app.UIFigure);
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
            imshow(app.currentImg, 'Parent', app.UIAxes);
            app.updateButtonStates();
            app.updateStatusBar();
            app.updateInfoPanel();
            app.loadAnnotations();
        end

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
                app.StatusBar.Text = ['Warning: Could not load annotations - ' ME.message];
            end
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
                app.AreaStatsLabel.Text = 'Area Stats: -';
            else
                stats = cell(1, n+1);
                stats{1} = 'Area Stats:';
                for i = 1:n
                    areaPx = sum(app.regions{i}.mask(:));
                    totalPx = numel(app.regions{i}.mask);
                    pct = 100 * areaPx / totalPx;
                    stats{i+1} = sprintf('  %s: %d px (%.1f%%)', ...
                        char(app.regions{i}.label), areaPx, pct);
                end
                app.AreaStatsLabel.Text = strjoin(stats, newline);
            end

            app.updateMaskPreview();
            app.updateButtonStates();
            app.updateStatusBar();
        end

        function updateOverlay(app)
            existing = findobj(app.UIAxes, 'Type', 'Image');
            if numel(existing) > 1
                delete(existing(2:end));
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

        function autoSave(app)
            if isempty(app.currentImg)
                return;
            end
            app.saveCurrent();
        end

        function pushUndo(app)
            app.redoStack = undoStack('clear', app.redoStack);
            app.undoStack = undoStack('push', app.undoStack, app.regions);
        end

    end

end

function out = conditional(cond, t, f)
    if cond, out = t; else, out = f; end
end
