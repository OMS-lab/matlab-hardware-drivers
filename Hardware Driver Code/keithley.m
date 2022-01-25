%% Simple handle for basic measurements from Keithley instruments inplementing SCPI
%   For example : K6487 (https://download.tek.com/manual/6487-901-01(B-Mar2011)(Ref).pdf)
%           or  : K2400 
%
classdef keithley < handle
    
    properties
        % Serial port connection
        s
        model
    end
    
    methods
        function connect(obj)
            % Check if open
            f = instrfind('port','COM6');
            for i =1:numel(f)
                fclose(f(i));
                delete(f(i));
            end
            % Note, 2020 prefers serialport (earlier was serial)
            obj.s = serial('COM6','BaudRate',19200, 'databits',8, 'parity','none','flowcontrol','none','terminator',newline);
            fopen(obj.s);
            obj.get_model();
        end
        
        function delete(obj)
            % Remove serial connection from memory
            fclose(obj.s);
        end
        
        function r = read_current(obj)
            % Single-shot current measurement
            r = obj.query('READ?');
            % Need to check return value
            o = sscanf(r,'%fA,%f,%f',3);
            r = struct();
            % Put into a structure
            if o(1)<9e37
                r.A = o(1);
            else
                r.A = NaN;
            end
            r.O = o(2);
            r.V = o(3);
        end
        
        function set_voltage(obj,V)
            % Set the output voltage
            obj.ser_write(sprintf('SOUR:VOLT:LEV:IMM:AMPL %.3f',V));
        end
                
        function reset(obj)
            obj.ser_write('*RST');
        end
        
        
        function output(obj,state)
            % Switch the output (i.e. arm)
            if state
                % Set minimum current range
                % obj.ser_write('SOURI:VOLT:ILIM 1');
                % Set 500V range
                obj.ser_write('SOUR:VOLT:RANG 500');
                % Fix ranging to 20uA max
                obj.ser_write('CURR:RANG:UPP 2e-3');
                pause(.5);
                obj.ser_write('CURR:RANG:AUTO OFF');
                % Set immediate update
                obj.ser_write('SOUR:VOLT:STAT ON');    
                % Turn off zero check
                obj.ser_write('SYST:ZCH OFF');    
                % Initiate measurement
                obj.ser_write('INIT');
            else
                obj.ser_write('SYST:ZCH ON');    
                obj.ser_write('SOUR:VOLT:STAT OFF');    
            end
        end
    end
    
    methods (Access = private)
        
        function get_model(obj)
            % Request model number (used for command-set ID)
            r=obj.query('*IDN?');
            obj.model = strip(r');
        end
        
        function ser_write(obj,command)
            % Send command + terminator
            fwrite(obj.s,[command,newline]);
            pause(.05);
        end
        
        function r=ser_read(obj)
            % Read from the buffer, up to 256 characters
            r =zeros(256,1);
            i=1;
            % Inf loop
            while(1)
                % Wait for bytes
                while(obj.s.BytesAvailable==0)
                    pause(0.03);
                end
                % Read bytes 
                osb=obj.s.BytesAvailable;
                a = fread(obj.s,osb);
                % Add to buffer
                r(i:(i+numel(a)-1)) = a;
                i = i+numel(a);
                % If newline, break
                if r(i-1)==newline
                    r = char(r(1:i-1));
                    break
                end
            end
        end
        
        function r=query(obj,command)
            % Issue a read/write combination
            obj.ser_write(command);
            r = obj.ser_read();
        end
    end
end