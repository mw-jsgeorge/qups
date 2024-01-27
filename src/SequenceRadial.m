classdef SequenceRadial < Sequence
    % SEQUENCERADIAL - Sequence defined by range/angle coordinates
    %
    % A SEQUENCERADIAL object expands the Sequence class by offereing 
    % utilities for transmit sequences that can be defined by range and 
    % angle with respect to an apex.
    %
    % Use with a TransducerConvex with the apex at the center or use to 
    % conveniently create plane wave focal sequences with a range of one
    % across all angles.
    %
    % See also: SEQUENCE SEQUENCEGENERIC TRANSDUCERCONVEX
    
    properties
        apex (3,1) {mustBeNumeric} = [0;0;0] % Center of polar coordinate system
    end
    
    properties(Dependent)
        ranges (1,:) {mustBeNumeric} % range from the apex, or length of the vector
        angles (1,:) {mustBeNumeric} % angle with respect to the z-axis (deg)
    end
    
    methods
        % constructor
        function self = SequenceRadial(seq_args, seqr_args)
            % SEQUENCERADIAL - SequenceRadial constructor
            %
            % seq = SEQUENCERADIAL() constructs a Sequence
            %
            % seq = SEQUENCERADIAL(Name, Value, ...) uses Name/Value pair
            % arguments to construct a Sequence
            %
            % seq = SEQUENCERADIAL('type', 'PW', 'angles', theta) defines a
            % plane wave (PW) sequence at the 1 x S array of angles theta. 
            % The angles theta must be in degrees.
            %
            % seq = SEQUENCERADIAL('type', 'VS', 'apex', apex, 'ranges', r, 'angles', theta)
            % defines a focused or diverging virtual source (VS) sequence 
            % with focal point locations at the ranges r and angles theta 
            % in polar coordinates with respect to an origin at apex. the
            % angles theta are defined in degrees.
            %
            % seq = SEQUENCERADIAL(..., 'c0', c0) sets the beamforming 
            % sound speed to c0. 
            %
            % seq = SEQUENCERADIAL(..., 'pulse', wv) defines the 
            % transmitted pulse to be the Waveform wv.
            %
            % See also SEQUENCERADIAL WAVEFORM

            arguments % Sequence arguments
                seq_args.?Sequence
                seq_args.type (1,1) string {mustBeMember(seq_args.type, ["PW", "FC", "DV", "VS",])} = "PW" % restrict 
            end
            arguments % SequenceRadial arguments
                seqr_args.apex (3,1) {mustBeNumeric} = [0;0;0]
                seqr_args.ranges (1,:) {mustBeNumeric}
                seqr_args.angles (1,:) {mustBeNumeric}
            end
            
            % initialize Sequence properties
            seq_args_ = struct2nvpair(seq_args);
            self@Sequence(seq_args_{:});
            
            % initialize SequenceRadial properties 
            self.apex = seqr_args.apex; 

            % initialize range/angle together
            if isfield(seq_args, 'focus') % focus is set -> range/angle invalid
                if isfield(seqr_args, 'ranges') || isfield(seqr_args, 'angles') 
                    error("The focus must be set either by focus or by range/angle.");
                end
            else  % focus not set -> range/angle
                if ~isfield(seqr_args, 'ranges'), seqr_args.ranges = 1; end % initialize if not set
                if ~isfield(seqr_args, 'angles'), seqr_args.angles = 0; end % initialize if not set
                self.setPolar(seqr_args.ranges, seqr_args.angles); % set the focus
            end
        end
        
        % scaling
        function self = scale(self, kwargs)
            arguments
                self SequenceRadial
                kwargs.dist (1,1) double
                kwargs.time (1,1) double
            end
            args = struct2nvpair(kwargs); % gather args
            self = scale@Sequence(self, args{:}); % call the superclass method
            if isfield(kwargs, 'dist')
                self.apex = kwargs.dist * self.apex; % scale distance (e.g. m -> mm)
            end
        end
    end

    % get/set methods
    methods
        function setPolar(self, ranges, angles, apex)
            % SETPOLAR - Set the focal points in polar coordinates
            %
            % SETPOLAR(self, ranges, angles) defines the foci given the  
            % ranges and angles.
            %
            % SETPOLAR(self, ranges, angles, apex) additionally redefines 
            % the apex.
            %
            % See also MOVEAPEX
            arguments % SequenceRadial arguments
                self SequenceRadial
                ranges (1,:) {mustBeNumeric}
                angles (1,:) {mustBeNumeric}
                apex (3,1) {mustBeNumeric} = self.apex;
            end

            self.apex = apex(:); % set apex
            [ranges, angles] = deal(ranges(:)', angles(:)'); % 1 x [1|S]
            foci = ranges .* SequenceRadial.vectors_(angles); % 3 x S
            self.focus = foci + self.apex;
        end
        function r = get.ranges(self), r = vecnorm(self.focus - self.apex, 2, 1); end
        function a = get.angles(self), a = atan2d(sub(self.focus - self.apex,1,1), sub(self.focus - self.apex,3,1)); end
        function set.ranges(self, r), self.focus = self.apex + r .* self.vectors(); end
        function set.angles(self, a), self.focus = self.apex + self.ranges .* SequenceRadial.vectors_(a); end
        function moveApex(self, apex)
            % MOVEAPEX - Set a new apex, preserving the ranges and angles
            %
            % MOVEAPEX(self, apex) moves the apex for the SequenceRadial,
            % preserving the ranges / angles of the Sequence
            %
            % See also: SEQUENCERADIAL/SETPOLAR
            arguments
                self SequenceRadial
                apex (3,1)
            end
            
            % to move the apex, if ranges and angles are there, preserve
            % them for a SEQUENCERADIAL
            [r, a] = deal(self.ranges, self.angles);
            self.setPolar(r, a, apex);
        end
    end

    % helper functions
    methods
        function v = vectors(self), v = SequenceRadial.vectors_(self.angles); end
        % VECTORS - Cartesian normal vectors corresponding to each angle
    end

    % helper functions
    methods(Static, Hidden)
        function v = vectors_(angles), v = cat(1, sind(angles), zeros(size(angles)), cosd(angles)); end
    end

    % plotting functions
    methods
        function h = plot(self, varargin, quiver_args)
            arguments
                self (1,1) SequenceRadial
            end
            arguments(Repeating)
                varargin
            end
            arguments
                quiver_args.?matlab.graphics.chart.primitive.Quiver
                quiver_args.DisplayName = 'Sequence'
            end
            
            if numel(varargin) >= 1 && isa(varargin{1},'matlab.graphics.axis.Axes')
                hax = varargin{1}; varargin(1) = []; % extract axis
            else 
                hax = gca;
            end

            % make a quiver plot, starting at the origin, and
            % pointing in the vector direction
            vecs = self.vectors() .* self.ranges;
            og = repmat(self.apex, [1,size(vecs,2)]);
            [x, y, z] = deal(  og(1,:),   og(3,:),   og(2,:));
            [u, v, w] = deal(vecs(1,:), vecs(3,:), vecs(2,:));
            quiver_args = struct2nvpair(quiver_args);
            h = quiver3(hax, x, y, z, u, v, w, varargin{:}, quiver_args{:});
        end
    end
        
end