%% Class to connect to LabJack U6 model via dotnet drivers
%   Version : 0.1
%   Author  : Patrick Parkinson (patrick.parkinson@manchester.ac.uk)
%
%   Usage (setting output 1 to 5V):
%       lj = labjack();
%       lj.voltage = 5;
%
classdef labjack < handle
    
    properties (Access = private)
        % Connection to labjack
        ljudObj
        ljhandle
    end
    
    properties (Dependent = true, GetAccess = private)
        % Set-only voltage
        voltage;
    end
    
    methods
        
        function obj = labjack()
            % Initialize and connect
            % Add dotnet assembly
            NET.addAssembly('LJUDDotNet');
            % Get object
            obj.ljudObj = LabJack.LabJackUD.LJUD;
            % Open/connect
            [ljerror, obj.ljhandle] = obj.ljudObj.OpenLabJackS('LJ_dtU6', 'LJ_ctUSB', '0', true, 0);
            if ~strcmp(ljerror,'NOERROR')
                error(ljerror);
            end
        end
        
        function set.voltage(obj,v)
            % Set DAC on channel 1
            obj.ljudObj.eDAC(obj.ljhandle, 1, v, 0, 0, 0);
        end
        
        function on(obj)
            % Set channel 1 to 5V (TTL on)
            obj.ljudObj.eDAC(obj.ljhandle, 1, 5, 0, 0, 0);
        end
        
        function off(obj)
            % Set channel 1 to 0V (TTL off)
            obj.ljudObj.eDAC(obj.ljhandle, 1, 0, 0, 0, 0);
        end
        
        function delete(obj)
            % Destroy object
            obj.ljudObj.Close();
        end
    end
end