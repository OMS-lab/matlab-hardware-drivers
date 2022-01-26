classdef kurios < handle
    properties (Access = private)
        s
    end
    
    properties (Dependent = true)
        wavelength;
    end
    
    methods 
        function obj = kurios()
            obj.s = serialport('COM3',115200,'DataBits',8,'Parity','none','StopBits',1,'FlowControl','none');
            obj.s.configureTerminator("CR");
            obj.query('*IDN?');
        end
       
        function wl=get.wavelength(obj)
            wl = obj.query("WL?");
            wl = sscanf(wl,"%*[>WL]=%f");
        end
        
        function set.wavelength(obj,wl)
            if and(wl <=730,wl>=420)
                obj.query(sprintf("WL=%d",wl));
            else
                error("Out of range");
            end
        end
        
        function delete(obj)
            flush(obj.s);
        end
    end
    
    
    methods (Access = private)
        function write(obj,cmd)
            obj.s.write(strcat(cmd,string(char(13))),"char");
        end
        
        function o = read(obj)
            o = obj.s.readline();
        end
        
        function o = query(obj,cmd)
            obj.write(cmd);
            pause(0.1);
            o = obj.read();
        end
    end
end