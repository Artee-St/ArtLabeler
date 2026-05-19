function varargout = undoStack(action, varargin)
    % undoStack('create', maxDepth) → stack struct
    % undoStack('push',   stack, data) → stack
    % undoStack('pop',    stack) → [stack, data]
    % undoStack('clear',  stack) → empty stack
    % undoStack('isEmpty', stack) → logical

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
    end
end

function copy = deepCopyRegions(data)
    if isempty(data)
        copy = {};
        return;
    end
    copy = cell(size(data));
    for i = 1:numel(data)
        r = data{i};
        copy{i} = struct(...
            'points', r.points, ...
            'label', r.label, ...
            'mask', r.mask, ...
            'roi', []);  % roi handles not copied (axes-specific)
    end
end
