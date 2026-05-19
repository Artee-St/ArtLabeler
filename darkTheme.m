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
