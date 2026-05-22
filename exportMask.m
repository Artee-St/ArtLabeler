function exportMask(regions, imageSize, filepath)
    % exportMask  Generate indexed label PNG from annotated regions.
    %
    %   exportMask(regions, imageSize, filepath)
    %
    %   regions:   cell array of region structs (each has .label, .mask)
    %   imageSize: [height, width] of source image
    %   filepath:  full output path for the mask PNG

    cfg = classConfig();

    combined = zeros(imageSize, 'uint8');
    for i = 1:numel(regions)
        r = regions{i};
        if isKey(cfg.classIds, r.label)
            combined(r.mask) = cfg.classIds(r.label);
        end
    end

    imwrite(combined, filepath);
end
