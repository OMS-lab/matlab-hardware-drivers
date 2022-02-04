%% ThorLabs APT rotation stage driver (over thorlabs_serial VCP)
%
% Author  : Patrick Parkinson (patrick.parkinson@manchester.ac.uk)
%
% Used for communication with the APT rotation stage controller.
%
%   Usage:
%       rs = TDC001_rotation_stage();
%       rs.connect();
%       rs.position = 100;
%
classdef TDC001_rotation_stage < thorlabs_serial
    
    properties (Access=protected)
        % USB address
        destaddr  = uint8(hex2dec('50'));
        destaddr2 = uint8(hex2dec('50')+hex2dec('80'));
        % Stage encoding values
        enc_scale = 1919.64;
        vel_scale = 42941.66;
        acc_scale = 14.66;
    end
    
    properties (Access=public, Dependent=true)
        % Dependent variable
        position;
    end
    
    methods
        %% Public methods
        function connect(obj,portname)
            % Connect to device
            if nargin < 2
                obj.portname = 'COM14';
            else
                obj.portname = portname;
            end
            obj.ba = obj.destaddr;
            % Call super
            obj.establish;
        end
        
        function delete(obj)
            % Clean close
            obj.shut();
        end
        
        function o=status(obj)
            % Obtain status byte for channel, interpret response.
            pl = obj.generateHeader(obj.cmd('MOT_REQ_DCSTATUSUPDATE'),'01',0,obj.destaddr);
            obj.write(pl);
            r = obj.read(obj.cmd('MOT_GET_DCSTATUSUPDATE'));
            %
            pos = r(9:12);
            vel = r(13:14);
            sta = r(17:20);
            % Interpret
            o.position = obj.enc2pos(pos);
            o.velocity = obj.enc2vel(vel);
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
        
        function [p, pos]=getposition(obj)
        % Get axis position in real units (and encoder units)
        pl = obj.generateHeader(obj.cmd('MOT_REQ_ENCCOUNTER'),'01','00',obj.destaddr);
        obj.write(pl);
        o   = obj.read(obj.cmd('MOT_GET_ENCCOUNTER'));
        pos = o(9:12);
        p   = obj.enc2pos(pos);
        end
        
        function move(obj,position,sync)
            if nargin ==2
                sync = 1;
            end
            % Only synchronous movements
            pos = obj.pos2enc(position);
            cmd = obj.cmd('MOT_MOVE_ABSOLUTE');
            % Make header
            header = obj.generateHeader(cmd,'06','00',obj.destaddr2);
            % Make payload
            data   = uint8([obj.chan, hex2dec('00'), pos']);
            pl     = [header,data];
            % Send
            obj.write(pl);
            % Wait
            if sync
                obj.read(obj.cmd('MOT_MOVE_COMPLETED'));
            end
        end
        
        function complete(obj)
            % Check if movement completed
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
        function o=get.position(obj)
            % Get current position
            o = obj.getposition();
        end
        function set.position(obj, val)
            % Set current position
            obj.move(val);
        end
        
    end
    
    methods (Access=protected)
        %% Private/internal functions
        function p = enc2pos(obj,enc)
            % Convert encoded to physical position
            p=sum(enc'.*256.^[0,1,2,3])/obj.enc_scale;
        end
        
        function by = pos2enc(obj,pos)
            % Convert physical position to encoder
            pos = uint64(pos*obj.enc_scale);
            bs  = [0,8,16,24];
            by  = zeros(4,1,'uint8');
            for i =1:4
                by(i)=bitshift(bitand(pos,bitshift(255,bs(i))),-bs(i));
            end
        end
        
        function v = enc2vel(obj,enc)
            % Convert encoded velocity to physical
            conv = 0:(length(enc)-1);
            C = obj.vel_scale;
            v=sum(enc'.*256.^conv)/C;
        end
        
        function by = vel2enc(obj,vel)
            % Convert physical velocity to encoded
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