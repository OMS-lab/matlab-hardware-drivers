%% MATLAB Wrapper for low-level communication with the ACS/PI SPiiplus motion controller
%   Version: beta
%   Author: Patrick Parkinson (patrick.parkinson@manchester.ac.uk)
%
%   Connects via tcpip, reimplements licensed low-level control.
%   This implements a minimum working example, with most error handling
%   etc. not implemented.
%
%   Usage:
%       s = spiiplus(); % Create driver
%       s.connect();    % Connect via tcpip with default commands
%       s.enable(0);    % Enable axis 0
%       s.position;     % Get relative position.
%
classdef spiiplus < handle
    
    properties (Access = private)
        % TCPIP connection variable, private
        connection;
        % Flag to run in simulated mode
        simulate = true;
        fifo_packets = {};
    end
    
    properties (Access= private,Constant)
        % Constants for packet construction
        start_char = struct('COMMAND','D3','REPLY','E3','PROMPT_COMMAND','D9','PROMPT_REPLY','E9','UNSOLICITED','E5','ALERT','EE');
        end_char   = struct('COMMAND','D6','REPLY','E6','PROMPT_COMMAND','','PROMPT_REPLY','','UNSOLICITED','E6');
        % Constants for communications
        server_address = "10.0.0.100";
        server_port    = 701;
        % Internal soft limits for movement
        softlim = [[-51,51];[-51,51];[-5,3]];
    end
    
    properties (Dependent=true)
        % High-level position (3D) variable
        position;
        synchronous;
        velocity;
    end
    
    properties (Access = private)
        % Internal flag for synchronous motion
        i_synchronous = false;
    end
    
    properties
        % Specific position list for our experiments
        zero         = [0,0,0];
        positions = struct('P1',[-41.5 41.5 0],...
        'P2',[-41.5 21.5 0],...
        'P3',[-41.5 1.5 0],...
        'P4',[-41.5 -18.5 0],...
        'P5',[-41.5 -38.5 0],...
        'P6',[-21.5 41.5 0],...
        'P7',[-21.5 21.5 0],...
        'P8',[-21.5 1.5 0],...
        'P9',[-21.5 -18.5 0],...
        'P10',[-21.5 -38.5 0],...
        'target',[3.4620 41.3210 0],...
        'P12',[3.5 19.5 0],...
        'P13',[3.5 -15.5 0],...
        'P14',[3.5 -37.5 0],...
        'slide',[33.5 11.5 0],...
        'zero',[0 0 0],...
        'PD',[33.5  -38.5    0],...
        'GaAs',[-1 -35 0],...
        'GaN',[-1 -40 0],...
        'InP',[5 -40 0]);
        
    end
    
    methods
        % High-level function for getting and setting position and setting
        % the zero
        
        function p = get.position(obj)
            % Get current position
            p = [0,0,0];
            for i = 0:2
                p(i+1) = obj.query_rpos(i);
            end
            p = p - obj.zero;
        end
        
        function set.position(obj,posn)
            % set position, and start move
            if numel(posn) ~= 3
                error('Need 3 axes');
            end
            posn = posn + obj.zero;
            
            %check within soft limits and coerece
           if ~isempty(posn(posn(:) > obj.softlim(:,2))) || ~isempty(posn(posn(:) < obj.softlim(:,1)))
               disp('Set position exceeds soft limit - setting to soft limit');
               posn(posn(:) > obj.softlim(:,2)) = obj.softlim(posn(:) > obj.softlim(:,2),2);
               posn(posn(:) < obj.softlim(:,1)) = obj.softlim(posn(:) < obj.softlim(:,1),1);               
           end
           %
           obj.ptp([0,1,2],posn);
        end
        
        function v = get.velocity(obj)
            % Read the velocity (maximum) for the axis
            r = obj.send_resp(obj.wrap_command('COMMAND',obj.request_binary_read(8,'VEL',0,2)));
            % Convert data to 3-vector
            d = reshape(r,8,3);
            v = zeros(3,1);
            for i =1:3
                v(i) = typecast(d(:,i),'double');
            end
            v = v';
        end
        
        function setZero(obj,xzero,yzero,zzero)
            % Internal zero position (in stage units)
            if nargin < 2
                % Set zero where we are
                xzero = obj.query_rpos(0);
                yzero = obj.query_rpos(1);
                zzero = obj.query_rpos(2);
            elseif and(nargin < 3,numel(xzero) == 3)
                xzero = xzero(1);
                yzero = xzero(2);
                zzero = xzero(3);
            end                
            obj.zero = [xzero,yzero,zzero];
        end
        
        
        function home(obj)
            speed = 20;
            %Home negative
            disp('Homing');
            obj.find_home(0,1,speed);
            obj.find_home(1,1,speed);
            obj.find_home(2,1,speed);
            pause(120);
            % Assign values
            pos = obj.position;
            % Arbitrary offset to bring towards the centre
            pos = pos + [15,15,-4];   
            
            %set new zero position
            obj.zero = pos;
            
            % Move to zero
            obj.position = [0,0,0];
        end
    end
    
    %% Non-movement commands, accessible
    
    methods
        % Mid-level functions
        function connect(obj)
            % Make connection
            if isa(obj.connection,'tcpclient')
                return;
            end
            % Make connection
            obj.connection = tcpclient(obj.server_address,obj.server_port);
            obj.simulate = false;
        end
        
        function response = enable(obj,axis)
            % P73 -> Enable motor axis
            body = sprintf('ENABLE %d',axis);
            cmd  = obj.wrap_command('COMMAND',body);
            response = obj.acksend(cmd);
        end
        
        function response = enable_all(obj)
            % P73 -> Enable all motor axis
            for i = 0:2
                body = sprintf('ENABLE %d',i);
                cmd  = obj.wrap_command('COMMAND',body);
                response = obj.acksend(cmd);
            end
        end
        
        function response = disable(obj,axis)
            % P73 -> Disable motor axis
            body = sprintf('DISABLE %d',axis);
            cmd  = obj.wrap_command('COMMAND',body);
            response = obj.acksend(cmd);
        end

        function response = disable_all(obj)
            % P73 -> Disable all motor axis
            for i =0:2
                body = sprintf('DISABLE %d',i);
                cmd  = obj.wrap_command('COMMAND',body);
                response = obj.acksend(cmd);
            end
        end
        
        function out = status(obj)
            % Checks status of motors - are they enabled?
            d=obj.send_resp(obj.wrap_command('COMMAND',obj.request_binary_read(4,'MST',0,2)));
            d = uint64(reshape(d,4,3));
            response = [];
            for i = 1:3
                r = sum(d(:,i)'.*uint64([1 256 256^2 256^3]));
                response(i).enabled = logical(bitand(r(1),uint64(2^0))); %#ok<AGROW>
                response(i).open = logical(bitand(r(1),uint64(2^1))); %#ok<AGROW>
                response(i).inpos = logical(bitand(r(1),uint64(2^4))); %#ok<AGROW>
                response(i).move = logical(bitand(r(1),uint64(2^5))); %#ok<AGROW>
                response(i).acc = logical(bitand(r(1),uint64(2^6))); %#ok<AGROW>
            end
            out.enabled = [response(1).enabled,response(2).enabled,response(3).enabled];
            out.open = [response(1).open,response(2).open,response(3).open];
            out.inpos = [response(1).inpos,response(2).inpos,response(3).inpos];
            out.move = [response(1).move,response(2).move,response(3).move];
            out.acc = [response(1).acc,response(2).acc,response(3).acc];
        end
        
        function r= in_pos(obj)
            % Check if all axes are at target position
            r = obj.status();
            r = all([r.inpos]);
        end
        function response = killall(obj)
            % P76 -> Kill all motion
            cmd  = obj.wrap_command('COMMAND','KILLALL');
            response = obj.acksend(cmd);    
        end
        
        function response = ptp(obj,axis,abs_position)
            % P85 -> Point-to-point movement (absolute)

            if numel(axis) > 1
                % Temporary group/multiple axis movement
                ax = sprintf('%d,',axis);
                ps = sprintf('%.4f,',abs_position);
                body = sprintf('PTP (%s), %s',ax(1:end-1), ps(1:end-1));
            else
                % Single axis move
                body = sprintf('PTP %d,%.4f',axis,abs_position);
            end
            % Wrap command
            cmd  = obj.wrap_command('COMMAND',body);
            % Send
            response = obj.acksend(cmd);
            % Wait if synchronous move requested
            if obj.i_synchronous
                while ~obj.in_pos
                  pause(5e-3);
                end
            end
        end

        function response = find_home(obj,axis,method,speed)
            %homing using method 1 or 2
            if method > 2
                error("spiiplus:find_home:unknown_method",'Method must be 1 or 2');
            end
            body = sprintf('HOME %d, %d, %d',axis,method,speed);
            % Wrap command
            cmd  = obj.wrap_command('COMMAND',body);
            % Send
            response = obj.acksend(cmd);
        end
        
        function d = query_rpos(obj,axis)
            % P79 -> Get current position (absolute)
            body = sprintf('?RPOS(%d)',axis);
            cmd  = obj.wrap_command('COMMAND',body);
            [d,response] = obj.send_resp(cmd);
            % Convert from string to number
            if response
                d=str2double(char(d));
            else
                error("spiiplus:query_rpos:fail",'Failed position request');
            end
        end
                
        function set.synchronous(obj,val)
            % TODO: Sort out synchronous and asynchronous motion.
            if val
                obj.i_synchronous = true;
%                 obj.acksend(obj.wrap_command('COMMAND','DISPCH = -2'));                 % Set all channels
%                 obj.acksend(obj.wrap_command('COMMAND','COMMFL.#SAFEMSG=1'));           % Allow unsolicited messages
%                 obj.acksend(obj.wrap_command('COMMAND','SETCONF(306,-1,1)'));           % Turn on unsol. messages
%                 obj.acksend(obj.wrap_command('COMMAND','SETCONF(307,0x0030000,0x07)')); % Set "end of movement" messages on
            else
                 obj.i_synchronous = false;
%                  obj.acksend(obj.wrap_command('COMMAND','SETCONF(306,-1,0)'));
%                  obj.acksend(obj.wrap_command('COMMAND','COMMFL.#SAFEMSG=0'));
%                  obj.acksend(obj.wrap_command('COMMAND','SETCONF(307,0x0030000,0x00)')); % Set "end of movement" messages on
            end
        end
        
        function o = get.synchronous(obj)
            % Get internal synchronous state
            o = obj.i_synchronous;
        end
        
    end
    
    %% Private internal
    methods (Access = private)
        % Low-level communication functions
        function [cmd, out_id] = wrap_command(obj,type, command_body)
            % Create a "safe-format" packet to send
            % TODO: This only handle single-packet commands, so will fail
            % with very long command body (>1000bytes or so).
            persistent id
            % Initialise
            if isempty(id);id = 0;end
            % Command
            if ~any(strcmp(fieldnames(obj.start_char),type))
                error('Unknown Type');
            end
            % Start and end bytes
            command     = uint8(hex2dec(obj.start_char.(type)));
            command_end = uint8(hex2dec(obj.end_char.(type)));
            % Add one to the command ID
            id = mod(id + 1,255);
            % Get command length as 2 chars
            cmd_len = typecast(uint16(length(command_body)+1),'uint8');
            % Edit command body
            command_body = char(command_body);
            % Return [command, id, length, body, \r, end]
            cmd = char([command, uint8(id), cmd_len, command_body,13,command_end]);
            % Return ID (to match)
            out_id = id;
        end
        
        function [type,id, body,iserror,complete] = unwrap_packet(~,cmd)
            % Read a "safe format" packet.
            % TODO: Check that this is complete using the CMD length.
            % Get packet type
            type = uint8(cmd(1));
            % Get ID
            id = uint8(cmd(2));
            % Could be acknowledgement
            if (length(cmd) == 2) && (type==hex2dec('E9'))
                body = '';
                iserror = false;
                complete = true;
                return;
            end
            % Check for alert
            if type == hex2dec('EE')
                body = cmd(7:10);
                iserror = false;
                complete = true;
                return;
            end
            % Check if end matches start
            if uint8(cmd(end)) ~= (type+3)
                warning('Mismatched start and end bytes in unwrap, possible underrun');
                complete = false;
                body = '';
                iserror = false;
                return
            end
            % Get length of body
            % TODO: Check that this corresponds to the body length
            cmd_len = uint8(cmd(3:4));
            cmd_len = sum(cmd_len.*uint8([1 8]));
            % Body
            body = cmd(5:end-1);
            % Check
            if cmd_len > numel(body)
                iserror = false;
                complete = false;
                return; 
            else
                complete = true;
            end
            % Check for error condition
            iserror = false;
            if length(body) == 6
                if strcmp(body(1),'?')
                    iserror = true;
                end
            end
        end
        
        function o = binary_write(~,len, var_name,data)
            % Format - %[RW][04 or 08]<Variable Name>(From1, To1)(From2,To2)
            % Where [RW] = ?? for read, >> for write
            % Where 04 -> Int, 08 -> Real
            % Single value (0,0)(0,0)
            % 1D (f1,t1)(0,0)
            % 2D (f1,t1)(f2,t2)
            if len == 4
                type = uint8(4);
                data = int32(data);
             %   t = 'int32';
            elseif len==8
                type = uint8(8);
                data = double(data);
             %   t = 'double';
            else
                error('Type must be 4 or 8byte');
            end
            % Decide what/how many variables to write
            s = size(data);
            if isscalar(data)
                f1 = 0; t1=0; f2 = 0; t2 = 0;
            elseif isvector(data)
                f1 = 0; t1=numel(data); f2 = 0; t2 = 0;
            elseif ismatrix
                f1 = 0; t1=s(1); f2 = 0; t2 = s(2);
            else
                error('Unknown variable type');
            end
            % Construct requestor
            o = sprintf('%%>>%s%s(%d,%d)(%d,%d)/%%',char(type),var_name,f1,t1,f2,t2);
            d = data(:);
            for i =1:numel(d)
                o = [o,typecast(d(i),'uint8')];
            end
        end
        
        function o = request_binary_read(~, len, var_name, f1,t1,f2,t2)
            % Format - %[RW][04 or 08]<Variable Name>(From1, To1)(From2,To2)
            % Where [RW] = ?? for read, >> for write
            % Where 04 -> Int, 08 -> Real
            % Single value (0,0)(0,0)
            % 1D (f1,t1)(0,0)
            % 2D (f1,t1)(f2,t2)
            if len == 4
                type = uint8(4);
            elseif len==8
                type = uint8(8);
            else
                error('Type must be 4 or 8byte');
            end
            % Decide what/how many variables to read
            switch nargin
                case 3
                    f1 =0; t1 = 0; f2 = 0; t2 = 0;
                case 5
                    f2 = 0; t2 = 0;
                case 7
                    pass
                otherwise
                    error('Incorrect argument count');
            end
            % Construct requestor
            o = sprintf('%%??%s%s(%d,%d)(%d,%d)',char(type),var_name,f1,t1,f2,t2);
        end
        
        function r=acksend(obj,payload)
            % Write a command and wait on an acknowledgement
            if obj.simulate
                disp(["-> SEND :",payload]);
                r = true;
                return;
            end
            % Send over TCPIP
            obj.connection.write(payload);
            % Wait for at least 2 bytes
            while obj.connection.NumBytesAvailable<2
                pause(0.005);
            end
            % Read from port
            r = [];complete = false;
            while ~complete
                r = [r,obj.connection.read()];                
                % Unwrap packet
                [type,i,b,~,complete] = obj.unwrap_packet(r);
            end
            % Test type (is it a prompt reply/acknowledgement?)
            if type == 233
                r = true;
            else
                warning(char(b));
                r = false;
            end
        end
        
        function [d,r] = send_resp(obj,payload)
            % Send a command and await a full response.
            % Write to port
            if obj.simulate
                disp(['--> SEND : ',payload]);
                d = 0;
                r = true;
                return;
            end
            obj.connection.write(payload);
            % Wait for at least 4 bytes (minimium size)
            while obj.connection.NumBytesAvailable<4
            %    pause(0.005);
            end
            % Read from port
            r = obj.connection.read();
            % Unwrap
            [type,~,d,~] = obj.unwrap_packet(r);
            % Test if an appropriate data type (REPLY)
            if type == 227
                r = true;
            else
                r = false;
            end
        end
        
    end
    
end