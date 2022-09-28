function animate(h, x, kwargs)
% ANIMATE - Animate imagesc data
%
% ANIMATE(h, x) animates the multi-dimensional data x by looping through
% the upper dimensions and iteratively updating the image handle h. The
% data will be plotted until the figure is closed.
%
% If h is an array of image handles and x is a corresponding cell array of
% image data, each image h(i) will be updated by the data x{i}.
%
% ANIMATE(..., 'loop', false) plays through the animation once, rather than
% looping until the figure is closed.
%
% ANIMATE(..., 'fs', fs) updates the image at a rate fs.
% 
% Note: MATLAB execution will be paused while the animation is playing.
% Close the figure or press 'ctrl + c' in the command window to stop the
% animation.
%
% Example:
% % Simulate some data
% us = UltrasoundSystem(); % get a default system
% us.fs = single(us.fs); % use single precision for speed
% us.sequence = SequenceRadial('type', 'PW', 'angles', -21:0.5:21);
% scat = Scatterers('pos', [0;0;30e-3], 'c0', us.sequence.c0); % define a point target
% chd = greens(us, scat); % simulate the ChannelData
% 
% % Configure the image of the Channel Data
% figure;
% chd_im = mod2db(chd);
% nexttile();
% h = imagesc(chd_im); % initialize the image
% caxis(max(caxis) + [-60 0]); % 60 dB dynamic range
% colorbar;
% title('Channel Data per Transmit');
% 
% % Animate the data across transmits 
% animate(h, chd_im.data, 'loop', false); % show once
%
% % Beamform the data
% b = DAS(us, chd, 'keep_tx', true); % B-mode image
% bim = mod2db(b); % log-compression / envelope detection
% 
% % Initialize the B-mode image
% nexttile();
% h(2) = imagesc(us.scan, bim(:,:,1)); % show the first image
% colormap(h(2).Parent, 'gray');
% caxis(max(caxis) + [-60 0]); % 60 dB dynamic range
% colorbar;
% title('B-mode per Transmit');
%  
% % Animate both images across transmits
% animate(h, {chd_im.data, bim}, 'loop', false); % show once
% 
% See also IMAGESC
arguments
    h (1,:) matlab.graphics.primitive.Image
    x {mustBeA(x, ["cell","gpuArray","double","single","logical","int64","int32","int16","int8","uint64","uint32","uint16","uint8"])} = 1 % data
    kwargs.fs (1,1) {mustBePositive} = 20; % refresh rate (hertz)
    kwargs.loop (1,1) logical = true; % loop until cancelled
end

% place data in a cell if it isn't already
if isnumeric(x) || islogical(x), x = {x}; end

% argument type checks - x must contain data that can be plotted
cellfun(@mustBeReal, x);

% Get sizing info
I = numel(h);
Mi = cellfun(@(x) prod(size(x,3:max(3,ndims(x)))), x); % upper dimension sizing
M = unique(Mi);

% validity checks
assert(isscalar(M), "The number of images must be the same for all images (" + (Mi + ",") + ").");
assert(numel(h) == numel(x), "The number of image handles (" ...
    + numel(h) + ...
    ") must match the number of images (" ...
    + numel(x) + ")." ...
    );

while(all(isvalid(h)))
    for m = 1:M
        if ~all(isvalid(h)), break; end
        for i = 1:I, h(i).CData(:) = x{i}(:,:,m); end % update image
        drawnow limitrate;
        pause(1/kwargs.fs);
    end
    if ~kwargs.loop, break; end
end

end