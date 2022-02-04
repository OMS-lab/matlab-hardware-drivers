%% ThorLabs MLS203 XY controller (over thorlabs_serial VCP)
%
% Author  : Patrick Parkinson (patrick.parkinson@manchester.ac.uk)
%
% Used for communication with the XY controller stage. Based on
% thorlabs_serial communication library.
%
%   Usage:
%       xy = MLS203_xy_controller();
%       xy.connect();
%       xy.position = [30 30];
%
classdef MLS203_xy_controller < thorlabs_serial
    
    properties (SetAccess=public, GetAccess=public)
        % Public properties
        moving       = [0,0];
        maxVelocity  = [0,0];
        acceleration = [0,0];
        zero         = [0,0];
    end
    
    properties (Access=protected)
        % Stage specific parameters
        limits   = [0,110;0,75];
        vlimits  = [1e-4,250];
        alimits  = [0,1000];
        bayaddr  = uint8([hex2dec('21'),hex2dec('22'),...
            hex2dec('11'),...
            hex2dec('21')+hex2dec('80'),hex2dec('22')+hex2dec('80')]);
        % Internal tracking parameters
        homed    =[0 0];
        % Debugging
        DEBUG    = 0;
    end
    properties (Dependent = true)
        % Position, velocity, acceleration
        p;
        v;
        a;
    end
        
    methods
        %% Public methods
        
        function connect(obj, port)
            % Establish connection via serial port
            obj.portname = port;
            obj.ba       = obj.bayaddr;
            % Call super
            obj.establish();
            % Check if channels are enabled - if not, enable
            obj.channelEnable(1);
            obj.channelEnable(2);
            % Check if channels are homed - if not, home (autohome)
            for i=1:2
                s = obj.status(i);
                obj.homed(i) = s.status.homed;
                if obj.homed(i) == 0
                    disp('Homing');
                    obj.home(i);
                end
                % Ger parameters
                r = obj.getMoveParams(i);
                obj.maxVelocity(i) = r.maxVel;
                obj.acceleration(i) = r.accel;
            end
        end
        
        function delete(obj)
            % Close serial object and delete
            fclose(obj.s);
            delete(obj.s);
        end
        
        function channelEnable(obj,bay)
            % Enable channel (turn on motors)
            payload = obj.generateHeader(obj.cmd('MOD_REQ_CHANENABLESTATE'),...
                '01','00', obj.bayaddr(bay));
            obj.write(payload);
            % Check channel state
            o = obj.read(obj.cmd('MOD_GET_CHANENABLESTATE'));
            % Check if disabled
            if o(4) == 2
                payload = obj.generateHeader(obj.cmd('MOD_SET_CHANENABLESTATE'),...
                    '01','01',obj.bayaddr(bay));
                obj.write(payload);
            end
        end
        
        % Information commands
        function o=status(obj,bay)
            % Obtain status byte for channel, interpret response.
            pl = obj.generateHeader(obj.cmd('MOT_REQ_DCSTATUSUPDATE'),'01',0,obj.bayaddr(bay));
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
            o.status.currentLimit = bitand(sta(4),1)   > 0;
            o.status.motionError  = bitand(sta(2),64)  > 0;
            o.status.settled      = bitand(sta(2),32)  > 0;
            o.status.tracking     = bitand(sta(2),16)  > 0;
            o.status.homed        = bitand(sta(2),4)   > 0;
            o.status.homing       = bitand(sta(2),2)   > 0;
            o.status.jogReverse   = bitand(sta(1),128) > 0;
            o.status.jogForward   = bitand(sta(1),64)  > 0;
            o.status.moveReverse  = bitand(sta(1),32)  > 0;
            o.status.moveForward  = bitand(sta(1),16)  > 0;
            o.status.reverseLimit = bitand(sta(1),2)   > 0;
            o.status.forwardLimit = bitand(sta(1),1)   > 0;
        end
        
        function [p, pos]=getPosition(obj,bay)
            % Get axis position in real units (and encoder units)
            pl = obj.generateHeader(obj.cmd('MOT_REQ_ENCCOUNTER'),'01','00',obj.bayaddr(bay));
            obj.write(pl);
            o   = obj.read(obj.cmd('MOT_GET_ENCCOUNTER'));
            pos = o(9:12);
            p   = obj.enc2pos(pos)-obj.zero(bay);
        end
        
        function reply=getMoveParams(obj,bay)
            % Read the current parameters for movements (velocity and
            % acceleration) for the axis given by 'bay'.
            pl = obj.generateHeader(obj.cmd('MOT_REQ_VELPARAMS'),'01','00',obj.bayaddr(bay));
            obj.write(pl);
            r = obj.read(obj.cmd('MOT_GET_VELPARAMS'));
            % Interpret
            reply.minVel = obj.enc2vel(r(9:12));
            reply.accel   = obj.enc2acc(r(13:16));
            reply.maxVel = obj.enc2vel(r(17:20));
            % save the reply
            obj.maxVelocity(bay) = reply.maxVel;
            obj.acceleration(bay)= reply.accel;
        end
        
        % Movement commands
        function home(obj,bay,force)
            % Check if the axis is homed - if not, perform homing. Operation
            % can be forced
            if nargin < 3; force = 0; end
            o = obj.status(bay);
            if ~o.status.homed || force==1
                pl = obj.generateHeader(obj.cmd('MOT_MOVE_HOME'),'01','00',obj.bayaddr(bay));
                obj.write(pl);
                obj.read(obj.cmd('MOT_MOVE_HOMED'));
            end
        end
        
        function setMoveParams(obj,bay,velocity,acceleration)
            % Set the move parameters (velocity and acceleration) for the axis
            % specified by 'bay'
            % Check specified value are in acceptable range for stage
            if velocity < obj.vlimits(1) || velocity > obj.vlimits(2)
                error('xy_controller:setMoveParams:velOutOfRange',...
                    ['Specified velocity ' num2str(velocity) ' is out of range (' num2str(obj.vlimits) ')']);
            end
            if acceleration < obj.alimits(1) || acceleration > obj.alimits(2)
                error('xy_controller:setMoveParams:accOutOfRange',...
                    ['Specified acceleration ' num2str(acceleration) ' is out of range (' num2str(obj.alimits) ')']);
            end
            % Make the header
            header = obj.generateHeader(obj.cmd('MOT_SET_VELPARAMS'),'0E','00',obj.bayaddr(bay+3));
            % Make the payload
            minVel = [0,0,0,0];
            maxVel = obj.vel2enc(velocity);
            accel   = obj.acc2enc(acceleration);
            data   = uint8([obj.chan, 0, minVel, accel', maxVel']);
            % Send
            payload = [header, data];
            obj.write(payload);
        end
        
        function setMove(obj, bay, position)
            % Asynchronous or synchronous movement.
            % Convert values
            position = position + obj.zero(bay);
            % Check if in range
            if position < obj.limits(bay,1) || position > obj.limits(bay,2)
                error('xy_controller:setMove:outOfLimits',...
                    ['Specified position (' num2str(position) ') is out of the range of stage (' num2str(obj.limits(bay,:)) ')']);
            end
            % Calculate encoded position
            pos = obj.pos2enc(position);
            % Generate payload
                cmd=obj.cmd('MOT_MOVE_ABSOLUTE');
            % Generate the header and data packets
            header = obj.generateHeader(cmd,'06','00',obj.bayaddr(bay+3));
            data   = uint8([obj.chan, hex2dec('00'), pos']);
            pl     = [header,data];
            % Send
            obj.write(pl);
            % Wait for move to complete
            obj.read(obj.cmd('MOT_MOVE_COMPLETED'));
        end
        
        % Wrapper (non-native) commands
        function setZero(obj,xzero,yzero)
            % Internal zero position (in stage units)
            if nargin < 2
                % Set zero where we are
                xzero = obj.getPosition(1)+obj.zero(1);
                yzero = obj.getPosition(2)+obj.zero(2);
            end
            obj.zero = [xzero,yzero];
        end
        
        function load(obj,method)
            % Move to load position
            if nargin < 2
                method=1;
            end
            % Remember old settings
            v_old = obj.v;
            obj.v = 100;
            cp    = obj.p;
            if method==1
                posn = [cp(1) 35-obj.zero(2)];
                obj.p = posn;
                posn = [110-obj.zero(1) 35-obj.zero(2)];
                obj.p = posn;
            else
                posn = [110-obj.zero(1) 35-obj.zero(2)];
                obj.p = posn;
            end
            % Recall old settings
            obj.v = v_old;
        end
        function p=getPosition2D(obj)
            % Get stage position
            p = [obj.getPosition(1),obj.getPosition(2)];
        end
        
        function move2D(obj,coords)
            % Do asynchronous move
            obj.setMove(1,coords(1));
            obj.setMove(2,coords(2));
        end
        
        % Dependant variable stuff for the important parameters
        function p=get.p(obj)
            p = obj.getPosition2D();
        end
        
        function set.p(obj,pos)
            % Set position
            if numel(pos) < 2
                error('xy_controller:setP:posSize','Must be a 2 element vector');
            end
            obj.move2D(pos);
        end
        
        function v=get.v(obj)
            r1 = obj.getMoveParams(1);
            r2 = obj.getMoveParams(2);
            v  = [r1.maxVel,r2.maxVel];
        end
        
        function set.v(obj,vels)
            % Make the same if only one value passed
            if numel(vels) == 1
                vels = [vels,vels];
            end
            % Read accelerations (current)
            r1 = obj.getMoveParams(1);
            r2 = obj.getMoveParams(2);
            % Set velocities
            obj.setMoveParams(1,vels(1),r1.accel);
            obj.setMoveParams(2,vels(2),r2.accel);
        end
        
        function a=get.a(obj)
            % Acceleration
            r1 = obj.getMoveParams(1);
            r2 = obj.getMoveParams(2);
            a  = [r1.accel,r2.accel];
        end
        
        function set.a(obj,accels)
            % Make the same if only one value passed
            if numel(accels) == 1
                accels = [accels,accels];
            end
            % Read velocities (current)
            r1 = obj.getMoveParams(1);
            r2 = obj.getMoveParams(2);
            % Set accelerations
            obj.setMoveParams(1,r1.maxVel,accels(1));
            obj.setMoveParams(2,r2.maxVel,accels(2));
        end
            
    end
    
    methods(Access=protected)
        % Conversion functions
        function p = enc2pos(~,enc)
            p=sum(enc'.*256.^[0,1,2,3])/20000;
        end
        function v = enc2vel(~,enc)
            conv = 0:(length(enc)-1);
            C = 134217.73;
            v=sum(enc'.*256.^conv)/C;
        end
        function a = enc2acc(~,enc)
            C = 13.744;
            a=sum(enc'.*256.^[0,1,2,3])/C;
        end
        function by = vel2enc(~,vel)
            C = 134217.73;
            vel = uint64(vel*C);
            bs  = [0,8,16,24];
            by  = zeros(4,1,'uint8');
            for i =1:4
                by(i)=bitshift(bitand(vel,bitshift(255,bs(i))),-bs(i));
            end
        end
        function by = acc2enc(~,acc)
            C = 13.744;
            acc = uint64(acc*C);
            bs  = [0,8,16,24];
            by  = zeros(4,1,'uint8');
            for i =1:4
                by(i)=bitshift(bitand(acc,bitshift(255,bs(i))),-bs(i));
            end
        end
        function by = pos2enc(~,pos)
            pos = uint64(pos*20000);
            bs  = [0,8,16,24];
            by  = zeros(4,1,'uint8');
            for i =1:4
                by(i)=bitshift(bitand(pos,bitshift(255,bs(i))),-bs(i));
            end
        end
    end
end
