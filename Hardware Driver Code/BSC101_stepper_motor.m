%% BSC101 Stepper Motor Controller (ThorLabs)
%
% Author  : Patrick Parkinson (patrick.parkinson@manchester.ac.uk)
%
% Class wrapper for the BSC101 stepper motor (one-channel). Based on the
% "thorlabs_serial" class.
% 
%   Usage (to move to position)
%       step = BSC101_stepper_motor();
%       step.connect();
%       step.position = 10;


classdef BSC101_stepper_motor < thorlabs_serial
    
    properties (Access=protected)
        % Address of the first device over serial
        destaddr  = uint8(hex2dec('50'));
        
        % Stage encoding values in mm (depends on controller)
        enc_scale = 128*200;
        vel_scale = 128*200;
    end
    
    properties (SetAccess=protected)
        % Stage settings, read-only
        zero=0;
        
    end
    
    properties
       % User changable 
       backlash = 0.1;
       % Minimum increment (in mm)
       cutoff   = 1e-3;
       % Soft limits of motion
       softlimit = [7 17];
    end
    
    properties (Access=public, Dependent=true)
        % Dependant
        position;
    end
    
    methods
        
        function connect(obj,portname)
            % Make connection to the device, using inherited
            % thorlabs_serial class
            obj.portname = portname;
            obj.ba = obj.destaddr;
            obj.ack  = 0;
            % Super command
            obj.establish;
            
            % Enable if reqd
            st = obj.status;
            if not(st.status.enabled)
                obj.channelEnable();
            end
            % Use initial position as internal zero - avoids accidents.
            obj.zero = obj.position;
        end
        
        function delete(obj)
            % Clean shutdown
            obj.shut();
        end
        
        function o=status(obj)
            % Obtain status byte for channel, interpret response.
            pl = obj.generateHeader(obj.cmd('MOT_REQ_STATUSBITS'),'01',0,obj.destaddr);
            obj.write(pl);
            r = obj.read(obj.cmd('MOT_GET_STATUSBITS'));
            % Cut last four bytes
            sta = r(9:12);
            % Interpret
            o.status.enabled      = bitand(sta(4),128) > 0;
            o.status.currentlimit = bitand(sta(4),1)   > 0;
            o.status.motionerror  = bitand(sta(2),64)  > 0;
            o.status.settled      = bitand(sta(2),32)  > 0;
            o.status.tracking     = bitand(sta(2),16)  > 0;
            o.status.homed        = bitand(sta(2),4)   > 0;
            o.status.homing       = bitand(sta(2),2)   > 0;
            o.status.jogreverse   = bitand(sta(1),128) > 0;
            o.status.jogforward   = bitand(sta(1),64)  > 0;
            o.status.movereverse  = bitand(sta(1),32)  > 0;
            o.status.moveforward  = bitand(sta(1),16)  > 0;
            o.status.reverselimit = bitand(sta(1),2)   > 0;
            o.status.forwardlimit = bitand(sta(1),1)   > 0;
        end
        
        function setZero(obj,position)
            % Set an internal zero position
            if nargin < 2
                % Current position if not supplied
                position = obj.position+obj.zero;
            end
            obj.zero = position;
        end
        
        function channelEnable(obj)
            % Enable channel (turn on motors)
            pl = obj.generateHeader(obj.cmd('MOD_REQ_CHANENABLESTATE'),'01','00', obj.destaddr);
            obj.write(pl);
            o = obj.read(obj.cmd('MOD_GET_CHANENABLESTATE'));
            if o(4) == 0
                % If disabled - enable
                pl = obj.generateHeader(obj.cmd('MOD_SET_CHANENABLESTATE'),'01','01', obj.destaddr);
                obj.write(pl);
            end
        end        
        
        function move(obj,position,force)
            % Move the stage
            if nargin<3
                force = 0;
            end
            % Check softlimit
            if (((position+obj.zero) < min(obj.softlimit)) || ((position+obj.zero) > max(obj.softlimit))) && not(force)
                error('stepper_motor:move:out_of_range','Out of range of soft-limit');
            end
            % Read current position
            curpos = obj.position;
            
            % Check if move is larger than cutoff resolution
            if abs(position - curpos) < obj.cutoff
                return
            end
            
            % Implement backlash
            if (position < curpos) && not(force) && (obj.backlash > 0)
                obj.move(position-obj.backlash, 1);
            end
            
            % Only synchronous movements permitted
            pos = obj.pos2enc(position+obj.zero);
            cmd = obj.cmd('MOT_MOVE_ABSOLUTE');
            
            % Make header
            header = obj.generateHeader(cmd,'06','00',obj.destaddr+hex2dec('80'));
            
            % Make payload
            data   = uint8([obj.chan, hex2dec('00'), pos']);
            pl     = [header,data];
            
            % Send
            obj.write(pl);
            
            % Wait
            obj.read(obj.cmd('MOT_MOVE_COMPLETED'));
        end
            
        function home(obj,force)
            % Check if the axis is homed - if not, perform homing. Operation
            % can be forced
            if nargin < 2; force = 0; end
            o = obj.status();
            if ~o.status.homed || force==1
                pl = obj.generateHeader(obj.cmd('MOT_MOVE_HOME'),'01','00',obj.destaddr);
                obj.write(pl);
                obj.read(obj.cmd('MOT_MOVE_HOMED'));
            end
        end
        
        % Helper functions (dependent)
        function p=get.position(obj)
            % Get axis position in real units (and encoder units)
            pl = obj.generateHeader(obj.cmd('MOT_REQ_POSCOUNTER'),'01','00',obj.destaddr);
            obj.write(pl);
            o   = obj.read(obj.cmd('MOT_GET_POSCOUNTER'));
            pos = o(9:12);
            p   = obj.enc2pos(pos)-obj.zero;
        end
        
        function set.position(obj, val)
            % Set current position
            obj.move(val);
        end
        
        function retract(obj)
            % Move out of the way (to end of range), retaining zero
            disp('stepper_motor:retracting');
            obj.move(-20,1);
        end
        
        function m=get_metadata(obj)
            % Metadata structure
            m = struct('zero',obj.zero, 'resolution',obj.cutoff);
        end
    end
    
    methods (Access=protected)
        %% Internal methods
        function p = enc2pos(obj,enc)
            % Convert encoder position to physical position
            p=sum(enc.*256.^[0,1,2,3])/obj.enc_scale;
        end
        
        function by = pos2enc(obj,pos)
            % Convert physical position to encoder value
            pos = uint64(pos*obj.enc_scale);
            bs  = [0,8,16,24];
            by  = zeros(4,1,'uint8');
            for i =1:4
                by(i)=bitshift(bitand(pos,bitshift(255,bs(i))),-bs(i));
            end
        end
        
        function v = enc2vel(obj,enc)
            % Convert encoder velocity to physical velocity
            conv = 0:(length(enc)-1);
            C = obj.vel_scale;
            v=sum(enc.*256.^conv)/C;
        end
        
        function by = vel2enc(obj,vel)
            % Convert physical velocity to encoder velocity
            C = obj.vel_scale;
            vel = uint64(vel*C);
            bs  = [0,8,16,24];
            by  = zeros(4,1,'uint8');
            for i =1:4
                by(i)=bitshift(bitand(vel,bitshift(255,bs(i))),-bs(i));
            end
        end
    end
end