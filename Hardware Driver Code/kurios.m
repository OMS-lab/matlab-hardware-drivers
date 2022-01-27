%% Thor Labs Kurios over COM port
%   Version : 0.1
%   Author  : Patrick Parkinson (patrick.parkinson@manchester.ac.uk)
%
%   Usage, setting wavelength to 550nm
%       k = kurios();
%       k.wavelength = 550;
%
classdef kurios < handle
    
    properties (Access = private)
        % Serial port connection
        s
    end
    
    properties (Dependent = true)
        % Get/set wavelength
        wavelength;
    end
    
    methods 
        function obj = kurios()
            % Initialize connection
            obj.s = serialport('COM3',115200,'DataBits',8,'Parity','none',...
                'StopBits',1,'FlowControl','none');
            % Set terminator
            obj.s.configureTerminator("CR");
            % Send basic query to test connection
            obj.query('*IDN?');
        end
       
        function wl=get.wavelength(obj)
            % Get current wavelength
            wl = obj.query("WL?");
            wl = sscanf(wl,"%*[>WL]=%f");
        end
        
        function set.wavelength(obj,wl)
            % Set current wavelength (this version set to 420-720nm)
            if and(wl <=730,wl>=420)
                obj.query(sprintf("WL=%d",wl));
            else
                error("Out of range (420nm to 730nm)");
            end
        end
        
        function delete(obj)
            % Delete connection
            flush(obj.s);
        end
    end
    
%% Internal commands, not accessible
    methods (Access = private)
        
        function write(obj,cmd)
            % Write over serial port
            obj.s.write(strcat(cmd,string(char(13))),"char");
        end
        
        function o = read(obj)
            % Read from serial port
            o = obj.s.readline();
        end
        
        function o = query(obj,cmd)
            % Write, then read response
            obj.write(cmd);
            pause(0.1);
            o = obj.read();
        end
    end
end