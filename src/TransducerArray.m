% TRANSDUCERARRAY - Linear Array Transducer class
% 
% A TransducerArray defines a linear transducer where all elements lie on a
% line.
% 
% See also TRANSDUCER TRANSDUCERCONVEX TRANSDUCERMATRIX

classdef TransducerArray < Transducer

    properties
        pitch               % the interelement distance
    end
    
    properties(Dependent)
        kerf                % the spacing between elements
        aperture_size       % width of the full aperture
    end
    
    % constructor 
    methods(Access=public)
        function xdc = TransducerArray(array_args, xdc_args)
            % TRANSDUCERARRAY - TransducerArray constructor
            %
            % xdc = TRANSDUCERARRAY(Name, Value, ...) constructs a
            % TransducerArray using name/value pair arguments.
            %
            % See also TRANSDUCERCONVEX
            arguments
                array_args.pitch double {mustBeScalarOrEmpty} 
                array_args.kerf double {mustBeScalarOrEmpty} 
                xdc_args.?Transducer
            end

            % if width not set but pitch is, make it the pitch
            if ~isfield(xdc_args, 'width') && isfield(array_args, 'pitch'), 
                xdc_args.width = array_args.pitch; 
            end
            
            % initialize the Transducer
            xdc_args = struct2nvpair(xdc_args);
            xdc@Transducer(xdc_args{:}) 
            
            % initialize the TransducerArray 
            for f = string(fieldnames(array_args))'
                xdc.(f) = array_args.(f);
            end

            % if kerf not set, default it to 0
            if isempty(xdc.pitch), xdc.kerf = 0; end
        end
    end
    
    % manipulation
    methods
        % scaling
        function xdc = scale(xdc, kwargs)
            % SCALE - Scale units
            %
            % xdc = SCALE(xdc, 'dist', factor) scales the distance of the
            % properties by factor. This can be used to convert from meters
            % to millimeters for example.
            %
            % xdc = SCALE(xdc, 'time', factor) scales the temporal
            % properties by factor. This can be used to convert from
            % seconds to microseconds and hertz to megahertz.
            %
            % Example:
            %
            % % Create a TransducerArray
            % xdc = TransducerArray('fc', 5e6, 'width', 0.3e-3); % m, s, Hz
            %
            % % convert from meters to millimeters, hertz to megahertz
            % xdc = scale(xdc, 'dist', 1e3, 'time', 1e6) % mm, us, MHz
            %
            %

            arguments
                xdc Transducer
                kwargs.dist (1,1) double
                kwargs.time (1,1) double
            end
            args = struct2nvpair(kwargs); % get the arguments as Name/Value pairs
            xdc = scale@Transducer(xdc, args{:}); % call superclass method
            if isfield(kwargs, 'dist')
                w = kwargs.dist;
                % scale distance (e.g. m -> mm)
                [xdc.pitch] = deal(w*xdc.pitch);
            end
        end
    end
        
    % define position methods
    methods(Access=public)    
        % get methods
        function p = positions(xdc)
            array_width = (xdc.numel - 1) * xdc.pitch;
            x = linspace(-array_width/2, array_width/2, xdc.numel);
            p = xdc.transPos([1 0 0]'*x);
        end
        
        function [theta, phi, normal, width, height] = orientations(xdc)            
            theta =  xdc.rot(1) + zeros([1, xdc.numel]);
            phi   = -xdc.rot(2) + 0 * theta;
            ZERO  = 0 * theta;
            normal     = [cosd(phi  ).*sind(theta); sind(phi );  cosd(phi ).*cosd(theta)];
            width      = [cosd(theta);              sind(ZERO); -cosd(ZERO).*sind(theta)];
            height     = [sind(phi  ).*sind(ZERO ); cosd(phi );  sind(phi ).*cosd(ZERO )];
        end        
    end

    
    % SIMUS conversion functions
    methods
        function p = getSIMUSParam(xdc)
            arguments, xdc TransducerArray, end
            p = arrayfun(@(xdc) struct( ...
                'fc', xdc.fc, ...
                'pitch', xdc.pitch, ...
                'width', xdc.width, ...
                'height', xdc.height, ...
                'Nelements', xdc.numel, ...
                'radius', inf, ...
                'bandwidth', 100*xdc.bw_frac, ... 2-way 6dB fractional bandwidth in % 
                'focus', xdc.el_focus ... elevation focus
                ), xdc);
            if isempty(p), p = struct.empty; end
            % TODO: error if origin not at 0.
        end
    end

    % Field II conversion function
    methods
        function aperture = getFieldIIAperture(xdc, sub_div, focus)
            arguments
                xdc TransducerArray
                sub_div (1,2) double = [1,1]
                focus (3,1) double = [0 0 realmax('single')]
            end
            focus(isinf(focus)) = realmax('single') .* sign(focus(isinf(focus))); % make focus finite

            % Field II parameters
            xdc_lin_array_params = arrayfun(@(xdc){{ ...
                xdc.numel, ...
                xdc.width, ...
                xdc.height,...
                xdc.kerf, ...
                sub_div(1), ...
                sub_div(2), ...
                reshape(focus, 1, []),...
                }}, xdc);

            % Generate aperture for emission
            try evalc('field_info'); catch, field_init(-1); end
            i = arrayfun(@(xdc) any(xdc.offset) || any(xdc.rot), xdc); % extra translation/rotation
            aperture( i) = getFieldIIAperture@Transducer(xdc(i), sub_div, focus); % call superclass to make rectangles directly
            aperture(~i) = cellfun(@(p)xdc_linear_array(p{:}), xdc_lin_array_params(~i));
        end
    end
    
    % USTB conversion function
    methods
        function probe = QUPS2USTB(xdc)
            arguments, xdc Transducer, end
            probe = arrayfun(@(xdc) uff.linear_array(...
                'N', xdc.numel, ...
                'pitch', xdc.pitch, ...
                'element_width', xdc.width, ...
                'element_height', xdc.height, ...
                'origin', uff.point('xyz', xdc.offset(:)') ...
                ), xdc);
            if isempty(probe), probe = reshape(uff.linear_array.empty, size(probe)); end
        end
    end

    % Fullwave functions
    methods(Hidden)
        function xdco = getFullwaveTransducer(xdc, sscan)

            [dX, dY] = deal(sscan.dx, sscan.dz); % simulation grid step size
            [X0, Y0]= deal(sscan.x(1), sscan.z(1)); % first value
            nX = sscan.size('X' == sscan.order); % grid size
            nY = sscan.size('Z' == sscan.order);
            % map (X, Z) -> (X, Y)
            
            % define variables
            xdc_.npx     = xdc.numel; % number of elements
            % xdc_.thetas  = xdc.orientations(); % xdc_.dTheta*((-(xdc_.npx-1)/2):((xdc_.npx-1)/2)); % the thetas defining the transmit elements

            % legacy
            % zero_offset = 12.4e-3;      % (deprecated) offset of transducer face, how much it comes into the grid (m)
            % xdc_.ptch    = xdc.pitch; % sind(xdc.angular_pitch) * xdc.radius; % angular pitch of the transducer (pixels)
            % xdc_.cen     = [(xdc.offset(1) - X0)/dX, (xdc.offset(3) - xdc.radius - Y0)/dY]; % center of the transducer in grid indices

            %% Make incoords and outcoords curves

            % define the thetas at the center of each element
            % evenly space, centered at 0deg
            % for n=1:xdc_.npx, xdc_.thetas(n)=n*xdc_.dTheta; end
            % xdc_.thetas = xdc_.thetas-mean(xdc_.thetas);

            % get x-axis and y-axis
            x = X0 + (0:nX-1) * dX; % 1 x X
            y = Y0 + (0:nY-1) * dY; % 1 x Y

            % Make a rectangle that defines the transducer surface
            pb = xdc.bounds;
            inmap  = pb(1,1) < x' & x' < pb(1,2) & y < pb(3,2);
            outmap = zeros(nX,nY);

            % Grab the coords on edge of the rectangle - deeper rect for outcoords
            for i=1:nX
                % find inmap coords
                j = find(inmap(i,:)==0);
                j = j(1);
                inmap(i,1:max([j-8 0]))=0; % make a depth of 8-1=7 pixels in y

                % find outmap coords
                j = find(inmap(i,:)==1);
                if(~isempty(j))
                    j = j(end)+2; % offset by 2 indices in y - this is important!
                    outmap(i,j)= 1; % make a depth of 1 pixel in y
                end
            end

            % convert incoords binary map to a vector of coordinates
            xdc_.inmap     = inmap;
            xdc_.incoords  = mapToCoords(double(inmap));
            [~, idcr]     = sort(xdc_.incoords(:,1)); % sort by x instead of y
            xdc_.incoords  = xdc_.incoords(idcr,:);

            % convert outcoords binary map to a vector of coordinates
            xdc_.outcoords = mapToCoords(outmap);
            [~, idcr]     = sort(xdc_.outcoords(:,1)); % sort by x instead of y
            xdc_.outcoords = xdc_.outcoords(idcr,:);

            %% assign which transducer number each incoord is assigned to
            xn = xdc.positions();
            xn = xn(1,:); % x-positions of the transmit elements

            % get location of the center of each element (in pixels)
            xdc_.outcoords2 = zeros(0,2);
            xdc_.incoords2  = zeros(0,2);

            xdc_.outcoords(:,3) = 1; % this helps with reading genout
            xdc_.outcoords(:,4) = 0; % This labels which tranducer element each subelement is assigned to
            xdc_.incoords (:,4) = 0; % This labels which tranducer element each subelement is assigned to

            for tt=1:xdc_.npx

                % find which incoords are assigned to tt
                % less_than_max    = xdc.thetas_in < (xdc.thetas(tt) + xdc.dTheta/2);
                % greater_than_min = xdc.thetas_in > (xdc.thetas(tt) - xdc.dTheta/2);
                % idtheta = find( less_than_max & greater_than_min);
                idxn = abs(x(xdc_.incoords(:,1)) - xn(tt)) < xdc.pitch/2; % x is in-bounds
                xdc_.incoords(idxn,4) = tt; % assign

                % find center of tt tx element - do each dim separate cause sometimes idtheta is just one value
                % xdc.incoords2(tt,1) = mean(xdc.incoords(idtheta,1));
                % xdc.incoords2(tt,2) = mean(xdc.incoords(idtheta,2));
                xdc_.incoords2(tt,1:2) = mean(xdc_.incoords(idxn,1:2),1);

                % find which outcoords are assigned to tt
                % less_than_max    = xdc.thetas_out < (xdc.thetas(tt) + xdc.dTheta/2);
                % greater_than_min = xdc.thetas_out > (xdc.thetas(tt) - xdc.dTheta/2);
                % idtheta = find( less_than_max & greater_than_min);
                idxn = abs(x(xdc_.outcoords(:,1)) - xn(tt)) < xdc.pitch/2; % x is in-bounds
                xdc_.outcoords(idxn,4) = tt; % assign

                % find center of tt rx element - do each dim separate cause sometimes
                % xdc.outcoords2(tt,1) = mean(xdc.outcoords(idtheta,1));
                % xdc.outcoords2(tt,2) = mean(xdc.outcoords(idtheta,2));
                xdc_.outcoords2(tt,1:2) = mean(xdc_.outcoords(idxn,1:2),1);

            end

            xdc_.nOutPx = size(xdc_.outcoords,1);
            xdc_.nInPx  = size(xdc_.incoords,1);

            %     figure(2); clf;
            %     plot(xdc.incoords(:,1),xdc.incoords(:,2),'.'), hold on
            %     plot(xdc.incoords2(:,1),xdc.incoords2(:,2),'.')
            %     plot(xdc.outcoords(:,1),xdc.outcoords(:,2),'.')
            %     plot(xdc.outcoords2(:,1),xdc.outcoords2(:,2),'.'), hold off

            % make vector which labels where the transducer surface is in pixels in
            % y across x
            xdc_.surf = zeros(1,nX);
            for i = 1:nX

                % find where the transducer surface is
                j = find(xdc_.inmap(i,:)==1);
                if(~isempty(j))
                    j = j(end);
                else
                    j = 1;
                end
                xdc_.surf(i) = j + 6; % round(ppw/2); % buffer ?????????????????????????
            end

            % output a struct with only the required fields (for
            % consistency)
            args = cellstr(["npx", "inmap", "nInPx", "nOutPx", "incoords", "outcoords", "incoords2", "outcoords2", "surf"]);
            for a = 1:numel(args), args{2,a} = xdc_.(args{1,a}); end
            xdco = struct(args{:});

        end
    end

    % dependent variable methods
    methods
        % get the kerf
        function k = get.kerf(xdc), k = xdc.pitch - xdc.width; end
        
        % set the kerf
        function set.kerf(xdc, k)
           xdc.pitch = xdc.width + k; 
           if xdc.pitch < 0
               warning('The interelement spacing is less than 0!');
           end
        end
        
        % get the aperture size
        function a = get.aperture_size(xdc), a = xdc.numel * xdc.pitch; end
    end
    
    methods(Static)
        function xdc = L12_3v()
            % Transducer parameters for a verasonics L12-3v probe
            xdc = TransducerArray(...
                'fc', mean([4e6 11e6]), ...
                'bw', ([4e6 11e6]), ...
                'width', (0.18e-3), ... placeholder @ 90% pitch
                'height', (2e-3), ... placeholder @ 10x pitch
                'numel', 192, ...
                'pitch', 0.2e-3, ...
                'el_focus', 20e-3 ...
                );
        end
        function xdc = L11_5v()
            % Transducer parameters for a verasonics L11-5v probe
            xdc = TransducerArray(...
                'fc', mean([4.5e6 10e6]), ...
                'bw', ([4.5e6 10e6]), ...
                'width', (0.27e-3), ... placeholder @ 90% pitch
                'height', (3e-3), ... placehoder @ 10x pitch
                'numel', 128, ...
                'pitch', 0.3e-3, ...
                'el_focus', 18e-3 ...
                );
        end
        function xdc = L11_2v()
            % Transducer parameters for a verasonics L12-2v probe
            xdc = TransducerArray(...
                'fc', 5.1333e+06, ... % Transducer center frequency [Hz]
                'bw', 5.1333e6 + 3e6*[-1 1]/2, ... % bandwidth [Hz]
                'width', 0.270e-3, ... % linear kerf
                'height', 5e-3, ... % Height of element [m]
                'numel', 128, ... % number of elements
                'pitch', 0.300e-3, ... % probe pitch [m]
                'el_focus', 20e-3 ... % elevation focal depth [m]
                );

        end
        function xdc = L12_5v()
            % Transducer parameters for a verasonics L12-5 50mm probe
            xdc = TransducerArray(...
                'fc', 7.5e6, ... % Transducer center frequency [Hz]
                'bw', ([5 11])*1e6, ... % bandwidth [Hz]
                'width', hex2num('3f265251dc6ba641'), ... % element width [m]
                'height', 7.5e-3, ... % Height of element [m]
                'numel', 256, ... % number of elements
                'pitch', hex2num('3f29992e39cf2ea7'), ... % probe pitch [m]
                'el_focus', 20e-3 ... % elevation focal depth [m]
                );
        end
        function xdc = P4_2v()
            % Transducer parameters for a verasonics P4-2v probe
            xdc = TransducerArray(...
                'fc', 3e6, ... % Transducer center frequency [Hz]
                'bw', ([1.5 4.5])*1e6, ... % bandwidth [Hz]
                'width', (0.27e-3), ... placeholder @ 90% pitch
                'height', (3e-3), ... placeholder @ 10x pitch
                'numel', 64, ... % number of elements
                'pitch', 0.3e-3, ... % probe pitch [m]
                'el_focus', mean([50 70])*1e-3 ... % elevation focal depth  [m]
                );
        end
        function xdc = Verasonics(Trans, c0)
            arguments
                Trans (1,1) struct
                c0 (1,1) double = 1540
            end

            switch Trans.units % determine the scaling of the properties
                case 'wavelengths', scale = c0 / Trans.frequency * 1e-6; % lambda -> m
                case 'mm', scale = 1e-3; % mm -> m
            end

            if isfield(Trans, 'spacingMm'),   d = 1e-3 * Trans.spacingMm;
            elseif isfield(Trans, 'spacing'), d = c0 / Trans.frequency * 1e-6 * Trans.spacing;
            else, error("QUPS:TransducerArray:Verasonics:undefinedSpacing", "Cannot find the element spacing in the given Trans struct.")
            end

            % set relevant properties
            xdc = TransducerArray(...
                'fc',       1e6*Trans.frequency, ... % Transducer center frequency [Hz]
                'width',    scale*Trans.elementWidth, ... % linear kerf
                'height',   scale*Trans.elementLength, ... % Height of element [m]
                'numel',    Trans.numelements, ... % number of elements
                'pitch',    d ... % probe pitch [m]
                );
        end
        function xdc = UFF(probe)
            arguments
                probe uff.linear_array
            end
            for i = 1:numel(probe)
                if isempty(probe.origin), probe.origin.xyz = [0;0;0]; end % force 0 if empty
            end
            xdc = arrayfun(@(probe) TransducerArray(...
                "pitch", probe.pitch, ...
                "width", probe.element_width, ...
                "height", probe.element_height, ...
                "numel", probe.N_elements, ...
                "offset", - probe.origin.xyz ...
                ), probe);
        end
    end
end
