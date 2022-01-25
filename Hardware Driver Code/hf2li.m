classdef hf2li < handle %#ok<*INUSD>
    % Author  : Patrick Parkinson (patrick.parkinson@manchester.ac.uk)
    % Date    : 05/01/2018
    % License : 
    %
    % Class wrapper for ziDAQ, Zurich Instruments HF2 lock-in amplifier
    % Most of the lock-in settings are controlled through the dedicated
    % ziControl software - here we seek to implement the bare minimum to
    % run an experiment:
    %   - connecting to and disconnecting from the lock-in
    %   - reading values from the lockin demodulators
    %   - setting auxiliary voltage and digital outputs
    
    properties (Access=protected)
        i_status = 0; % Connected and working?
        i_device = 'DEV915'; % String
    end
    
    properties (SetAccess=protected, GetAccess=public, Dependent=true)
        % Simplify getting the most common values from demodulator 1
        sample;  % Sample
    end
    
    properties (Dependent = true)
        preampV;
    end
    
    methods
        function connect(obj)
            % Establish and check connection
            ziDAQ('connect');
            d = ziDAQ('listNodes','/');
            f = 0;
            for i =1:length(d)
                if strcmp(d{i},obj.i_device)
                    disp(['Found ' obj.i_device]);
                    f = 1;
                    break
                end
            end
            if f==0
                error('hf2li:connect:deviceNotFound', 'Device not found - is it switched on?');
            end
            obj.i_status=1;
        end
        
        function disconnect(obj)
            % Rip down connection
            if obj.i_status==1
                ziDAQ('disconnect');
                obj.i_status = 0;
            end
        end
        
        function setSensitivity(obj,lin, value)
            % Set the input level (sensitivity)
        end

        function o=getValue(obj, demod)
            % Get the output from one of the 6 demodulators
            % parameter is x,y,r,t (4 x 64bit numbers)
            if obj.i_status==0; error('hf2li:notConnected','Not connected');end;
            if demod < 1 || demod > 6; error('hf2li:getValue:demodNotInRange','Demodulator not in range 1 to 6');end;            % Start from 0
            demod = demod -1;
            % Get sample
            o   = ziDAQ('getSample',['/',obj.i_device,'/demods/',int2str(demod),'/sample']);
            % Add theta and R
            o.theta = atand(o.y/o.x);
            o.R     = sqrt(o.x^2+o.y^2);
        end
        
        function s=get.sample(obj)
            % Return a readout from demod 1
            s = obj.getValue(1);
        end
        
        function o=status(obj) %#ok<*STOUT>
            % Check for overloads etc
            if obj.i_status==0; error('hf2li:notConnected','Not connected');end;           % Start from 0
            b=dec2bin(ziDAQ('getDouble',['/',obj.i_device,'/STATUS/FLAGS/BINARY']),13);
            % Handcode
            o.error           = str2double(b)>0;
            o.pll_unlock      = b(1);
            o.clock_unlock    = b(2);
            o.fx2_rx_error    = b(3);
            o.packageloss     = b(4);
            o.output1_clip    = b(5);
            o.output2_clip    = b(6);
            o.input1_clip     = b(7);
            o.input2_clip     = b(8);
            o.scope_skip      = b(9);
            o.fx2_buffer_full = b(10);
            o.pll_unlockDB    = b(12);
            o.fx2_package_loss = b(13);
        end
        
        function setAux(obj, auxport, voltage)
            % set an auxiliary output voltage on one of the 4 outputs. Note
            % pre-amp has one too (5).
            if obj.i_status==0; error('hf2li:notConnected','Not connected');end;           % Start from 0
            if auxport < 1 || auxport > 2; error('hf2li:setAux:auxNotInRange','Aux not in range 1-2');end;
            if voltage < -10 || voltage > 10; error('hf2li:setAux:voltageOutOfRange','Voltage out of range (plus/minus 10V)');end;
            port = int2str(auxport - 1);
            voltage = double(min(10,max(-10,voltage)));
            % We set the output to be fixed (rather than derived)
            ziDAQ('setDouble',['/',obj.i_device,'/auxouts/',port,'/outputselect'],-1);
            % And then set the voltage
            ziDAQ('setDouble',['/',obj.i_device,'/auxouts/',port,'/offset'],voltage);
        end
        
        function o=getAux(obj)
            % Read a voltage from one of the 2 aux ports
            if obj.i_status==0; error('hf2li:notConnected','Not connected');end;           % Start from 0
            o = ziDAQ('getAuxInSample',['/',obj.i_device,'/auxins/0/sample']);
        end
        
        function o=getDIO(obj, dioport)
            % Read from one of the 32 DIO ports. Note upper 16 are
            % bidirectional - a read forces it to be a read!
            if obj.i_status==0; error('hf2li:notConnected','Not connected');end;           % Start from 0
            d = ziDAQ('getDIO',['/',obj.i_device,'/dios/0/sample']);
            o = dec2bin(d.bits);
        end
        
        function setDIO(obj, dioport, value)
            % Set the value of one of the 16 DIO ports. Setting a value
            % will force it to be an output.
        end
        
        function set.preampV(obj,voltage)
            % set an auxiliary output voltage
            if obj.i_status==0; error('hf2li:notConnected','Not connected');end;           % Start from 0
            if voltage < -10 || voltage > 10; error('hf2li:setAux:voltageOutOfRange','Voltage out of range (plus/minus 10V)');end;   
            ziDAQ('setDouble',['/',obj.i_device,'/zctrls/0/tamp/biasout'],voltage);
        end
        
        function v=get.preampV(obj)
            v = ziDAQ('getDouble',['/',obj.i_device,'/zctrls/0/tamp/biasout']);
        end
    end
    
end