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

        function loadImage(app), end
        function loadFolder(app), end
        function startAnnotation(app), end
        function deleteRegion(app), end
        function undoAction(app), end
        function redoAction(app), end
        function prevImage(app), end
        function nextImage(app), end
        function saveCurrent(app), end
        function exportAll(app), end
        function reclassifyRegion(app), end
        function onRegionSelected(app), end
        function onClose(app), end

    end

end

function out = conditional(cond, t, f)
    if cond, out = t; else, out = f; end
end
