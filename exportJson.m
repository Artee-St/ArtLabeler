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
