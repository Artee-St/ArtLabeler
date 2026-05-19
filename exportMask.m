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
