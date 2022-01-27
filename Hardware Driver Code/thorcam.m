%% ThorCam class wrapper for uc480 driver
%   Version : Release
%   Author  : Patrick Parkinson (patrick.parkinson@manchester.ac.uk)
%
%   This code is tested with basic USB-based ThorLabs cameras. It uses a 
%   dotnet driver for the uc480 controller, and is effectively a simple wrapper.
%
%   Usage - taking and displaying one image:
%       cam = thorcam();
%       im = cam.get();

classdef thorcam < handle
    
    properties (Access=private)
        % Internal variables
        cam;
        MemID;
        iminfo;
    end
    
    properties (Dependent = true)
        exposure;
    end
    
    methods
        function obj=thorcam()
            % Initialize
            % Add dotnet assembly
            NET.addAssembly('C:\Program Files\Thorlabs\Scientific Imaging\ThorCam\uc480DotNet.dll');
            % Get camera
            obj.cam = uc480.Camera;
            % Initialize
            obj.cam.Init(0);
            % Set modes and triggers
            obj.cam.Display.Mode.Set(uc480.Defines.DisplayMode.DiB);
            obj.cam.PixelFormat.Set(uc480.Defines.ColorMode.RGBA8Packed);
            obj.cam.Trigger.Set(uc480.Defines.TriggerMode.Software);
            % Get a memory buffer
            [~,obj.MemID] = obj.cam.Memory.Allocate(true);
            % Get image information
            obj.iminfo = struct('Width',0,'Height',0,'Bits',0);
            [~,obj.iminfo.Width, obj.iminfo.Height, obj.iminfo.Bits,~] = obj.cam.Memory.Inquire(obj.MemID);
        end
        
        function im=get(obj)
            % Acquire one image
            obj.cam.Acquisition.Freeze(uc480.Defines.DeviceParameter.Wait);
            % Copy image to data
            [~,tmp] = obj.cam.Memory.CopyToArray(obj.MemID);
            % Manipulate data to image format
            data = reshape(uint8(tmp),[obj.iminfo.Bits/8,obj.iminfo.Width,obj.iminfo.Height]);
            data = data(1:3,1:obj.iminfo.Width,1:obj.iminfo.Height);
            im = permute(data,[3,2,1]);
        end
        
        function delete(obj)
            % Clean close/destroy
            obj.cam.Exit();
        end
        
        function exp=get.exposure(obj)
            % Get current exposure time
            [~,exp]=obj.cam.Timing.Exposure.Get();
        end
        
        function set.exposure(obj,time)
            % Set image exposure time, checking range
            [~,range]=obj.cam.Timing.Exposure.GetRange();
            if or(time>range.Maximum,time<range.Minimum)
                error("thorcam:set_exposure:out_of_range",'Exposure requested is out of range');
            end
            % Set exposure
            a=obj.cam.Timing.Exposure.Set(time);
            if ~strcmp(a,'SUCCESS')
                error('Failure');
            end
        end
                
    end
end