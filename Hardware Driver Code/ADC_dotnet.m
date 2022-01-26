%% Data Translation USB ADC
%   Author: Patrick Parkinson
%   Began : Jan 2022
%
%   Class to use timed-triggered acquisition
classdef ADC_dotnet
    % Internal handles to device and subsystem
    properties %(Access = protected)
        device
        analogSystem
    end
    
    methods
        
        function obj=ADC_dotnet()
            % Initialise
            warning('off','MATLAB:NET:AddAssembly:nameConflict');
            % Add assembly
            NET.addAssembly('C:\Program Files (x86)\Data Translation\DotNet\OLClassLib\Framework 2.0 Assemblies\OpenLayers.Base.dll');
            % Connect device
            obj.device = OpenLayers.Base.Device("DT9816-S(00)");
            % Connect ADC/DAC subsystem
            obj.analogSystem = obj.device.AnalogInputSubsystem(0);
        end
        
        function set_external_clock(obj,divider)               
            % Clock to external input, with divider as specified
            obj.analogSystem.Clock.Source = OpenLayers.Base.ClockSource.External;            
            % Set divider
            if nargin > 1
                obj.analogSystem.Clock.ExtClockDivider = divider;
            end
        end
        
        function set_internal_clock(obj,freq)
            % Clock to internal clock, with frequency as specified
            obj.analogSystem.Clock.Source = OpenLayers.Base.ClockSource.Internal;    
            %
            obj.analogSystem.Clock.Frequency = freq;
        end
        
        function o= single_value(obj,chan)
            % Read single value with gain 1 (assumed)
            o = obj.analogSystem.GetSingleValueAsVolts(chan,1);
        end
        
        function configure_single_read(obj,chan)
            if nargin < 2
                chan = 0;
            end
            % Set up the system to work in single value mode
            obj.analogSystem.DataFlow = OpenLayers.Base.DataFlow.SingleValue;
            % Set clock
            obj.set_external_clock(1);
            % Add first analog system
            obj.analogSystem.ChannelList.Clear;
            obj.analogSystem.ChannelList.Add(chan);
            % Configure device (send config)
            obj.analogSystem.Config
        end
        
        function configure_continuous_read(obj)
            % Page 185 openlayer manual
            % Set to continous
            obj.analogSystem.DataFlow = OpenLayers.Base.DataFlow.Continuous;
            % Set to single ended
            obj.analogSystem.ChannelType = OpenLayers.Base.ChannelType.SingleEnded;
            % Clear to list
            obj.analogSystem.ChannelList.Clear;
            % Add channels to read from
            obj.analogSystem.ChannelList.Add(0);
            obj.analogSystem.ChannelList.Add(1);
            obj.analogSystem.ChannelList.Add(2);
            obj.analogSystem.ChannelList.Add(3);
            % Set up clock
            obj.set_external_clock();
            % Set software trigger
            obj.analogSystem.Trigger.TriggerType = OpenLayers.Base.TriggerType.Software;
            % Configure device (send config)
            obj.analogSystem.Config
        end
        
        function buffer = get_one_buffer(obj,samples,channel)
            if nargin < 3
                channel = 1;
            end
            % Get channel info
            channel_info = obj.analogSystem.SupportedChannels.GetChannelInfo(channel);
            % Get a single buffer. This resets to one channel as specified
            % above.
            buffer = obj.analogSystem.GetOneBuffer(channel_info,samples,samples/100);
        end
        
        function buffer = get_continuous(obj)
            % Create a buffer with 0.1sec
            ol_buffer = OpenLayers.Base.OlBuffer(400,obj.analogSystem);
            % Add to queue
            obj.analogSystem.BufferQueue.FreeAllQueuedBuffers();
            obj.analogSystem.BufferQueue.QueueBuffer(ol_buffer);
            % Start
            tic();
            obj.analogSystem.Start();
            % Check if still running
            while obj.analogSystem.IsRunning
                pause(0.001);
            end
            % Return buffer
            buffer = ol_buffer;
        end

        function out=split_convert(~,buffer)
            out = reshape(double(buffer.GetDataAsVolts),4,[])';
        end
        
        function delete(obj)
            obj.analogSystem.Dispose();
            obj.device.Dispose();
        end
    end
end