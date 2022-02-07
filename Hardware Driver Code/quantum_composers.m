%% Quantum Composers SCPI driver
%
% Author  : Patrick Parkinson (patrick.parkinson@manchester.ac.uk)
%
% Wrapper around the SCPI interface to quantum composers pulse generator.
% This is a basic framework for changing the channel delay - full SCPI
% details are available via:
%       https://www.quantumcomposers.com/pulse-delay-generator-emerald
%
%   Usage:
%       qc = quantum_composers("COM9");
%       qc.get_channel(1);
%       qc.set_channel_delay(1,50e-9);
%

classdef quantum_composers < handle
    
    properties (Access = private)
        % Serial port
        s;
    end
    
    properties (SetAccess = private)
        % Accessible details about available channels. Note, "virtual"
        % channels appear invisible.
        device_identity;
        channels = {};
    end
    
    properties (Access = private, Constant = true)
        % Constants of error codes. Fairly basic feedback.
        error_codes = {...
            'Incorrect prefix, i.e. no colon or * to start command.',...
            'Missing command keyword.',...
            'Invalid command keyword.',...
            'Missing parameter.',...
            'Invalid parameter.',...
            'Query only, command needs a question mark.',...
            'Invalid query, command does not have a query form.',...
            'Command unavailable in current system state.'};
    end
    
    methods
        
        function obj = quantum_composers(com_port)
            %
            if nargin == 0
                error('quantum_composers:quantum_composers:no_com_port',...
                    'A valid COM port must be passed.');
            end
            % Connect via com port passed. Settings provided by manual.
            obj.s = serialport(com_port,115200,'DataBits', 8, ...
                'Parity', 'none','StopBits',1);
            % Set terminator
            configureTerminator(obj.s,"CR/LF");
            % Test the device using a standard *IDN? command
            obj.device_identity = obj.s.writeread('*IDN?');
            
            % Get channels available on this device
            t = strsplit(obj.s.writeread(':INST:FULL?'),',');
            for i =1:2:numel(t)
                k = (i-1)/2+1;
                obj.channels{k} = t{i};
            end
        end
        
        function details = get_channel(obj,n)
            % Get all details about a given output channel
            details = struct();
            % We need to check if this is a virtual channel
            if n < numel(obj.channels)
                details.channel = obj.channels{n+1};
            else
                details.channel = sprintf('Virtual-%d',n);
            end
            details.state = obj.s.writeread(sprintf(':PULS%d:STAT?',n));
            % Check if stat failed - must be invalid channel
            if strcmp(details.state,'?1')
                error('quantum_composers:get_channel:invalid_channel','The queried channel does not exist');
            end
            % Get pulse width
            details.width = str2double(obj.s.writeread(sprintf(':PULS%d:WIDT?',n)));
            % Get pulse delay
            details.delay = str2double(obj.s.writeread(sprintf(':PULS%d:DEL?',n)));
            % Get pulse sync origin
            details.sync = obj.s.writeread(sprintf(':PULS%d:SYNC?',n));
            % Flip and convert due to endedness
            details.mux = reverse(dec2bin(str2double(obj.s.writeread(sprintf(':PULS%d:MUX?',n))),8));
            % Get pulse polarity
            details.polarity = obj.s.writeread(sprintf(':PULS%d:POL?',n));
            % Get pulse mode (burst etc.)
            details.mode = obj.s.writeread(sprintf(':PULS%d:CMOD?',n));
        end
        
        function set_channel_delay(obj,channel,delay)
            % Set the channel delay wrt t0
            r=obj.s.writeread(sprintf(':PULS%d:DEL %f',channel, delay));
            % Check for error
            obj.check_error('set_channel_delay',r);
        end
        
        function set_channel_state(obj,channel,state)
            % Set the channel state (on/off)
            if (state ~= true) && (state ~= false)
                error('quantum_composers:set_channel_state:state',...
                    'State must be 0 or 1');
            end
            r=obj.s.writeread(sprintf(':PULS%d:STAT %d',channel, logical(state)));
            % Check for error
            obj.check_error('set_channel_state',r);
        end
        
        
        function delete(obj)
            % Clean close serial port
            obj.s.flush();
            delete(obj.s);
        end
    end
    
    methods (Access = private)
    %% Private, internal functions    
        function check_error(obj,command,code)  
            % Check error codes
            if ~strcmp(code,'ok')
                error(...
                    sprintf('quantum_composers:%s:error',command),...
                    obj.error_codes{str2double(code(2))}...
                    );
            end            
        end
    end

end