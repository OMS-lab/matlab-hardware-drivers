%% pi_motion_controller
%  Motion controller driver for the C863 Mercury driver
%
classdef pi_motion_controller < handle
    
    properties
        % Externally accessible motion controller
        serial_props = struct('port',"COM7",'baud',38400,'bits',8,'parity',"None",'stop',1,...
            'terminator',newline);
        % Zero position
        zero = 0;
        % Synchronous
        sync = true;
    end
    
    properties (SetAccess = private)
        % Range of motion
        min;
        max;
    end
    
    properties (Dependent=true)
        % Set servo, set position etc.
        servo;
        position;
        tau;
    end
    
    properties (Access=private)
        % Serial connection
        s;
        conv = 6.6712819; %(ps per mm)
    end
    
    methods
        % Initialise and open connection
        function obj=pi_motion_controller()
            % Check port
            obj.s = check_port(obj.serial_props.port);
            if isempty(obj.s)
                obj.s = serial(obj.serial_props.port,...
                    'BaudRate',obj.serial_props.baud,...
                    'DataBits',obj.serial_props.bits,...
                    'StopBits',obj.serial_props.stop,...
                    'Terminator',obj.serial_props.terminator);
                if ~isa(obj.s,'serial')
                    error('nmc::serial');
                end
            end
            if ~strcmp(obj.s.Status,'open')
                fopen(obj.s);
                if ~strcmp(obj.s.Status,'open')
                    error('newport_motion_controller:serial_open',"Unable to open port");
                end
            end
            % Read range of motion
            q = obj.query('TMN?');
            q = sscanf(q,'%d=%f');
            obj.min = q(2);
            q = obj.query('TMX?');
            q = sscanf(q,'%d=%f');
            obj.max = q(2);
            % Home
            obj.home();
        end
        
        % Delete
        function delete(obj)
            fclose(obj.s);
        end
        
        % Get servo status
        function s=get.servo(obj)
            s=obj.query('SVO?');
            s=logical(s(3) == '1');
        end
        
        % Set servo status
        function set.servo(obj,status)
            status = logical(status);
            if status 
                st = '1'; 
            else
                st = '0';
            end
            obj.write(['SVO 1 ',st]);
        end
        
        % Get current position
        function p=get.position(obj)
            obj.write('POS?');
            r = obj.read();
            q = sscanf(r,'%d=%f');
            p = q(2);            
        end
        
        % Home device
        function home(obj)
            q = obj.query('FRF?');
            if q == "1=1"
                disp('Already homed');
            else
                obj.write('FRF');
            end
        end
        
        % Check if we are on target (for synchronous)
        function o=on_target(obj)
            q = obj.query('ONT?');
            q = sscanf(q,'%d=%d');
            o = logical(q(2)==1);
        end
        
        % Set position (immediate move)
        function set.position(obj,p)
            if all([p>=obj.min,p<=obj.max,obj.servo])
                obj.write(sprintf('MOV 1 %.4f',p));
            else
                error('Out of range (%.1f - %.1f)mm',obj.min, obj.max);
            end
            if obj.sync
                % Synchronous move
                while obj.on_target == false
                    pause(0.2);
                end
            end
        end
        
        function initialise(obj)
            obj.servo = true;
            obj.home();
        end
        
        function t=get.tau(obj)
            t = (obj.position - obj.zero)*obj.conv;
        end
        
        function set.tau(obj,t)
            obj.position = (t/obj.conv + obj.zero);
        end
        
        function set_zero(obj)
            obj.zero = obj.position;
        end
            
    end
    
    % Private read and write functions
    methods (Access = private)
                function write(obj,str)
            str = [str,newline];
            fwrite(obj.s,str);
        end
        
        function r=query(obj,qstring)
            obj.write(qstring);
            r = obj.read();
        end
        
        function r=read(obj,raw)
            if nargin <2; raw = false;end
            flag = true;
            trycount = 0;
            r    = [];
            pause(0.01);
            while flag
                while obj.s.BytesAvailable == 0
                    pause(0.01);
                    trycount = trycount+1;
                    if trycount > 100
                        error('pmc:read:no_data',"No data");
                    end
                end
                i = fread(obj.s,obj.s.BytesAvailable);
                r = [r;i]; %#ok<AGROW>
                if or(raw,r(end) == 10)
                    % incomplete read
                    flag = false;
                end
            end
            if ~raw
                r = char(r(1:end-1)');
            else
                r = r(1:end-1);
            end
        end
    end
end