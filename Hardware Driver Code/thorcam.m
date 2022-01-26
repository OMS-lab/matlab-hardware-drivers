%% MATLAB camera
classdef thorcam < handle
    
    properties
        cam;
        MemID;
        iminfo;
    end
    properties (Dependent = true)
        exposure;
    end
    methods
        function obj=thorcam()
            NET.addAssembly('C:\Program Files\Thorlabs\Scientific Imaging\ThorCam\uc480DotNet.dll');
            obj.cam = uc480.Camera;
            obj.cam.Init(0);
            obj.cam.Display.Mode.Set(uc480.Defines.DisplayMode.DiB);
            obj.cam.PixelFormat.Set(uc480.Defines.ColorMode.RGBA8Packed);
            obj.cam.Trigger.Set(uc480.Defines.TriggerMode.Software);
            [~,obj.MemID] = obj.cam.Memory.Allocate(true);
            obj.iminfo = struct('Width',0,'Height',0,'Bits',0);
            [~,obj.iminfo.Width, obj.iminfo.Height, obj.iminfo.Bits,~] = obj.cam.Memory.Inquire(obj.MemID);
        end
        
        function im=get(obj)
            obj.cam.Acquisition.Freeze(uc480.Defines.DeviceParameter.Wait);
            [~,tmp] = obj.cam.Memory.CopyToArray(obj.MemID);
            data = reshape(uint8(tmp),[obj.iminfo.Bits/8,obj.iminfo.Width,obj.iminfo.Height]);
            data = data(1:3,1:obj.iminfo.Width,1:obj.iminfo.Height);
            im = permute(data,[3,2,1]);
        end
        
        function delete(obj)
            obj.cam.Exit();
        end
        
        function exp=get.exposure(obj)
            [~,exp]=obj.cam.Timing.Exposure.Get();
        end
        
        function set.exposure(obj,time)
            [~,range]=obj.cam.Timing.Exposure.GetRange();
            if or(time>range.Maximum,time<range.Minimum)
                error('Out of range');
            end
            a=obj.cam.Timing.Exposure.Set(time);
            if ~strcmp(a,'SUCCESS')
                error('Failure');
            end
        end
                
    end
end