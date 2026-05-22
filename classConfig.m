function varargout = classConfig(varargin)
    % classConfig  Shared class configuration for ArtLabeler.
    %   cfg = classConfig()        Load current tag configuration.
    %   classConfig(cfg)           Save tag configuration (classes + colors).
    %
    %   The config persists to tag_config.json alongside this file.
    %   On first run, default tags are created automatically.

    configDir = fileparts(mfilename('fullpath'));
    configPath = fullfile(configDir, 'tag_config.json');

    if nargin == 0
        if isfile(configPath)
            saved = readConfig(configPath);
        else
            saved = defaultConfig();
            writeConfig(configPath, saved);
        end
        varargout = {buildCfg(saved)};
    else
        cfg = varargin{1};
        saved.classes = cfg.classes;
        saved.colors = cell(1, numel(cfg.classes));
        for i = 1:numel(cfg.classes)
            label = cfg.classes{i};
            if isKey(cfg.colors, label)
                saved.colors{i} = cfg.colors(label);
            else
                saved.colors{i} = [1 1 0];
            end
        end
        writeConfig(configPath, saved);
    end
end

function saved = defaultConfig()
    saved.classes = {'person', 'building', 'sky', 'plant'};
    saved.colors = {[1 0 0], [0 0 1], [0.5 0.8 1], [0 0.6 0]};
end

function saved = readConfig(path)
    raw = jsondecode(fileread(path));
    saved.classes = raw.classes;
    saved.colors = raw.colors;
end

function writeConfig(path, saved)
    s.classes = saved.classes;
    s.colors = saved.colors;
    fid = fopen(path, 'w');
    if fid == -1
        error('classConfig:cannotWrite', 'Cannot write %s.', path);
    end
    fprintf(fid, '%s', jsonencode(s));
    fclose(fid);
end

function cfg = buildCfg(saved)
    cfg.classes = saved.classes;
    n = numel(saved.classes);
    cfg.classIds = containers.Map('KeyType', 'char', 'ValueType', 'double');
    cfg.colors = containers.Map('KeyType', 'char', 'ValueType', 'any');
    cfg.colormap = zeros(n + 1, 3);
    for i = 1:n
        label = saved.classes{i};
        cfg.classIds(label) = i;
        cfg.colors(label) = saved.colors{i};
        cfg.colormap(i + 1, :) = saved.colors{i};
    end
    cfg.numClasses = n;
end
