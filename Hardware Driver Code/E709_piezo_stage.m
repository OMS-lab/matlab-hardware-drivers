%% Piezo Stage (Physik Instrumente E-709 controller)
%   Author  : Patrick Parkinson (patrick.parkinson@manchester.ac.uk)
%   Date    : 19/04/2018
%   Version : 0.1
%   License : CC-BY-SA (http://creativecommons.org/licenses/by-sa/4.0/)
%   
%   This MATLAB class provides a handle-based approach to connecting with
%   PI E-709 controllers. The purpose is to provide a selection of the most
%   relevant methods and properties, such as connection, movement, velocity
%   setting, and low-level commands.
%
%   This class wraps the provided lower-level commands provided by PI 
%
%   Changelog:
%       15/10/2018 : Allow for reusing existing waveform if it exists (cuts
%       communcation time by ~10sec/scan. [PWP]

classdef E709_piezo_stage < handle
    
    properties (GetAccess=public)
        controllerSerialNumber = '117071743';
        Controller  = [];   % Controller connection
         E709       = [];   % Connection to stage
         axisname   = [];   % Internal axis name
         IIR_filter_status = 0;
         dMin       = 0;    % Minimum position
         dMax       = 0;    % Maximum position
         position_trigger = 0;
         last_wav   = struct();
    end

    properties
         sync       = 0;    % Perform synchronous moves
         velocity_limit=1000;  % Velocity limit (mm/s)
    end
    
    properties (Dependent=true)
        position            % Position of stage (mm)
        velocity            % Velocity of stage (mm/s)
        moving              % Boolean (true/false)
    end
    
    properties (Dependent=true,SetAccess = private)
        analog              % Analog 
    end
    
    methods
        % Initialise 
        function obj=E709_piezo_stage()
            % Add driver code to the matlab path (make it accessible)
            addpath('C:\Users\Public\PI\PI_MATLAB_Driver_GCS2');

            % See if controller already connected
            if(~isa(obj.Controller,'PI_GCS_Controller'))
                obj.Controller = PI_GCS_Controller();
            end

            % Connection settings
            boolE709connected = false;
            
            % Check if stage connected
            if ~isempty(obj.E709)
                if (obj.E709.IsConnected)
                    boolE709connected = true;
                end
            end
            
            % Otherwise - connect now
            if (~boolE709connected)
                    obj.E709 = obj.Controller.ConnectUSB(obj.controllerSerialNumber);
            end
            
            % Stage initialisation
            obj.E709 = obj.E709.InitializeController();
            obj.axisname = '1';
            obj.stop();
            % switch on servo
            obj.servo(1);
            % Read stage max and min
            obj.dMin = obj.E709.qTMN(obj.axisname);
            obj.dMax = obj.E709.qTMX(obj.axisname);
        end
        
        function servo(obj,state)
            % Set Servo state
            if state
                state = 1;
            else
                state = 0;
            end
            obj.E709.SVO(obj.axisname,state);
        end
        
        function delete(obj)
            obj.stop();
            disp('Removing PI from memory');
            obj.Controller.Destroy;
        end
        
        function p=get.position(obj)
            p=obj.E709.qPOS(obj.axisname);
        end
        
        function set.position(obj,p)
            % Second check if position is in range
            if ~and(p>obj.dMin ,p<obj.dMax)
                error('Destination out of range');
            end
            % Perform move
            obj.E709.MOV(obj.axisname, p);
            % If synchronous, wait
            if obj.sync == 1
                while(0 ~= obj.E709.IsMoving(obj.axisname))
                    pause(0.1);
                end
            end
        end
        
        function o=get.moving(obj)
            % Check if device is moving
            o=logical(obj.E709.IsMoving(obj.axisname));
        end
        
        function v=get.velocity(obj)
            % Query stage velocity
            v = obj.E709.qVEL(obj.axisname);
        end
        
        function set.velocity(obj,v)
            % Set maximum velocity (only valid in PID_pos_vel)
            if v<=obj.velocity_limit
                obj.E709.VEL(obj.axisname,v);
            else
                error('Velocity exceeds velocity limit');
            end
        end
        
        function stop(obj)
            % Stop the movement (check wavetable first)
            if obj.E709.qWGO(1)
                obj.E709.WGO(1,0);
            end
            obj.E709.STP();
        end
        
        function halt(obj)
            % Turn off the servo, and stop the movement
            obj.servo(0);
            obj.stop();
        end
        
        function r=query_parameter(obj,code)
            % Low level query of parameters in volatile memory. Read by
            % code, passed as a char string
            if ~isa(code,'char')
                error('Pass code as a string (not including 0x)');
            end
            code = uint32(hex2dec(code));
            r    =obj.E709.qSPA(obj.axisname,code);
        end
    
        function set_pulse_distance(obj,channel,distance,lims)
            % Set to output a TTL signal on given channel every "distance"
            % in um units
            if nargin<4
                lims      = [];
            end
            if or(channel < 1,channel > 2)
                error('Channel not recognised - use 1-2');
            end
            channel = uint8(channel);
            obj.E709.CTO(channel,2,1);              % Configure digital line
            obj.E709.CTO(channel,3,0);              % Distance mode
            obj.E709.CTO(channel,1,distance);       % Set distance
            if numel(lims) > 0
                obj.E709.CTO(channel,8,lims(1));           
                obj.E709.CTO(channel,9,lims(2));              
            else
                obj.E709.CTO(channel,8,0);           
                obj.E709.CTO(channel,9,0);                    
            end
            obj.position_trigger = distance;
        end
        
        function waveform(obj,startpos,stoppos,freq,binning)
            % Create and run a new triangle waveform.
            % This creates triggers for +ve and -ve going movement
            if obj.moving
                warning('Stopping current movement');
                obj.stop();
            end
            
            % Arbitrary overshoot of 10 bins
            overshoot = 10*binning;
            x2        = startpos-overshoot;
            x3        = stoppos +overshoot;
            v         = abs(x3-x2)*freq;
            
            % Set up trigger lines
            obj.set_pulse_distance(1,binning,[startpos stoppos]);   % Increasing
            obj.set_pulse_distance(2,binning,[stoppos startpos]);   % Decreasing
            
            % Activate
            % Go to start position
            obj.sync     = 1;
            obj.velocity = obj.velocity_limit;
            obj.position = x2;
            
            % Set up waveform table
            obj.velocity        = v;
            amplitude           = x3-x2;
            offset              = x2;
            if freq < 1.21
                % Need to do wtr
                wtr=ceil(1.21/freq);
                disp('Changing wtr');
                obj.E709.WTR(0,wtr*5,0);
                freq = freq*wtr;
            else
                obj.E709.WTR(0,5,0);
            end
            seglength           = round(4936/freq);
            if seglength > 4096;error('piezo_stage:waveform:seglength','Seglength max 4096');end
            speedupdown         = 64;      % ARBITRARY
            curvecentrepoint    = round(seglength/2);
            
            wav = struct('seglength',seglength,...
                'curvecentrepoint',curvecentrepoint,...
                'speedupdown',speedupdown,...
                'amplitude', amplitude,...
                'offset',offset);
            if isequal(wav,obj.last_wav)
                s='existing waveform last';
            else
                s='Uploaded new waveform';
                obj.E709.WAV_RAMP(1,0,seglength,int32('X'),curvecentrepoint, speedupdown, amplitude, offset, seglength);
                obj.last_wav = wav;
            end

            % WSL 1 1  - Connect generator to table
            obj.E709.WSL(1,1);
            % WGC 1 0  - Run ad infinitum
            obj.E709.WGC(1,0);
            % WGO 0 1  - Start immediately
            obj.E709.WGO(1,1);
            
            disp(['Waveform active -',s]);
        end
        
        function v=get.analog(obj)
            v = obj.E709.qTNS(2)/10;
        end
    end
    
end