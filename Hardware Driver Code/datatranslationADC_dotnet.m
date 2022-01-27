%% Data Translation 9816 USB ADC
%   Version: alpha
%   Author: Patrick Parkinson (patrick.parkinson@manchester.ac.uk)
%
%   Class to use clocked ADC acquistion with 9816 series adc. This requires
%   the use of the dotnet driver, rather than the provided MATLAB drivers.
%
%   There are three modes of operation - get_single_value, get_one_buffer
%   and get_continuous. The first gets one number. The second gets a series
%   of data, clocked either internally or externally. The final provides a
%   method to stream data in.
%
%   Usage (read one from channel 0):
%       adc = datatranslationADC_dotnet();
%       adc.configure_single_read();
%       v0 = adc.get_single_value();
%
%   Usage (a buffer of 20000 data from channel 0):
%       adc = datatranslationADC_dotnet();
%       b = adc.get_one_buffer(20000,0);


classdef datatranslationADC_dotnet
    % Internal handles to device and subsystem
    properties %(Access = protected)
        device
        analogSystem
    end
    
    methods
        
        function obj=datatranslationADC_dotnet()
            % Initialise
            warning('off','MATLAB:NET:AddAssembly:nameConflict');
            % Add assembly (this is a local path - CHECK!)
            NET.addAssembly('C:\Program Files (x86)\Data Translation\DotNet\OLClassLib\Framework 2.0 Assemblies\OpenLayers.Base.dll');
            % Connect device
            obj.device = OpenLayers.Base.Device("DT9816-S(00)");
            % Connect ADC/DAC subsystem. Only one available.
            obj.analogSystem = obj.device.AnalogInputSubsystem(0);
        end
        
        function set_external_clock(obj,divider)               
            % Clock to external input, with divider as specified
            obj.analogSystem.Clock.Source = OpenLayers.Base.ClockSource.External;            
            % If a divider is provided, set it
            if nargin > 1
                obj.analogSystem.Clock.ExtClockDivider = divider;
            else
                obj.analogSystem.Clock.ExtClockDivider = 1;
            end
        end
        
        function set_internal_clock(obj,freq)
            % Clock to internal clock, with frequency as specified
            obj.analogSystem.Clock.Source = OpenLayers.Base.ClockSource.Internal;    
            obj.analogSystem.Clock.Frequency = freq;
        end
        
        function o= single_value(obj,chan)
            % Read single value from channel with gain 1 (assumed)
            o = obj.analogSystem.GetSingleValueAsVolts(chan,1);
        end
        
        function configure_single_read(obj,chan)
            % Device must be configured before use
            if nargin < 2
                chan = 0;
            end
            % Set up the system to work in single value mode
            obj.analogSystem.DataFlow = OpenLayers.Base.DataFlow.SingleValue;
            % Set clock
            obj.set_external_clock();
            % Add first analog system
            obj.analogSystem.ChannelList.Clear;
            obj.analogSystem.ChannelList.Add(chan);
            % Configure device (send config)
            obj.analogSystem.Config
        end
        
        function configure_continuous_read(obj, channels)
            % Page 185 openlayer manual
            if nargin < 2
                % If not provided, read from first 4 channels
                channels = [0,1,2,3];
            end
            % Set to continous
            obj.analogSystem.DataFlow = OpenLayers.Base.DataFlow.Continuous;
            % Set to single ended
            obj.analogSystem.ChannelType = OpenLayers.Base.ChannelType.SingleEnded;
            % Clear to list
            obj.analogSystem.ChannelList.Clear;
            % Add channels to read from
            for i =1:numel(channels)
                obj.analogSystem.ChannelList.Add(channels(i));
            end
            % Set up clock
            obj.set_external_clock();
            % Set software trigger
            obj.analogSystem.Trigger.TriggerType = OpenLayers.Base.TriggerType.Software;
            % Configure device (send config)
            obj.analogSystem.Config
        end
        
        function buffer = get_one_buffer(obj,samples,channel)
            % Read a single buffer (non-continous) from a specified channel
            if nargin < 3
                channel = 1;
            end
            % Get channel info
            channel_info = obj.analogSystem.SupportedChannels.GetChannelInfo(channel);
            % Get a single buffer. This resets to one channel as specified
            % above. The default timeout is approx 10ms per sample.
            buffer = obj.analogSystem.GetOneBuffer(channel_info,samples,samples/100);
        end
        
        function buffer = get_continuous(obj)
            % A continous read either requires two buffers, or a cyclic
            % buffer. As currently written this returns after one buffer
            %
            % Create a buffer with approx 0.1sec of data
            ol_buffer = OpenLayers.Base.OlBuffer(400,obj.analogSystem);
            % Add the buffer to the system queue
            obj.analogSystem.BufferQueue.FreeAllQueuedBuffers();
            obj.analogSystem.BufferQueue.QueueBuffer(ol_buffer);
            % Start acquisition
            tic();
            obj.analogSystem.Start();
            % Check if still running
            while obj.analogSystem.IsRunning
                pause(0.001);
            end
            % Return buffer
            buffer = ol_buffer;
        end

        function out=split_convert(~,buffer, chans)
            % If a buffer contains multiple channels, we can reshape the
            % output to separate these. "chans" is the number of channels.
            if nargin <3
                chans = 4;
            end
            % Reshape
            out = reshape(double(buffer.GetDataAsVolts),chans,[])';
        end
        
        function delete(obj)
            % Release the analog subsystem
            obj.analogSystem.Dispose();
            % Release the device
            obj.device.Dispose();
        end
    end
end