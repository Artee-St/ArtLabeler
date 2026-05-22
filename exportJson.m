function exportJson(filename, imageSize, regions, filepath)
    % exportJson  Write annotation metadata as JSON.
    %
    %   exportJson(filename, imageSize, regions, filepath)
    %
    %   filename:  source image filename (e.g. '001.jpg')
    %   imageSize: [height, width]
    %   regions:   cell array of region structs
    %   filepath:  full output path for JSON

    data.image  = filename;
    data.width  = imageSize(2);
    data.height = imageSize(1);

    n = numel(regions);
    totalPx = imageSize(1) * imageSize(2);
    regionsOut = cell(1, n);

    for i = 1:n
        r = regions{i};
        areaPx = sum(r.mask(:));

        maskFilename = strrep(filename, '.', '_mask_');
        maskFilename = [maskFilename num2str(i) '.png'];

        regionsOut{i} = struct(...
            'label',       r.label, ...
            'mask',        maskFilename, ...
            'area',        areaPx, ...
            'areaPercent', round(10000 * areaPx / totalPx) / 100, ...
            'points',      r.points);
    end

    data.regions = regionsOut;

    jsonStr = jsonencode(data);
    fid = fopen(filepath, 'w');
    if fid == -1
        error('exportJson:cannotOpen', 'Cannot open %s for writing.', filepath);
    end
    fprintf(fid, '%s', jsonStr);
    fclose(fid);
end
