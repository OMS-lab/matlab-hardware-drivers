%% Driver for Acton2150
%   Author : Patrick Parkinson
%   Email  : patrick.parkinson@manchester.ac.uk
%   V1 date: 26/07/2018
%
%   General driver for RS232 over USB control of Acton2150 spectrometer

classdef acton2150 < handle
    
    properties
        % Port to connect on
        port = 'COM24';
    end
    properties (Access = private)
        % Serial port (low-level)
        s=[];
    end
    
    properties (Dependent = true)
        % Dependent properties - timescale and voltagescale.
        wavelength;
    end
    
    methods
        function obj=acton2150(port)
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
                obj.s = serial(obj.port,'baudrate',9600,'databits',8,'parity','none','stopbits',1);
            end
            % We now have  port object - check if open
            if ~strcmp(obj.s.status,'open')
                disp('Opening port...');
                fopen(obj.s);
            end
        end
        
        function delete(obj)
            % Clean shutdown
            fclose(obj.s);
        end
        
        function wl=get.wavelength(obj)
            % Main "get" function
            obj.write('?NM');
            r = obj.read();
            l = strfind(r,'n');
            wl = str2double(r(1:l-1));
        end
        
        function set.wavelength(obj,nm)
            % Blocking, synchronous "set" function
            wl = sprintf('%3.1f',nm);
            obj.write([wl,' GOTO']);
            r=obj.read();
            if isempty(strfind(r,'ok'))
                error('Couldntmove');
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
            while (r(end) ~= 10)
                while obj.s.BytesAvailable == 0;pause(0.001);end
                r = [r;fread(obj.s,obj.s.BytesAvailable)]; %#ok<AGROW>
            end
            % Cut off delimiter for return
            r = r(1:end-2);
            % Convert to string
            r=[char(r)']; %#ok<NBRAK>
        end
    end
    
end