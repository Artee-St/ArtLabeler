function varargout = undoStack(action, varargin)
    % undoStack  Undo/redo stack for region annotation data.
    %
    %   stack = undoStack('create', maxDepth)
    %   stack = undoStack('push',   stack, data)
    %   [stack, data] = undoStack('pop', stack)
    %   stack = undoStack('clear',  stack)
    %   tf = undoStack('isEmpty',   stack)
    %
    %   Internal: stack is a struct with fields .entries, .depth, .top.

    switch action
        case 'create'
            maxDepth = varargin{1};
            stack = struct('entries', {{}}, 'depth', maxDepth, 'top', 0);
            varargout = {stack};

        case 'push'
            stack = varargin{1};
            data = varargin{2};
            stack.top = stack.top + 1;
            if stack.top > stack.depth
                stack.entries(1) = [];
                stack.top = stack.depth;
            end
            stack.entries{stack.top} = deepCopyRegions(data);
            varargout = {stack};

        case 'pop'
            stack = varargin{1};
            if stack.top == 0
                varargout = {stack, []};
            else
                data = stack.entries{stack.top};
                stack.entries(stack.top) = [];
                stack.top = stack.top - 1;
                varargout = {stack, data};
            end

        case 'clear'
            varargout = {undoStack('create', varargin{1}.depth)};

        case 'isEmpty'
            varargout = {varargin{1}.top == 0};

        otherwise
            error('undoStack:unknownAction', ...
                'Unknown action: %s. Valid: create, push, pop, clear, isEmpty.', action);
    end
end

function copy = deepCopyRegions(regions)
    % Deep-copy region cell array, stripping roi handles (axes-specific).
    % Non-cell inputs are returned as-is (no deep copy needed).
    if ~iscell(regions)
        copy = regions;
        return;
    end
    if isempty(regions)
        copy = {};
        return;
    end
    n = numel(regions);
    copy = cell(1, n);
    for i = 1:n
        r = regions{i};
        copy{i} = struct(...
            'points', r.points, ...
            'label',  r.label, ...
            'mask',   r.mask, ...
            'roi',    []);
    end
end
