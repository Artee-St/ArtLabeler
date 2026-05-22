function exportLabelMe(filename, imageSize, regions, filepath)
    % exportLabelMe  Write LabelMe-compatible XML annotation.
    %
    %   exportLabelMe(filename, imageSize, regions, filepath)
    %
    %   filename:  source image filename
    %   imageSize: [height, width]
    %   regions:   cell array or struct array of region entries
    %   filepath:  full output path for XML

    fid = fopen(filepath, 'w');
    if fid == -1
        error('exportLabelMe:cannotOpen', 'Cannot open %s for writing.', filepath);
    end

    fprintf(fid, '<annotation>\n');
    fprintf(fid, '  <filename>%s</filename>\n', filename);
    fprintf(fid, '  <folder>%s</folder>\n', fileparts(filepath));
    fprintf(fid, '  <source><annotation>ArtLabeler</annotation></source>\n');
    fprintf(fid, '  <imagesize><nrows>%d</nrows><ncols>%d</ncols></imagesize>\n', ...
        imageSize(1), imageSize(2));

    if isstruct(regions) && ~iscell(regions)
        regions = num2cell(regions);
    end

    for i = 1:numel(regions)
        r = regions{i};
        fprintf(fid, '  <object>\n');
        fprintf(fid, '    <name>%s</name>\n', r.label);
        fprintf(fid, '    <deleted>0</deleted>\n');
        fprintf(fid, '    <verified>0</verified>\n');
        fprintf(fid, '    <polygon>\n');
        pts = r.points;
        for j = 1:size(pts, 1)
            fprintf(fid, '      <pt><x>%d</x><y>%d</y></pt>\n', round(pts(j,1)), round(pts(j,2)));
        end
        fprintf(fid, '    </polygon>\n');
        fprintf(fid, '  </object>\n');
    end

    fprintf(fid, '</annotation>\n');
    fclose(fid);
end
