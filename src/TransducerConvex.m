% TRANSDUCERCONVEX - Convex Array Transducer class
% 
% A TransducerConvex defines a convex transducer where all elements lie on
% a circle.
% 
% See also TRANSDUCER TRANSDUCERARRAY TRANSDUCERMATRIX

classdef TransducerConvex < Transducer
    
    % verasonics C5-2V defaults
    properties
        radius = 50e-3          % inner radius of curvature
        angular_pitch = 0.5872  % the interelement angular distance (deg)
    end
       
    properties(Dependent)
        pitch                   % interelement spacing along the arc 
        kerf                    % the spacing between elements along the arc
        angular_aperture_size   % size of the aperture (deg)
        center                  % center of the circle defining the transducer
    end
    
    % constructor and get/set methods
    methods(Access=public)
        function xdc = TransducerConvex(array_args, xdc_args)
            % TRANSDUCERCONVEX - TransducerConvex constructor
            %
            % xdc = TRANSDUCERCONVEX(Name, Value, ...) constructs a
            % TransducerConvex using name/value pair arguments.
            %
            % See also TRANSDUCERARRAY
            arguments
                array_args.pitch double {mustBeScalarOrEmpty}
                array_args.kerf double {mustBeScalarOrEmpty}
                array_args.radius double {mustBeScalarOrEmpty}
                array_args.angular_pitch double {mustBeScalarOrEmpty}
                array_args.center (3,1) double 
                xdc_args.?Transducer
            end

            % if width not set but pitch is, make it the pitch
            if ~isfield(xdc_args, 'width') && isfield(array_args, 'pitch'),
                xdc_args.width = array_args.pitch;
            end

            % initialize the Transducer
            xdc_args = struct2nvpair(xdc_args);
            xdc@Transducer(xdc_args{:})

            % initialize the TransducerConvex
            for f = string(fieldnames(array_args))'
                if f == "pitch", continue; end % set this last
                xdc.(f) = array_args.(f);
            end
            if isfield(array_args, "pitch"), xdc.pitch = array_args.pitch; end

            % if kerf not set, default it to 0
            if isempty(xdc.pitch), xdc.kerf = 0; end
        end
    end
    
    % manipulation
    methods
        % scaling
        function xdc = scale(xdc, kwargs)
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
                [xdc.radius, xdc.center] = deal(w*xdc.radius, w*xdc.center);
                
            end
        end
    end

    % define position methods
    methods
        % get methods                
        function p = positions(xdc)
            array_angular_width = (xdc.numel - 1)* xdc.angular_pitch;
            theta = linspace(-array_angular_width/2, array_angular_width/2, xdc.numel);
            z = xdc.radius * cosd(theta);
            x = xdc.radius * sind(theta);
            y =      0      *      theta ;
            p = xdc.transPos([x; y; z]) - [0 0 xdc.radius]';
        end
        
        function [theta, phi, normal, width, height] = orientations(xdc)
            array_angular_width = (xdc.numel - 1)* xdc.angular_pitch;
            theta =  xdc.rot(1) + linspace(-array_angular_width/2, array_angular_width/2, xdc.numel);
            ZERO  =       0      * theta; % broadcast 
            phi   = -xdc.rot(2) + ZERO; % implicit broadcast
            normal     = [cosd(phi).*sind(theta); sind(phi );  cosd(phi ).*cosd(theta)];
            width      = [cosd(theta);            sind(ZERO); -cosd(ZERO).*sind(theta)];
            height     = [sind(phi).*sind(ZERO ); cosd(phi );  sind(phi ).*cosd(ZERO )];
        end        
    end

    % SIMUS conversion functions
    methods
        function p = getSIMUSParam(xdc)
            arguments, xdc TransducerConvex {mustBeNonempty}, end
            p = arrayfun(@(xdc) struct( ... 
                'fc', xdc.fc, ...
                'pitch', xdc.pitch, ...
                'width', xdc.width, ...
                'height', xdc.height, ...
                'Nelements', xdc.numel, ...
                'radius', xdc.radius, ...
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
                xdc TransducerConvex
                sub_div (1,2) double = [1,1]
                focus (3,1) double = [0 0 realmax('single')]
            end

            focus(isinf(focus)) = realmax('single') .* sign(focus(isinf(focus))); % make focus finite
                        
            % Field II parameters
            xdc_convex_params = arrayfun(@(xdc) {{ ...
                xdc.numel,     ... no of elements in x direciton
                xdc.width,     ... size of elements in x-arc direction
                xdc.height,    ... size of elements in y direciton
                xdc.kerf,      ... kerf in x-arc direction
                xdc.radius,    ... inner convex radius (circumscribed)
                sub_div(1), ... x sub-divisions
                sub_div(2), ... y sub-divisions
                focus.'         ... focal depth
                }}, xdc);
            
            % Generate aperture for emission
            try evalc('field_info'); catch, field_init(-1); end
            i = arrayfun(@(xdc) any(xdc.offset) || any(xdc.rot), xdc); % extra translation/rotation
            aperture( i) = getFieldIIAperture@Transducer(xdc(i), sub_div, focus); % call superclass to make rectangles directly
            aperture(~i) = cellfun(@(p)xdc_convex_array(p{:}), xdc_convex_params(~i));
        end
    end
    
    % USTB conversion function
    methods
        function probe = QUPS2USTB(xdc)
            arguments, xdc TransducerConvex, end
            probe = arrayfun(@(xdc) uff.curvilinear_array(...
                'N', xdc.numel, ...
                'pitch', xdc.pitch, ...
                'radius', xdc.radius, ...
                'element_width', xdc.width, ...
                'element_height', xdc.height, ...
                'origin', uff.point('xyz', xdc.offset(:)') ...
                ), xdc);
            if isempty(probe), probe = reshape(uff.curvilinear_array.empty, size(probe)); end
        end
    end

    % Fullwave functions (in-house)
    methods
        function xdco = getFullwaveTransducer(xdc, sscan)
            
            [dX, dY] = deal(sscan.dx, sscan.dz); % simulation grid step size
            [X0, Y0]= deal(sscan.x(1), sscan.z(1)); % first value
            nX = sscan.size('X' == sscan.order); % grid size
            nY = sscan.size('Z' == sscan.order);
            % map (X, Z) -> (X, Y)
            

            % define variables
            xdc_.npx     = xdc.numel; % number of elements
            xdc_.dTheta  = xdc.angular_pitch; % atan2(xdc_.ptch,xdc_.rad); % angular pitch (radians)
            xdc_.thetas  = xdc.orientations(); % xdc_.dTheta*((-(xdc_.npx-1)/2):((xdc_.npx-1)/2)); % the thetas defining the transmit elements
            
            % legacy
            % xdc_.rad     = self.radius / dY; % 4.957e-2;  % radius of the transducer (pixels)
            % zero_offset = 12.4e-3;      % (deprecated) offset of transducer face, how much it comes into the grid (m)
            % xdc_.ptch    = sind(self.angular_pitch) * self.radius / dY; % spatial pitch of the transducer (pixels)
            % xdc_.cen     = [(self.offset(1) - X0)/dX, (self.offset(3) - self.radius - Y0)/dY]; % center of the transducer in grid indices
            
            %% Make incoords and outcoords curves

            % define the thetas at the center of each element
            % evenly space, centered at 0deg
            % for n=1:xdc_.npx, xdc_.thetas(n)=n*xdc_.dTheta; end
            % xdc_.thetas = xdc_.thetas-mean(xdc_.thetas);

            % get x-axis and y-axis
            x = X0 + (0:nX-1) * dX; % 1 x X
            y = Y0 + (0:nY-1) * dY; % 1 x Y

            % Make a circle that defines the transducer surface
            inmap = (hypot(x' - xdc.center(1), y - xdc.center(3))) < xdc.radius; % X x Y
            outmap = zeros(nX,nY);
            % inmap(hypot(x+self.offset(1),y+self.offset(3)-self.radius) < self.radius) = true;
            % inmap(circleIdx(size(inmap),xdc_.cen,xdc_.rad/dY)) = 1;

            % Grab the coords on edge of the circle - larger circle for outcoords
            for i=1:nX

                % find inmap coords
                j = find(inmap(i,:)==0);
                j = j(1);
                inmap(i,1:max([j-8 0]))=0; % make a depth of 8-1=7 pixels in y

                % find outmap coords
                j = find(inmap(i,:)==1);
                if(~isempty(j))
                    j = j(end)+2; % offset by 2 indices in y - this is important!
                    outmap(i,j)=1; % make a depth of 1 pixel in y
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
            % xdc_.thetas_in  = atan2(xdc_.incoords(:,1)-xdc_.cen(1),xdc_.incoords(:,2)-xdc_.cen(2));
            % xdc_.thetas_out = atan2(xdc_.outcoords(:,1)-xdc_.cen(1),xdc_.outcoords(:,2)-xdc_.cen(2));

            xdc_.thetas_in   = atan2d(x(1+xdc_.incoords (:,1)) - xdc.center(1),y(1+xdc_.incoords (:,2))-xdc.center(3));
            xdc_.thetas_out  = atan2d(x(1+xdc_.outcoords(:,1)) - xdc.center(1),y(1+xdc_.outcoords(:,2))-xdc.center(3));

            % get location of the center of each element (in pixels)
            xdc_.outcoords2 = zeros(0,2);
            xdc_.incoords2  = zeros(0,2);

            xdc_.outcoords(:,3) = 1; % this helps with reading genout
            xdc_.outcoords(:,4) = 0; % This labels which tranducer element each subelement is assigned to
            xdc_.incoords (:,4) = 0; % This labels which tranducer element each subelement is assigned to

            for tt=1:xdc_.npx

                % find which incoords are assigned to tt
                % less_than_max    = xdc_.thetas_in < (xdc_.thetas(tt) + xdc_.dTheta/2);
                % greater_than_min = xdc_.thetas_in > (xdc_.thetas(tt) - xdc_.dTheta/2);
                % idtheta = find( less_than_max & greater_than_min);
                idtheta = abs(xdc_.thetas_in - xdc_.thetas(tt)) < xdc_.dTheta/2;
                xdc_.incoords(idtheta,4) = tt;

                % find center of tt tx element - do each dim separate cause sometimes idtheta is just one value
                % xdc_.incoords2(tt,1) = mean(xdc_.incoords(idtheta,1));
                % xdc_.incoords2(tt,2) = mean(xdc_.incoords(idtheta,2));
                xdc_.incoords2(tt,1:2) = mean(xdc_.incoords(idtheta,1:2),1);

                % find which outcoords are assigned to tt
                % less_than_max    = xdc_.thetas_out < (xdc_.thetas(tt) + xdc_.dTheta/2);
                % greater_than_min = xdc_.thetas_out > (xdc_.thetas(tt) - xdc_.dTheta/2);
                % idtheta = find( less_than_max & greater_than_min);
                idtheta = abs(xdc_.thetas_out - xdc_.thetas(tt)) < xdc_.dTheta/2;
                xdc_.outcoords(idtheta,4) = tt;

                % find center of tt rx element - do each dim separate cause sometimes
                % xdc_.outcoords2(tt,1) = mean(xdc_.outcoords(idtheta,1));
                % xdc_.outcoords2(tt,2) = mean(xdc_.outcoords(idtheta,2));
                xdc_.outcoords2(tt,1:2) = mean(xdc_.outcoords(idtheta,1:2),1);

            end

            % remove coordinates with no matching element - they are unused
            % this was commented out and it worked
            xdc_.incoords (xdc_.incoords (:,4)==0,:) = [];
            xdc_.outcoords(xdc_.outcoords(:,4)==0,:) = [];

            xdc_.nOutPx = size(xdc_.outcoords,1);
            xdc_.nInPx  = size(xdc_.incoords,1);

            %     figure(2); clf;
            %     plot(xdc_.incoords(:,1),xdc_.incoords(:,2),'.'), hold on
            %     plot(xdc_.incoords2(:,1),xdc_.incoords2(:,2),'.')
            %     plot(xdc_.outcoords(:,1),xdc_.outcoords(:,2),'.')
            %     plot(xdc_.outcoords2(:,1),xdc_.outcoords2(:,2),'.'), hold off

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
        % get the pitch
        function p = get.pitch(xdc), p = 2 * xdc.radius * sind(xdc.angular_pitch / 2); end
        
        % set the pitch
        function set.pitch(xdc, p), xdc.angular_pitch = 2 * asind(p / 2 / xdc.radius); end
        
        % get the kerf
        function k = get.kerf(xdc), k = xdc.pitch - xdc.width; end
        
        % set the kerf
        function set.kerf(xdc, k)
           xdc.pitch = xdc.width + k; 
           if xdc.angular_pitch < 0
               warning('The interelement angular spacing is less than 0!');
           end
        end
        
        % get the aperture size
        function a = get.angular_aperture_size(xdc), a = (xdc.numel - 1) * xdc.angular_pitch; end

        % get the center of the transducer
        function p = get.center(xdc), p = - [0; 0; xdc.radius] + xdc.offset; end

        % set the center of the transducer
        function set.center(xdc, p)
            xdc.offset(1:numel(p)) = p + sub([0; 0; xdc.radius], 1:numel(p));
        end
    end
    
    methods(Static)
        function xdc = C5_2v()
            xdc = TransducerConvex(...
            'fc', 1e6*mean([2.4 5]), ... % in verasonics doc, this is 4
            'bw', 1e6*([2.4 5]), ...
            'width', 0.46e-3, ...
            'height', 13.5e-3, ...
            'numel', 128, ...
            'radius', 49.57e-3, ...
            'angular_pitch', hex2num('3fe2ca22dae81311'), ...
            'el_focus', mean([50e-3 70e-3]) ...
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

            if isfield(Trans, 'radiusMm'),   r = 1e-3 * Trans.radiusMm;
            elseif isfield(Trans, 'radius'), r = c0 / Trans.frequency * 1e-6 * Trans.radius; 
            else, error("QUPS:TransducerConvex:Verasonics:undefinedRadius", "Cannot find the radius in the given Trans struct.")
            end

            if isfield(Trans, 'spacingMm'),   d = 1e-3 * Trans.spacingMm;
            elseif isfield(Trans, 'spacing'), d = c0 / Trans.frequency * 1e-6 * Trans.spacing; 
            else, error("QUPS:TransducerConvex:Verasonics:undefinedSpacing", "Cannot find the element spacing in the given Trans struct.")
            end

            % set relevant properties
            xdc = TransducerConvex(...
                'fc',       1e6*Trans.frequency, ... % Transducer center frequency [Hz]
                'width',    scale*Trans.elementWidth, ... % linear kerf
                'height',   scale*Trans.elementLength, ... % Height of element [m]
                'numel',    Trans.numelements, ... % number of elements
                'radius',   r, ... % radius [m]
                'pitch',    d ... % probe pitch [m]
                );
        end
        function xdc = UFF(probe)
            arguments
                probe uff.curvilinear_array
            end
            for i = 1:numel(probe)
                if isempty(probe.origin), probe.origin.xyz = [0;0;0]; end % force 0 if empty
            end
            xdc = arrayfun(@(probe) TransducerConvex(...
                "pitch", probe.pitch, ...
                "radius", probe.radius, ...
                "width", probe.element_width, ...
                "height", probe.element_height, ...
                "numel", probe.N_elements, ...
                "offset", - probe.origin.xyz ...
                ), probe);
        end
    end    
end
