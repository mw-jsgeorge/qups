classdef KernTest < matlab.unittest.TestCase
    % KernTest - Function tests class
    %
    % This class test that all kernel functions operate properly

    %#ok<*NASGU,*ASGLU> unused variables

     properties(TestParameter)
        prec = {'double', 'single'}%, 'halfT'}
        complexity = struct('real', 'real', 'complex', 'complex');
        dev = getdevs()
     end

     properties
         dargs % data arguments
     end

    methods(TestClassSetup)
        % Setup for the entire class
        function set_data(test)
            % create random values for interpd
            [I, T, N, M, F] = deal(2^5, 2^8, 2, 3, 4);
            fc = shiftdim((0 : F - 1), -2); % 1 x 1 x 1 x F
            t = (0 : T - 1)' ./ T; % T x 1 x 1 x 1
            x = (cospi(2*fc.*t) + 1i*sinpi(2*fc.*t)) + 0.01*(complex(rand([1,N]), rand([1,N])) - (0.5 + 0.5i)); % T x N x 1 x F
            tau = (4 + (T - 8)) .* rand([I, N, M, 1]); % I x N x M x 1
            test.dargs{1} = {I, T, N, M, F, fc, t, x, tau};

            % random values for convd
            [N,M] = deal(2^10, 1);
            A = complex(randn([N,M]), randn([N,M]));
            B = complex(randn([N,M]), randn([N,M]));
            test.dargs{2} = {A, B, N, M};

            % random values for slsc / pcf / dmas
            us = UltrasoundSystem();
            [us.xdc.numel, us.seq.numPulse] = deal(8, 4);
            [us.scan.nx, us.scan.nz] = deal(16,32);
            sz = [us.scan.size us.xdc.numel];
            b = complex(randn(sz), randn(sz));
            test.dargs{3} = {us, b};
        end
    end

    % dispatch
    % Github test routine
    methods(Test, ParameterCombination = 'pairwise', TestTags={'Github','syntax'})
        function github_runconvd(test, prec, complexity, dev)
            runconvd(test, prec, complexity, dev)
        end
        function github_runinterpd(test, prec, complexity, dev)
            runinterpd(test, prec, complexity, dev)
        end
        function github_apred(test, dev, prec)
            aperture_reduction(test, dev, prec);
        end
        function github_correlator(test, prec, complexity, dev)
            correlator(test, prec, complexity, dev);
        end
    end

    % Full test routine
    methods(Test, ParameterCombination = 'exhaustive', TestTags={'full', 'build'})
        function full_convd(test, prec, complexity, dev), runconvd(test, prec, complexity, dev); end % forward all
        function full_interpd(test, prec, complexity, dev), runinterpd(test, prec, complexity, dev); end % forward all
        function full_apred(test, dev, prec), aperture_reduction(test, dev, prec); end % forward all
        function full_correlator(test, prec, complexity, dev); correlator(test, prec, complexity, dev); end
    end


    % test implementations
    methods
        function runconvd(test, prec, complexity, dev)

            % import matlab.unittest.TestCase;
            import matlab.unittest.constraints.NumericComparator;
            import matlab.unittest.constraints.IsEqualTo;
            import matlab.unittest.constraints.RelativeTolerance;
            if prec == "halfT", test.assumeTrue(logical(exist('halfT', 'class'))); end

            % random values
            [A, B, N, M] = deal(test.dargs{2}{:});
            [A,B] = dealfun(str2func(prec), A, B); % cast to type
            switch prec
                case "double", tol = 1e14;
                case "single", tol = 1e4; 
                case "halfT" , tol = 1e2;
            end
            switch complexity, case "real", [A,B] = deal(real(A), real(B)); end
            switch dev, case "gpu", [A,B] = dealfun(@gpuArray, A,B); end

            % check each type of argument
            % TODO: move this to setup params
            shapes = ["full", "same", "valid"];
            dims = [1,2,3]; 

            % check that defaults and options work
            test.assertTrue(isalmostn(convd(A), xcorr(A)));
            convd(A, B);
            convd(B, A, 'lowmem', true);

            % broadcasting
            test.assertTrue( all(convd(cat(4,A,A), B) == convd(A, B), 'all') );

            % convolve and check outputs
            for s = shapes, for d = dims %#ok<ALIGN> 
                z1 = cell2mat(cellfun(@(A,B) {gather(conv(A, B, char(s)))}, num2cell(A,1), num2cell(B,1)));
                z2 = gather(convd(shiftdim(A,1-d),shiftdim(B,1-d),d,s,'gpu',dev == "gpu", 'ocl', dev == "ocl"));
                test.assertThat(...
                    double(shiftdim(z2,d-1)), ...
                    IsEqualTo(double(z1), 'Using', NumericComparator('Within', RelativeTolerance(tol*double(eps(max(z1(:))))))) ...
                    );
            end,end

        end
        function runinterpd(test, prec, complexity, dev)
            % test the interpd fuction behaves like interp1 but better
            import matlab.unittest.constraints.NumericComparator;
            import matlab.unittest.constraints.IsEqualTo;
            import matlab.unittest.constraints.RelativeTolerance;
            if prec == "halfT", test.assumeTrue(logical(exist('halfT', 'class'))); end
            if prec == "halfT", test.assumeFalse(dev == "ocl"); end % not supported

            [I, T, N, M, F, fc, t, x, tau] = deal(test.dargs{1}{:});
            if dev == "gpu", [x, t, tau] = dealfun(@gpuArray, x, t, tau); end

            % all permutations
            terp = ["nearest", "linear"];%, "cubic"];
            ords = [1,2,3,4; 1,2,4,3; 2,1,3,4; 3,4,1,2; 4,3,2,1];
            switch prec
                case "double", tol = 1e12;
                case "single", tol = 1e5;
                case "halfT" , tol = 1e4;
            end
            switch complexity, case "real", x = real(x); end

            % test defaults, options run
            interpd(x, tau);
            interpd(x, tau, 1, "cubic");
            if dev == "gpu", interpd(x, tau, 1, "lanczos3"); end

            % cast data
            for terp_ = terp
                [x,t,tau] = dealfun(str2func(prec), x,t,tau);
                % get matching data via interp1
                clear z0;
                for f = F:-1:1
                    for m = M:-1:1
                        xf = num2cell(gather(x  (:,:,:,f)),1);
                        tf = num2cell(gather(tau(:,:,m,:)),1);
                        z0(1,:,m,f) = cellfun(@(x,t) {interp1(x,1+t,terp_,0)}, xf, tf);
                    end
                end
                z0 = reshape(cat(2,z0{:}), [I,N,M,F]); % I x N x M x F

                for ord = ords'
                    [xp, tp] = dealfun(@(x)permute(x, ord), x, tau);
                    z1 = wsinterpd(xp, tp, find(ord == 1), 1, [], terp_, 0);
                    z1 = ipermute(z1, ord);
                    test.assertThat(...
                        double(gather(z1)), IsEqualTo(double(gather(z0)), 'Using', ...
                        NumericComparator('Within', RelativeTolerance(tol*gather(double(eps(cast(1,'like',z0)))))) ...
                        ));
                end
            end
        end
        function aperture_reduction(test, dev, prec)
            if prec == "halfT", return; end % not supported
            [us, b] = deal(test.dargs{3}{:});
            f = str2func(prec); b = f(b);
            if dev == "gpu", b = gpuArray(b); end
            z = slsc(b, 'ocl', dev == "ocl");
            w = pcf(b);
            m = dmas(b);
            r = cohfac(b);
            for d = [2 4]
                z = slsc(b, d, [0 2], "ensemble", 'ocl', dev == "ocl");
                w = pcf(b, d);
                m = dmas(b, d);
                r = cohfac(b, d);
            end
            test.assertError(@()pcf(real(b)), "QUPS:pcf:realInput"); % should fail
            
            if dev ~= "ocl"
                z = slsc(repmat(b,[ones(1,6),2]), 4, 2, "ensemble", 7);
            end
        end
        function correlator(test, prec, complexity, dev)
            x = test.dargs{3}{2};
            x = x + randn([1 1 4 1]); % unique expansion in dim 3
            if dev == "gpu", x = gpuArray(x); end
            switch complexity, case "real", x = real(x); end
            f = str2func(prec);
            x = f(x);

            % all permutations
            switch prec
                case "double", tol = 1e12;
                case "single", tol = 1e5;
                case "halfT" , tol = 1e4;
            end

            % test all sets of arguments
            L = 2;
            fargs = {'pad', 'zero', 'norm', 'tdim', 'ndim'};
            for ord = perms(1:2)'
            for i = uint64(0 : 2 ^ 3 - 1)
            for md = ["neighbor", "center", "x0"]
                fargs(2,:) = [num2cell(logical(bitget(i, 1:3))), num2cell(ord')];
                [tdim, ndim] = deal(fargs{2,4:5});
                y = pwznxcorr(x,L,'stride',2,"ref",md,"x0",sub(x,1,ndim),'ldim',5,fargs{:});
                test.assertNotEmpty(y, "Value return from pwznxcorr was empty (" + join(string(size(y))," x ") + ")");
                % test.assertFalse(anynan(y), "Deteced NaN value(s) ("+nnz(isnan(y))+").");
            end
            end
            end
        end
    
    end

    methods(Test, TestTags={'full', 'build', 'syntax', 'Github'})
        function imag_util_test(test)
            % test animate, dbr
            % 
            % animate function should find the image, or make one if it
            % can't find it. It should also permute data to match the size
            % of the image it finds.
            %
            % dbr should work with default or specified options

            hf = figure('Visible', 'off');
            [us, b] = deal(test.dargs{3}{:}); % get data
            ftls = "Frm " + (1:size(b,4)); % frame titles
            for tp = [true, false] % transpose
            for multi_image = [true, false] % multiple images
            for init_fig = [true, false] % initialize?
                [b0, scn] = deal(b, copy(us.scan));
                if tp, ord = [2,1,3,4]; b0=permute(b0,ord); scn.order=scn.order(ord(1:3)); end
                if multi_image, bs = {b0,b0}; else, bs = {b0}; end
                if init_fig, hs = {cellfun(@(b)imagesc(scn,b,nexttile()), bs)}; else, hs = {}; end
                itls = "View " + (1:numel(bs)); % image titles
                ttl_set = {"", ftls, ftls', itls, itls', ftls'+" | "+itls, ftls+" | "+itls'};
                for ttl = ttl_set
                    animate(bs, hs{:}, "loop", false,"fs",Inf,"fn",true,"title",ttl{1});
                end
                clf(hf);
            end
            end
            end

            % test that defaults work
            imagesc(us.scan, b); dbr;
            arrayfun(@dbr, ["b-mode", "phase", "echo"])
            
            close(hf)
        end
        function wbilerp_test(test, dev)

            % Create a grid
            [x , y ] = deal(-5:5, -4:4);
            [xa, ya] = deal( -4 ,  +1 );
            [xb, yb] = deal( +3 ,  -2 );

            % implicit move to gpu
            if dev == "gpu"
                [xa, ya, xb, xa] = dealfun(@gpuArray, xa, ya, xb, xa); 
            end
            wfuns = {@wbilerp};
            if dev ~= "none", wfuns{end+1} = @wbilerpg;

            for swp = [false, true], if swp
                    [x, xa, xb, y, ya, yb] = ...
                deal(y, ya, yb, x, xa, xb); 
            end
            for wfun = wfuns
            for i = uint64(0 : 2^4 - 1) % for all directions of the lines
                s = -1+2*double(bitget(i, 1:4)); % sign
                [cxy, ixo, iyo] = wfun{1}(x, y, ...
                    s(1)*xa, ...
                    s(2)*ya, ...
                    s(3)*xb, ...
                    s(4)*yb ...
                    );
            end
            end
            end
            end
        end
    end
end

% test GPU devices if we can
function s = getdevs()
s = "none";
if gpuDeviceCount, s(end+1) = "gpu"; end
if exist('oclDeviceCount', 'file') && oclDeviceCount()
    devs = oclDeviceTable();
    devs = sortrows(devs, ["Type", "MaxComputeUnits"]);
    oclDevice(devs{end,"Index"}); % select best device
    s(end+1) = "ocl";
end
s = cellstr(s);
end
