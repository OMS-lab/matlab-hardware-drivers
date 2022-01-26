classdef labjack < handle
    properties
        ljudObj
        ljhandle
    end
    
    properties (Dependent = true, GetAccess = private)
        voltage;
    end
    
    methods 
        
        function obj = labjack()
            NET.addAssembly('LJUDDotNet');
            obj.ljudObj = LabJack.LabJackUD.LJUD;
            [ljerror, obj.ljhandle] = obj.ljudObj.OpenLabJackS('LJ_dtU6', 'LJ_ctUSB', '0', true, 0);
            if ~strcmp(ljerror,'NOERROR') 
                error(ljerror);
            end
        end
        
        function set.voltage(obj,v)
                obj.ljudObj.eDAC(obj.ljhandle, 1, v, 0, 0, 0);
                %obj.ljudObj.eDAC(0, 0, v, 0, 0, 0);
        end
        
        function on(obj)
            obj.ljudObj.eDAC(obj.ljhandle, 1, 5, 0, 0, 0);
        end

        function off(obj)
            obj.ljudObj.eDAC(obj.ljhandle, 1, 0, 0, 0, 0);
        end
        
        function delete(obj)
            obj.ljudObj.Close();
        end
    end
end