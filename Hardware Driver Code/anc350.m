%% Class to connect to Attocube ANC350 positioner
%   Version : 0.1
%   Created : 23/09/2020
%   Author  : Patrick Parkinson (patrick.parkinson@manchester.ac.uk)
%
%/Users/user/Documents/GitHub/matlab-hardware-drivers/Hardware Driver Code/ADC_dotnet.m
%   Note, axes are defined in mm, so um is 1e-3, and nm is 1e-6.
%   Usage:
%       atto = anc350();
%       disp(atto.position);
%       disp(atto.status);
%       atto.position = [0.0 1e-3];
%       delete(atto);

classdef anc350 < handle
     properties (Hidden=true)
            handle;
            servo = [0 0 0];
            zero  = [0 0 0];               
     end
     
     properties (Dependent=true)
         position
     end
     
     properties (Dependent = true, SetAccess = private)
         status
         voltage
     end
         
    methods
        function obj=anc350()
            % Load the library. Requires anc350v4.dll, anc350res.h,
            % ancdecl.h on the path and a C compiler
            if ~libisloaded('anc350v4')
                loadlibrary('anc350v4.dll','anc350res.h','addheader','ancdecl.h');
            end
            % Discover ANC350 on usb
            [err,o]=calllib('anc350v4','ANC_discover',1,0);
            obj.checkerr(err);
            % We need a single device
            if o~=1;error('anc350:initialise:no_device_found','Need to find just 1 device');end
            % Get device info
            [err,devType, ~, ~,~,~]=calllib('anc350v4','ANC_getDeviceInfo',0,0,0,0,0,0);
            obj.checkerr(err);
            fprintf('Found %s',devType);
            % Connect
            vp=libpointer('voidPtr');
            [err,~]=calllib('anc350v4','ANC_connect',0,vp);
            obj.checkerr(err);
            obj.handle = vp;
            fprintf(' : connected');
            % Check if connected
            [err,~,id, serNum,~,Conn]=calllib('anc350v4','ANC_getDeviceInfo',0,0,0,0,0,0);
            obj.checkerr(err);            
            if ~Conn
                error('anc350:initialise:not_connected','Could not connect to device');
            end
            fprintf(' : ID %d (#%d)\n',id,serNum);
            % Enable servos
            for i =1:3
                obj.set_servo(i-1,1);
                obj.servo(i) = 1;
            end
        end
        
        function servos_on(obj)
            for i =1:3
                obj.set_servo(i-1,1);
                obj.servo(i) = 1;
            end
        end
        
        function delete(obj)
            % Clean up
            err=calllib('anc350v4','ANC_disconnect',obj.handle);
            obj.checkerr(err);
        end
        
        function p=get.position(obj)
            % Get 3-axis position. Note internally 0 based, MATLAB 1-based
            p = zeros(3,1);
            for i = 1:3
                p(i)=obj.get_position(i-1);
            end
            p = (p-obj.zero');
        end
        
        function set_voltage(obj,axis,voltage)
            % Set a DC voltage for fine positioning mode
            if voltage<-0.1 || voltage>60.1
                error('anc350:set_voltage:out_of_range','Applied voltage is out of range (0V to 60V)');
            end
            if ~any(axis==[1,2,3])
                error('anc350:set_voltage:wrong_axis','Specify axis 1,2,3');
            end
            if obj.servo(axis)
                warning('Servo must be disabled for set_voltage mode. Disabling now.');
                obj.set_servo(axis-1,0);
            end
            % Set voltage
            err=calllib('anc350v4','ANC_setDcVoltage',obj.handle,axis-1,voltage);
            obj.checkerr(err);
        end
        
        function v=get.voltage(obj)
           v = [0,0,0];
           for i =1:3
                [err,~,v_t]=calllib('anc350v4','ANC_getDcVoltage',obj.handle,i-1,0);
                v(i) = v_t;
                obj.checkerr(err);
           end
        end
        
        function set.position(obj,p)
            % Set the position (equivalent to move in 3D)
            for i=1:3
                obj.set_target(i-1,p(i)+obj.zero(i));
            end
        end
        
        function set_zero(obj,posn)
            % Set a zero position - either where we are, or with a
            % co-ordinate system provided
            if nargin == 1
                for i =1:3
                    obj.zero(i) = obj.get_position(i-1);
                end
            else
                obj.zero = posn;
            end
        end
        
        function s=get.status(obj)
            % Read the system status from all axes
            s=struct('connected',[0 0 0],'enabled',[0 0 0],'moving',[0 0 0],'target',[0 0 0],'eotFwd',[0 0 0],'eotBwd',[0 0 0],'error',[0 0 0]);
            for i =1:3
                o = obj.get_status(i-1);
                f = fieldnames(o);
                for j = 1:numel(f)
                    s.(f{j})(i) = o.(f{j});
                end
            end
        end
        
    end 
    
    %% Hidden methods, internal communication
    methods (Hidden= true)
        
        function set_target(obj,axis,target)
            % Check if servo on
            if ~obj.servo(axis+1)
                warning('anc350:set_target:servo_off','Turn on the servo before setting a target');
            end
            % Note, internally in mm. Convert to m.
            target = target/1000;
            err=calllib('anc350v4','ANC_setTargetPosition',obj.handle,axis,target);
            obj.checkerr(err);
        end
            
        
        function set_servo(obj,axis,state)
            % Turn servo for targetting
            if and(state ~=0,state ~=1)
                error('anc350:set_servo:unknown_state','State must be 0 (off) or 1 (on)');
            end
            % Start automove
            err=calllib('anc350v4','ANC_startAutoMove',obj.handle,axis,state,1);
            obj.checkerr(err);
            % Record
            obj.servo(axis+1) = state;
            % Set to current position (stop immediate movement!)
            if state == 1
                obj.set_target(axis,obj.get_position(axis));
            end
        end
        
        function psn=get_position(obj,axis)
            % Get current axis position
            [err,~,psn]=calllib('anc350v4','ANC_getPosition',obj.handle,axis,0);
            obj.checkerr(err);
            % Base unit mm
            psn = psn*1000;
        end
        
        function s = get_status(obj,axis)
            % Get the status of an axis
            [err,~,connected,enabled,moving,target,eotFwd,eotBwd,error] = calllib('anc350v4','ANC_getAxisStatus', obj.handle,axis,0,0,0,0,0,0,0);
            obj.checkerr(err);
            s = struct('connected',connected,'enabled',enabled,'moving',moving,'target',target,'eotFwd',eotFwd,'eotBwd',eotBwd,'error',error);
        end
        
        function checkerr(~,err)
            % Check the error codes against those defined
            switch err
                case 0
                    % No error
                    return;
                case -1
                    errcode = 'ANC_Error';
                    errmessage = 'Unspecified error';
                case 1
                    errcode = 'ANC_Timeout';
                    errmessage = 'Receive timed out';
                case 2
                    errcode = 'ANC_NotConnected';
                    errmessage = 'No connection was established';
                case 3
                    errcode = 'ANC_DriverError';
                    errmessage = 'Error accessing the USB driver.';
                case 7
                    errcode = 'ANC_DeviceLocked';
                    errmessage = 'Cannot connect, device already in use.';
                case 8
                    errcode = 'ANC_Unknown';
                    errmessage = 'Unknown error.';
                case 9
                    errcode = 'ANC_NoDevice';
                    errmessage = 'Invalid device number used in call.';
                case 10
                    errcode = 'ANC_NoAxis';
                    errmessage = 'Invalid axis number in function call.';
                case 11
                    errcode = 'ANC_OutOfRange';
                    errmessage = '	Parameter in call is out of range.';
                case 12
                    errcode = 'ANC_NotAvailable';
                    errmessage = 'Function not available for device type.';
                case 13
                    errcode = 'ANC_FileError';
                    errmessage = 'Error opening or interpreting a file.';
                otherwise
                    errcode = 'Error_not_known';
                    errmessage = 'Error not in documentation.';
            end
            error(strcat('anc350:',errcode),errmessage);
        end
    end
    
end