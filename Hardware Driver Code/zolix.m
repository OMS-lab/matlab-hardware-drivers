%% Driver for Zolix
%   Author : Patrick Parkinson
%   Email  : patrick.parkinson@manchester.ac.uk
%   V1 date: 14/08/2018
%
%   General driver for RS232 over USB control of Zolix spectrometer

classdef zolix < handle
    
    properties
        % Port to connect on
        port = 'COM29';
    end
    properties (Access = private)
        % Serial port (low-level)
        s=[];
        i_exitport=-1;
        i_grating =-1;
    end
    
    properties (SetAccess = private)
        gratings;
        sysinfo;
    end
    
    properties (Dependent = true)
        % Dependent properties - wavelength, grating and exit_port
        wavelength;
        grating;
        exit_port;
    end
    
    methods
        function obj=zolix(port)
            if nargin>0
                obj.port = port;
            end
            % Check if open, and connect if we already have
            f = instrfind();
            for i =1:prod(size(f))  %#ok<PSIZE>
                if ~strcmpi(f(i).Type,'serial')
                    continue;
                end
                if strcmpi(f(i).port,obj.port)
                    obj.s = f(i);
                    disp('Already open - reconnecting');
                    break
                end
            end
            % If not connected - make connection
            if isempty(obj.s)
                disp('Initiating connection to port');
                obj.s = serial(obj.port,'baudrate',19200,'databits',8,'parity','none','stopbits',1);
            end
            % We now have  port object - check if open
            if ~strcmp(obj.s.status,'open')
                disp('Opening port...');
                fopen(obj.s);
            end
            % Say hello
            obj.write('Hello');
            obj.read();
            % Get system details
            obj.write('SYSTEMINFO?');
            si = obj.read();
            obj.sysinfo = si(11:end-3);
            % Get grating details
            obj.write('GRATINGS?');
            r = obj.read();
            p = strfind(r,char(10));
            obj.gratings{1} = r(p(1)+3:p(2)-1);
            obj.gratings{2} = r(p(2)+3:p(3)-1);
            obj.gratings{3} = r(p(3)+3:end-3);
            % Initialize
            obj.grating;
            obj.exit_port;
        end
        
        function delete(obj)
            % Clean shutdown
            fclose(obj.s);
        end
        
        function wl=get.wavelength(obj)
            % Main "get" function
            obj.write('POSITION?');
            r = obj.read();
            l = strfind(r,'N');
            h = strfind(r,'OK');
            wl = str2double(r(l+1:h-2));
        end
        
        function set.wavelength(obj,nm)
            % Blocking, synchronous "set" function
            wl = sprintf('MOVETO %3.1f',nm);
            obj.write(wl);
            r=obj.read();
            if isempty(strfind(r,'OK'))
                disp(r);
                if strfind(r,'E03')
                    error('Grating out of range');
                end
                error('Could not seek wavelength');
            end
        end
        
        function port=get.exit_port(obj)
            % Main "get" function
            obj.write('EXITPORT?');
            r = obj.read();
            l = strfind(r,'RT');
            h = strfind(r,'OK');
            port = str2double(r(l+3:h-2));
            obj.i_exitport = port;
        end
        
        function set.exit_port(obj,port)
            % Blocking, synchronous "set" function
            if port == obj.i_exitport
                return;
            end                
            po = sprintf('EXITPORT %d',port);
            obj.write(po);
            r=obj.read();
            if isempty(strfind(r,'OK'))
                pause(1);
            end
        end
        
        function set.grating(obj,grating)
            if or(grating<1,grating > 3)
                error('No such grating');
            end
            if grating == obj.i_grating
                warning('Already in place');
                return;
            end
            gr = sprintf('GRATING %d',grating);
            obj.write(gr);
            r = obj.read();
            if isempty(strfind(r,'OK'))
                warning('Error in grating move');
                pause(1);
            end
        end
        
        function gr=get.grating(obj)
            obj.write('GRATING?');
            r = obj.read();
            l = strfind(r,'NG');
            h = strfind(r,'OK');
            gr = str2double(r(l+3:h-2));
            obj.i_grating = gr;
        end
        
        function home(obj)
            obj.write('GRATINGHOME');
            r = obj.read();
            if isempty(strfind(r,'OK'))
                pause(1);
            end
        end        
    end
    
    methods (Access=public)
        % Write to serial port (append terminator)
        function write(obj,command)
            fwrite(obj.s,[command,char(13)]);
        end
        
        % Read from serial port
        function r=read(obj)
            % Read from serial port - waiting for terminator
            while obj.s.BytesAvailable == 0;pause(0.001);end
            r = fread(obj.s,obj.s.BytesAvailable);pause(0.001);
            while (r(end) ~= 13)
                while obj.s.BytesAvailable == 0;pause(0.001);end
                r = [r;fread(obj.s,obj.s.BytesAvailable)]; %#ok<AGROW>
            end
            % Cut off delimiter for return
            r = r(1:end-1);
            % Convert to string
            r=[char(r)']; %#ok<NBRAK>
        end
    end
    
end