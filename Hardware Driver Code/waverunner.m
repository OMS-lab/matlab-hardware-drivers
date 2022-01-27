%% Driver for LeCroy Waverunner 354A
%   Author : Patrick Parkinson
%   Email  : patrick.parkinson@manchester.ac.uk
%   V1 date: 24/07/2018
%
%   General driver for RS232 over USB control of LeCroy Waverunner 354A
%   oscilloscope. (Many commands will work for other LeCroy models)

classdef waverunner < handle
    properties 
        % Changable port to connect via (must install LeCroy USB drivers)
        port = 'COM4';
    end
    
    properties (Access = private)
        % Serial port (low-level)
        s=[];
        vs = [0 0 0 0];
        ts = 0;
        ch = 0;
        ml = 0;
    end
    
    properties (Dependent = true)
        % Dependent properties - timescale and voltagescale.
        timescale;
        voltscale;
        channel;
    end
    
    
    methods 
        % Constructor function - connect via serial, update time and
        % voltage
        function obj = waverunner()
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
            % Set up for standard readout
            disp('Done');
            obj.write('DTFORM BYTE');
            obj.write('DTSTART 0');
            obj.write(['DTPOINTS ',int2str(obj.memory_length)]);
            % Read/check basic parameters
            obj.channel;
            obj.timescale;
            obj.voltscale;
            
        end
        
        function reset(obj)
            % Reset internal state - if changed manually
            obj.vs = [0 0 0 0];
            obj.ts = 0;
            obj.ch = 0;
            obj.ml = 0;
            obj.timescale;
            obj.channel;
        end
        
        function o=memory_length(obj,s)
            % Read or write memory length
            if obj.ml > 0
                o = obj.ml;
            else
                % Check the memory length
                obj.write('MLEN?');
                r = obj.readstring(); 
                if strcmp(r(end),'K')
                    o = str2double(r(1:end-1))*1000;
                else
                    o = str2double(r);
                end
            end
            if nargin > 1
                % Set memory length
                if o ~= s
                    if s >= 1000
                        s = s/1000;
                        po = 'K';
                    else
                        po = '';
                    end
                    obj.write(['MLEN ',int2str(s),po]);
                    obj.write('MLEN?');
                    o = str2double(obj.readstring());
                    obj.ml = o;
                end
            end            
        end
        
        function o=offset(obj)
            % Get voltage offset
            obj.write('OFST?');
            o = str2double(obj.readstring());
        end
        
        function d=data(obj,src)
            % Take data
            if nargin < 2
                % Get all
                src = [1,2,3,4];
            end
            % Initialize
            meml = obj.memory_length();
            d = zeros(numel(src)+1,meml);
            % Iterate over channels
            for i =1:numel(src)
                % Set channel
                obj.channel = src(i);
                % Set number of points to read points
                obj.write(['DTPOINTS ',int2str(meml)]);
                % Check points
                obj.write('DTPOINTS?');
                pts = str2double(obj.readstring());
                of  = obj.offset();
                % If
                if pts > 0
                    obj.write('DTWAVE?');
                    data = double(obj.read(pts+12));
                    d(i+1,1:pts) = (data(11:pts+10))*obj.voltscale/256-of;
                end
            end
            d(1,:) = (0:meml-1).*double(obj.timescale)*100/meml;
        end
        
        function o= get.channel(obj)
            % Get the current input channel.
            if obj.ch>0
                o = obj.ch;
            else
                obj.write('WAVESRC?');
                o=obj.readstring();
                o=str2double(o(end));
                obj.ch = o;
            end
        end
        
        function set.channel(obj,ch)
            % Set the current input channel
            if ch ~= obj.ch
                obj.write(['WAVESRC CH',int2str(ch)]);
                obj.ch = ch;
            end
        end
        
        function o=get.timescale(obj)
            % Readf the timescale
            if obj.ts > 0
                o = obj.ts;
            else
                obj.write('TDIV?');
                o = str2double(obj.readstring());
                obj.ts = o;
            end
        end
        
        function o=get.voltscale(obj)
            % Read the voltage scale
            if obj.vs(obj.ch) > 0
                o = obj.vs(obj.ch);
            else
                obj.write('VDIV?');
                o = str2double(obj.readstring());
                obj.vs(obj.ch) = o;
            end
        end
               
    end
    %% Low level commands
    methods (Access=private)
        
        % Write to serial port (append terminator)
        function write(obj,command)
            fwrite(obj.s,[command,newline]);
        end
        
        % Read from serial port
        function r=read(obj,chars)
            % Read from serial port - waiting for terminator if chars is
            % missing or zero, or read a certain number of characters
            % otherwise
            if nargin<2
                chars = 0;
            end
            if chars == 0
                while obj.s.BytesAvailable == 0;pause(0.001);end
                r = fread(obj.s,obj.s.BytesAvailable);pause(0.001);
                while (r(end) ~= 13)
                    while obj.s.BytesAvailable == 0;pause(0.001);end
                    r = [r;fread(obj.s,obj.s.BytesAvailable)]; %#ok<AGROW>
                end
            else
                % Use for data readout = should be in int8 format relative
                % to screen centre
                r = fread(obj.s,chars,'int8');
            end
            % Cut off delimiter for return
            r = r(1:end-2);
        end
           
        function r =readstring(obj)
            % Convinience function to convert returned data to string
            r=[char(obj.read())']; %#ok<NBRAK>
        end
    end
    
    
end