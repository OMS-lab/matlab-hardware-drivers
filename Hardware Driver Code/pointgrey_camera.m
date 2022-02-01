%% Point Grey Camera Driver
%  Author     :   Patrick Parkinson (patrick.parkinson@manchester.ac.uk)
%
%  The driver accesses the camera through the MATLAB IMAQ interface. This requires
%  the image acquisition toolbox, and image processing toolbox to be
%  installed, as well as the point grey driver.
%  It has been tested to work with MATLAB 2015 and above only, due to the
%  change in IMAQ driver.
%
%   Usage:
%       cam = pointgrey_camera();
%       cam.connect();
%       v = cam.get();
%       imagesc(v.data);
%
classdef pointgrey_camera < handle
    
    properties (Access = protected)
        % Internal connections to the IMAQ driver
        video_device;
        video_source;
        ds = 1;
        inv = 0;
        im_size = [];
    end
    
    properties (GetAccess = public, SetAccess= protected)
        % Useful variables (read-only)
        ready   = 0;
        started = 0;
    end
    
    properties (Dependent = true)
        % Dependent parameters. Shutter (ms), gain (dB).
        shutter;
        gain;
        mode;
        gamma;
        downsample;
        invert;
    end
    
    methods
        function connect(obj)
            % Connect to device
            a = imaqhwinfo('pointgrey');
            if numel(a.DeviceIDs) == 0
                error('pointgrey_camera:connect:not_available','Camera is not available. Check power');
            end
            
            % PointGrey device.
            obj.video_device = videoinput('pointgrey', 1);
            obj.video_source = getselectedsource(obj.video_device);
            
            % Set up trigger to be manual (for now).
            triggerconfig(obj.video_device, 'immediate');
            obj.video_device.FramesPerTrigger = 1;
            % If we get to here, we're good.
            obj.ready = 1;
            % Turn off framerate mode
            set(obj.video_source,'FrameRateMode','Off');
            % Get image size (and flush buffer)
            a = obj.get();
            obj.im_size = size(a.data);
        end
        
        function set.mode(obj,mode)
            % Change the underlying operation mode
            obj.setmode(mode);
        end
        
        function m=get.mode(obj)
            % Read from driver name
            v = obj.video_device.Name;
            m = str2double(v(strfind(v,'Mode')+4));
        end
        
        function set.invert(obj,inv)
            % Inverting image
            if inv == 0
                obj.inv = 0;
            elseif inv==1
                obj.inv = 1;
            else
                error('pointgrey_camera:set.invert:unknown','Unknown option'); %#ok<CTPCT>
            end
        end
        
        function inv=get.invert(obj)
            % Get invert status
            inv = obj.inv;
        end
        
        function setmode(obj,mode)
            % Set the mode of the camera. I only use 0,5,7.
            if not((mode == 0)| (mode==5) | (mode==7))
                error('pointgrey_camera:setmode:unknown_mode','Only modes 0, 5 and 7 recognised/supported');
            end
            % Current mode
            if mode == obj.mode
                % Already in mode, skip
                return;
            end
            if mode == 0
                % Standard mode. Full sensor, 16bit
                st = 'F7_Mono16_1928x1448_Mode0';
            elseif mode==5
                % Binned mode, 4x4 binning, 16bit
                st = 'F7_Mono16_480x362_Mode5';
            elseif mode == 7
                % Slow mode, low noise, full sensor, 12bit.
                st = 'F7_Mono12_1928x1448_Mode7';
            end
            % Close old device
            delete(obj.video_device);
            % Open new device
            obj.video_device = videoinput('pointgrey',1,st);
            obj.video_source = obj.video_device.Source;
            triggerconfig(obj.video_device, 'immediate');
            obj.video_device.FramesPerTrigger = 1;
            set(obj.video_source,'FrameRateMode','Off');
            obj.ready = 1;
            % Get image size (and flush buffer)
            a = obj.get();
            obj.im_size = size(a.data);
        end
        
        function g = get.gamma(obj)
            % Get the gamma parameter
            g = get(obj.video_source,'Gamma');
        end
        
        function s=get.shutter(obj)
            % Read from the shutter parameter
            s = get(obj.video_source,'Shutter');
        end
        
        function set.shutter(obj,s)
            % Set the shutter parameter, in ms.
            % Auto rate if 'a'.
            if strcmp(s,'a')
                set(obj.video_source,'FrameRateMode','Off');
                set(obj.video_source,'ShutterMode','Auto');
                return;
            end
            
            % Turn off auto framerate first.
            set(obj.video_source,'FrameRateMode','Off');
            set(obj.video_source,'ExposureMode','Off');
            set(obj.video_source,'ShutterMode','Manual');
            bounds = propinfo(obj.video_source,'Shutter');
            if s < bounds.ConstraintValue(1) || s> bounds.ConstraintValue(2)
                error('pointgrey_camera:set_shutter:out_of_range',['Shutter value out of acceptable range (',num2str(bounds.ConstraintValue(1)),'-',num2str(bounds.ConstraintValue(2)),')']);
            end
            set(obj.video_source,'Shutter',s);
        end
        
        function ds=get.downsample(obj)
            % Read downsampling
            ds = obj.ds;
        end
        function set.downsample(obj,val)
            % Write downsampling
            old_downsamples  = obj.ds;
            obj.ds = round(val);
            if old_downsamples ~= obj.ds
                obj.im_size = obj.im_size.*(old_downsamples/obj.ds);
            end
        end
        
        function s=get.gain(obj)
            % Read gain in dB
            s = get(obj.video_source,'Gain');
        end
        
        function set.gain(obj,g)
            % Set the gain parameter.
            bounds = propinfo(obj.video_source,'Gain');
            % Auto gain if 'a'
            if strcmp(g,'a')
                set(obj.video_source,'GainMode','Auto');
                return;
            end
            % Check if in range
            if g < bounds.ConstraintValue(1) || g> bounds.ConstraintValue(2)
                error('pointgrey_camera:set_gain:out_of_range','Gain value out of acceptable range');
            end
            set(obj.video_source,'GainMode','Manual')
            set(obj.video_source,'Gain',g);
        end
        
        function delete(obj)
            % Clean delete
            delete(obj.video_device);
        end
        
        function o=get(obj,averages)
            % Main 'get' function, returns 'raw' data.
            if ~obj.ready
                error('pointgrey_camera:get:not_ready','Camera not ready');
            end
            if nargin < 2
                averages = 1;
            end
            % Go
            o = struct('x',[],'y',[],'data',[],...
                'acq_settings',struct('ts',[],'gain', obj.gain,...
                'shutter', obj.shutter,'mode',obj.mode,'acqtime',0));
            % Time the acquisition
            s      = tic();
            % How many frames
            obj.video_device.FramesPerTrigger = averages;
            % Get a frame
            flushdata(obj.video_device);
            start(obj.video_device);
            % Wait to complete
            while ~strcmp(obj.video_device.Running,'off')
                pause(min(0.005,obj.shutter/1000));
            end
            stop(obj.video_device);
            % Get data
            o.data = getdata(obj.video_device,averages,'uint16');
            if obj.inv == 1
                o.data = 2^16-o.data;
            end
            o.acq_settings.acqtime = toc(s);
            % Median filter to average
            if averages > 1
                o.data = median(o.data,4);
            end
            % Downsample if required
            if obj.ds == 2
                o.data = int32(o.data);
                o.data = o.data(1:obj.ds:end-1,1:obj.ds:end-1)+...
                    o.data(1:obj.ds:end-1,2:obj.ds:end)+...
                    o.data(2:obj.ds:end,1:obj.ds:end-1)+...
                    o.data(2:obj.ds:end,2:obj.ds:end);
            end
            % Remove 1 1 pixel - often used for non-image data
            o.data(1,1) = o.data(1,2);
            % Other data
            o.acq_settings.ts = now();
            
        end
        
        function m = get_metadata(obj)
            % Read camera metadata as a structure
            m = struct('gain',obj.gain,'mode',obj.mode, 'gamma',obj.gamma,...
                'downsample',obj.downsample,'invert',obj.invert,'shutter',obj.shutter);
        end
        
        % Lower-level preview functions
        function preview(obj,handle)
            if nargin > 1
                preview(obj.video_device,handle);
            else
                preview(obj.video_device);
            end
        end
        
        function stop_preview(obj)
            stoppreview(obj.video_device);
            closepreview(obj.video_device);
        end
    end
    
end