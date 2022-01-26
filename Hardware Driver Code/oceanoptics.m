classdef oceanoptics < handle
    % Note, only implement a single spectrometer at present
    properties (Access=protected)
        % Connection parameters
        spec;
        sI=0;
        cI=0;
        bt;
        tec;
        % Internal storage variables - integration time and dark spectrum
        it=50e-3;
        tec_enabled = true;
        temp_enabled = true;
    end
    
    properties (Dependent=true, Access=public)
        % Depedant variable - set IT in seconds
        integration_time;
        temperature;
        tec_temperature;
    end
    
    properties (SetAccess=protected, GetAccess=public)
        % Wavelength scale, energy scale and cm scale
        wl;
        eV;
        cm;
        darkspec=0;
    end
    
    methods
        function connect(obj)
            % Open driver
            obj.spec = icdevice('OceanOptics_OmniDriver.mdd');
            % Connect
            connect(obj.spec);
            % Set up temperature thing
            obj.bt = get(obj.spec,'boardtemperature');
            obj.tec= get(obj.spec,'ThermoElectric');
            % Get wavelengths
            obj.wl = invoke(obj.spec, 'getWavelengths',obj.sI,obj.cI);
            obj.eV = 1239.84193./obj.wl;
            obj.cm = obj.eV * 8065.54;
            % Set standard integration time
            obj.setIT(obj.it);
        end
        
        function it = get.integration_time(obj)
            it = obj.it;
        end
        
        function t = get.temperature(obj)
            if ~obj.temp_enabled;t=-100;return;end
            try
                t = invoke(obj.bt,'getBoardTemperatureCelsius',obj.sI);
            catch
                obj.temp_enabled = false;
                t = -100;
                return
            end
        end
        
        function t = get.tec_temperature(obj)
            if ~obj.tec_enabled;t=-100;return;end
            try
                t = invoke(obj.tec,'getDetectorTemperatureCelsius',obj.sI);
            catch
                obj.tec_enabled = false;
                t = -100;
                return
            end
        end
        
        function set.integration_time(obj,it)
            % Check in range - in seconds
            if it>60
                warning('Integration time is over 1 minute');
            end
            if it<100e-6
                error('Integration time invalid');
            end
            obj.setIT(it);
            obj.it = it;
        end
        
        function close(obj)
            disconnect(obj.spec);
            delete(obj.spec);
        end
        
        function o=click(obj,avs)
            if nargin < 2
                avs = 1;
            end
            % Take actual data
            obj.tec_temperature;obj.tec_temperature;
            e = tic();
            sd = invoke(obj.spec,'getSpectrum',obj.sI);
            spectra   = zeros(numel(sd),avs);
            spectra(:,1) = sd;
            t_elapsed = toc(e);
          %  if t_elapsed < (2*obj.integration_time); warning('Too short?');end
            % Averaging
            a   = avs-1;k=1;
            while a > 0
                k=k+1;
                a = a - 1;
                sd = invoke(obj.spec,'getSpectrum',obj.sI);
                spectra(:,k) = sd;
            end
            if avs == 2
                sd = mean(spectra,2);
            elseif avs >2
                sd = median(spectra,2);
            end
            % Set x-axis
            o.wl      = obj.wl;
            o.eV      = obj.eV;
            o.cm      = obj.cm;
            % Set spectrum
            o.rawspec = sd;
            % Set parameters
            o.inttime = obj.it;
            o.time    = clock;
            o.avs     = avs;
            % Set dark spectrum (if applicable)
            if numel(obj.darkspec) == numel(sd);
                o.spec = sd - obj.darkspec;
            else
                o.spec = sd;
            end
            % Scale to per second
            o.spec = double(o.spec)./(obj.it);
        end
        
        function [o,cur_int]=auto_click(obj,int_range)
            % This function does not do averaging
            if nargin <2
                int_range = obj.integration_time;
            end
            if numel(int_range) == 1
                % Iterative approach
                cur_int   = int_range;
                int_range = [0.001, 1];    % 1ms to 10sec
            elseif numel(int_range) == 2
                cur_int   = int_range(2);
            elseif numel(int_range) == 3
                cur_int   = int_range(3);
                int_range = int_range(1:2);
            end
            attempts = 0;
            while attempts < 10;
                attempts = attempts+1;
                obj.integration_time = cur_int;
                o = obj.click();
                ma = max(o.spec*obj.it);
                if ma < 60000 && ma > 10000
                    break;
                elseif ma > 60000
                    % Overload
                    if cur_int > (10*int_range(1))
                        cur_int = cur_int/10;
                    elseif cur_int > int_range(1)
                        cur_int = int_range(1);
                    elseif cur_int == int_range(1)
                        break;
                    end
                elseif ma < 10000
                    % Underload
                    rat = 40000/ma;
                    if cur_int < (int_range(2)/rat)
                        cur_int = rat*cur_int;
                    elseif cur_int < int_range(2)
                        cur_int = int_range(2);
                    elseif cur_int == int_range(2)
                        break;
                    end
                end
            end
        end
        
        
        
        
        function show(obj,s)
            % Helper function
            if nargin == 1
                s = obj.click();
            end
            clf;
            plot(s.wl,s.spec);
            [ma,mp] = max(s.spec);
            mp = s.wl(mp);
            xlabel('Wavelength (nm)');
            ylabel('Spectral intensity (counts)');
            title(['OceanOptics spectrum (t=' ,num2str(s.inttime),'s, pk=', num2str(ma), ' @ ' ,num2str(mp),'nm)']);
            drawnow();
        end
        
        function dark(obj,enable)
            % Take or delete a dark spectrum (internal)
            if nargin < 2
                enable = 1;
            end
            if enable > 0
                s = obj.click(enable);
                obj.darkspec = s.rawspec;
            else
                obj.darkspec = 0;
            end
        end
    end
    
    methods (Access=protected)
        % Internal protected functions
        function setIT(obj,it)
            % Pass it in seconds, set in microseconds
            it=round(it*1e6);
            invoke(obj.spec,'setIntegrationTime',obj.sI,obj.cI, it);
        end
    end
    
    
end