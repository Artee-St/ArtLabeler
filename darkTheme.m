function darkTheme(app)
    % darkTheme  Apply dark color scheme to ArtLabeler UI components.
    %
    %   darkTheme(app) sets background colors, font colors, and
    %   component styling for the ArtLabeler application figure.

    BG  = [0.15 0.15 0.15];
    FG  = [0.2  0.2  0.2];
    TXT = [1 1 1];
    SBG = [0.1  0.1  0.1];

    app.UIFigure.Color = BG;

    panels = {'LeftPanel', 'CenterPanel', 'RightPanel'};
    for i = 1:numel(panels)
        if isprop(app, panels{i})
            app.(panels{i}).BackgroundColor = BG;
        end
    end

    btnNames = {'LoadImageButton', 'LoadFolderButton', ...
        'StartAnnotationButton', 'DeleteRegionButton', ...
        'UndoButton', 'RedoButton', 'PrevButton', ...
        'NextButton', 'SaveButton', 'ExportButton', 'ManageTagsButton'};
    for i = 1:numel(btnNames)
        if isprop(app, btnNames{i}) && isvalid(app.(btnNames{i}))
            app.(btnNames{i}).BackgroundColor = FG;
            app.(btnNames{i}).FontColor = TXT;
        end
    end

    dropdowns = {'ClassDropdown', 'ReclassifyDropdown', 'RegionList'};
    for i = 1:numel(dropdowns)
        if isprop(app, dropdowns{i}) && isvalid(app.(dropdowns{i}))
            app.(dropdowns{i}).BackgroundColor = FG;
            app.(dropdowns{i}).FontColor = TXT;
        end
    end

    if isprop(app, 'StatusBar') && isvalid(app.StatusBar)
        app.StatusBar.BackgroundColor = SBG;
        app.StatusBar.FontColor = TXT;
    end

    allLabels = findobj(app.UIFigure, 'Type', 'uilabel');
    for i = 1:numel(allLabels)
        allLabels(i).FontColor = TXT;
    end

    if isprop(app, 'UIAxes') && isvalid(app.UIAxes)
        app.UIAxes.Color = BG;
    end
    if isprop(app, 'MaskPreviewAxes') && isvalid(app.MaskPreviewAxes)
        app.MaskPreviewAxes.Color = BG;
    end
end
