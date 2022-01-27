classdef elliptec_driver < handle
    %% ThorLabs Elliptec Driver
    %
    %   Control via enumerated serial port
    % 	Follow protocol on https://www.thorlabs.com/software_pages/ViewSoftwarePage.cfm?Code=ELL
    %   V2: Split off between driver and individual stage controller
    %   
    %   Note, this version has two modes of operation for serial connection:
    %   serial and serialport, for different MATLAB version. YMMV.
    %
    %   Author  : Patrick Parkinson (patrick.parkinson@manchester.ac.uk)
    %   Date    : 12/07/2021
    %   Version : 2.0
    
    % Private internal variables
    properties (Access = private)
        % Serial connection
        zero = 0;
        s;
        % Device address
        address = 0;
        % Conversion constant
        conv;
        integer_position = false;
    end
    
    properties (Dependent = true)
        % Physical position, converted from internal device units
        position;
    end
    
    methods
        function obj= elliptec_driver(address,com_port)
            % elliptec_rotation_stage(address,com_port) : 
            % Initialise the connection and identify the device. Pass address of device, and com port.
            if nargin < 1
                address = 0;
                warning("elliptec_driver:no_address",'No address provided, assuming 0');
            end
            % Set device address
            obj.address = address;
            % Set device COM port
            if nargin<2
                error("elliptec_driver:no_port",'No port provided');
            end
            % Check if is a existing COM connection
            if isa(com_port,'Serialport') || isa(com_port,'serial')
                obj.s = com_port;
            elseif isa(com_port, 'elliptec_driver')
                obj.s = com_port.s;
            elseif isa(com_port, "string") || isa(com_port,"char")
                % Check matlab version and choose serial connect method
                if verLessThan('matlab','8.4')
                    obj.s = serial(com_port,'BaudRate', 9600, 'DataBits',8,'StopBits',1,'Parity','none','FlowControl','none','Timeout',2,'Terminator',13); %#ok<SERIAL>
                    fopen(obj.s);
                else
                    obj.s = serialport(com_port, 9600, 'DataBits',8, 'StopBits',1,'Parity','none','FlowControl','none','Timeout',2);
                end
            else
                error('elliptec_driver:unknown_driver_type',"Unknown driver type");
            end
            % Get info (for conversion constant)
            obj.get_info();
        end
        
        function delete(obj)
            % Gracefully close the COM port as required.
            if verLessThan('matlab','8.4')
                fclose(obj.s);
            else
                if isa(obj.s,'Serialport')
                    flush(obj.s);
                end
            end
        end
        
        function o=get_info(obj)
            % Get device information at the given address, including serial number etc.
            a = obj.query('in');
            % Interpret response
            o = struct('type', ['ELL',int2str(hex2dec(a(1:2)))],...
                'serial_number',a(3:10),'year_of_manufacture',a(11:14),...
                'firmware',a(15:16),'hardware_version',a(17:18),...
                'travel',hex2dec(a(19:22)),'pulse_per_mu',hex2dec(a(23:end)));
            % Capture conversion constant
            if o.pulse_per_mu > 0
                % Standard stage
                obj.conv = o.travel/o.pulse_per_mu;
            else
                % Closed loop stage
                if strcmp(o.type,'ELL9')
                    % 4 position slider
                    obj.conv = 1/32;
                    obj.integer_position = true;
                else
                    obj.conv = 1;
                end
            end
        end
        
        function [s, s_string]=status(obj)
            % Return device status
            s = str2double(obj.query('gs'));
            % Defined in Elliptec manual
            switch s
                case 0
                    s_string = 'No Error';
                case 1
                    s_string = 'Communications time-out';
                case 2
                    s_string = 'Mechanical time-out';
                case 3
                    s_string = 'Command not supported';
                case 4
                    s_string = 'Value out of range';
                case 5
                    s_string = 'Module isolated';
                case 6
                    s_string = 'Module out of isolation';
                case 7
                    s_string = 'Initialising error';
                case 8
                    s_string = 'Thermal error';
                case 9
                    s_string = 'Busy';
                case 10
                    s_string = 'Sensor error';
                case 11
                    s_string = 'Motor error';
                case 12
                    s_string = 'Out of range';
                case 13
                    s_string = 'Overcurrent error';
            end
        end
        
        function home(obj,dir)
            % Move stage to home
            if nargin<2
                dir = 0;
            end
            obj.query(['ho',int2str(dir)]);
            % TODO - how know when finished?
        end
        
        function p=get.position(obj)
            try
                r = obj.query('gp');
                p = hex2dec(r);
                % Deal with twos complement version for negative movements
                if p<2^31
                    p=p*obj.conv;
                else
                    p=(p-2^32)*obj.conv;
                end
            catch
                disp(r);
                error('elliptec_driver:error_in_position_read','Unknown string in position read');
            end
            % For slider stages use integer position
            if obj.integer_position
                p=round(p);
            end
        end
        
        function set.position(obj,p)
            % Set position of stage via the conversion factor
            if obj.integer_position && p ~= round(p)
                    warning('elliptec_driver:integer_position_required','Rounding position to nearest integer');
                    p = round(p);
            end
            counter = round(p/obj.conv);
            % Send
            obj.send(['ma',dec2hex(counter,8)]);
            % Wait
            pause(0.1);
            % Read (position)
            obj.read();
            % Wait for movement to finish (async)
            while obj.status() > 0
                pause(0.1);
            end
        end
    end
    %% Internal send/recieve methods
    methods (Access=private)
        
        function send(obj,cmd)
            % Send data over the serial port
            % Check version
            if  verLessThan('matlab','8.4')
                fwrite(obj.s,[int2str(obj.address),cmd],'uchar');
            else
                writeline(obj.s,[int2str(obj.address),cmd]);
            end
        end
        
        function [result,r]=read(obj)
            % Read data back from serial port
            r = '';
            % Check version
            if  verLessThan('matlab','8.4')
                while 1
                    if obj.s.BytesAvailable > 0
                        t = fread(obj.s,obj.s.BytesAvailable);
                        r = [r,t]; %#ok<AGROW>
                        if ~isempty(t) && t(end)==10
                            break
                        end
                    else
                        pause(0.01);
                    end
                end
                r=char(r');
            else
                while 1
                    if obj.s.NumBytesAvailable > 0
                        t = read(obj.s,obj.s.NumBytesAvailable,'char');
                        r = [r,t]; %#ok<AGROW>
                        if ~isempty(t) && t(end)==10
                            break
                        end
                    else
                        pause(0.01);
                    end
                end
            end
            % Remove headers
            result = r(4:end-2);
            % Return full structure if requested
            if nargout > 1
                r = struct('Address',r(1),'Command',r(2:3),'Payload',result);
            end
        end
        
        function r=query(obj,cmd)
            % Send/receive
            obj.send(cmd);
            pause(0.05);
            r = obj.read();
        end
    end
end