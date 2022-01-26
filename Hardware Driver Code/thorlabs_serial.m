classdef thorlabs_serial < handle
    % Low level thorlabs serial port control driver.
    % Responsible for sending a receiving payloads from the controller.
    % Author  : Patrick Parkinson (patrick.parkinson@manchester.ac.uk)
    % Date    : 13/07/2017
    % Version : 1.1
    properties (Access=protected)
        % Communications protocol options
        portname;
        % Serial port
        s;
        % Protocol parameters
        hostaddr = uint8(hex2dec('01'));
        chan     = uint8(hex2dec('01'));
        % Device specific controls
        ack = 1;
        ba = {};
    end
    
    methods (Access=protected)
        % High level functions
        function establish(obj)
            % Establish connection via serial port
            if ~isa(obj.s,'serial')
                % Object is not yet connected (avoid double connections)
                % Check if we're being passed a serial port
                if isa(obj.portname,'serial')
                    % We are
                    obj.s = obj.portname;
                else
                disp('Opening serial port');
                obj.s = serial(obj.portname,'BaudRate',115200,...
                    'DataBits',8,...
                    'ByteOrder','littleEndian',...
                    'FlowControl','hardware',...
                    'Parity','none',...
                    'StopBits',1,...
                    'terminator','',...
                    'TimeOut',40);
                % Open serial port
                fopen(obj.s);
                end
            end
            % Test if port is valid
            if ~isvalid(obj.s)
                error('thorlabs_serial:establish:invalidSerial','Serial port is invalid after open');
            end
        end
        function shut(obj)
        % Close serial object and delete
        fclose(obj.s);
        delete(obj.s);
    end
        % Low level functions
        function payload = generateHeader(obj,cmd, param1, param2, bay)
            % Header generation function - makes 6 byte packet of the right
            % format for communication
            cmd1 = uint8(hex2dec(cmd(1:2)));
            cmd2 = uint8(hex2dec(cmd(3:4)));
            param1  = uint8(hex2dec(param1));
            param2  = uint8(hex2dec(param2));
            dest    = bay;
            src     = obj.hostaddr;
            payload = [cmd2,cmd1, param1, param2, dest, src];
        end
        % Read and write
        function write(obj,payload)
            persistent writes
            % Write to channel
            % Note - ack must be sent every 50 commands, so implement this here
            % as an extra step. Appears to be robust.
            if isempty(writes)
                writes = 21;
            end
            if writes > 20 & obj.ack == 1
                % Generate ack
                for i =1:length(obj.ba)
                    pl = obj.generateHeader(obj.cmd('MOT_ACK_DCSTATUSUPDATE'),'00','00',obj.ba(i));
                    fwrite(obj.s,pl,'uint8','sync');
                end
                writes = 0;
            else
                writes = writes+1;
            end
            fwrite(obj.s,payload,'uint8','sync');
        end
        function o = read(obj,reply)
            while 1
                % Get header
                h = fread(obj.s,6,'uint8');
                if length(h) < 6
                    % Incomplete dataset - throw
                    error('thorlabs_serial:read:incompleteData',...
                        'Incomplete dataset received when expecting');
                end
                % Does it have data?
                if bitand(h(5),128)>0
                    morebytes = h(3);
                    data = fread(obj.s,morebytes,'uint8');
                    o = [h;data];
                else
                    o = h;
                end
                % Check if correct
                if strcmp(dec2hex(o(1),2),reply(3:4)) && strcmp(dec2hex(o(2),2),reply(1:2))
                    % correct response as requested
                    break
                elseif strcmp(dec2hex(o(1),2),'64') && strcmp(dec2hex(o(2),2),'04')
                    % Read the axis parameter
                    ax = dec2hex(h(6));
                    % Check which axis triggered
                    if strcmp(ax,'21')
                        axi = 1;
                    elseif strcmp(ax,'22')
                        axi = 2;
                    else
                        warning('thorlabs_serial:read:moveOutOfSequence',...
                            ['Axis (' ax ') : Wrong axis returned']);
                        axi = 0;
                    end
                    % Stop!
                    if axi > 1
                        if obj.moving(axi)
                            obj.moving(axi) = 0;
                        else
                            warning('thorlabs_serial:read:moveOutOfSequence',...
                                ['Axis (' ax ') : move complete acknowledgement received out of sequence']);
                        end
                    end
                else
                    warning('thorlabs_serial:read:unknownPacket',...
                        'Unexpected packets found in datastream:');
                    disp(dec2hex(o));
                end
            end
        end
        % Command listing
        function o=cmd(~,name)
            switch name
                case 'MOD_IDENTIFY'
                    o = '0223';
                case 'HW_NO_FLASH_PROGRAMMING'
                    o = '0018';
                case 'MOT_REQ_POSCOUNTER'
                    o = '0411';
                case 'MOT_REQ_ENCCOUNTER'
                    o = '040A';
                case 'MOT_GET_ENCCOUNTER'
                    o = '040B';
                case 'MOT_SET_MOVEABSPARAMS'
                    o = '0450';
                case 'MOT_MOVE_HOME'
                    o = '0443';
                case 'MOT_MOVE_HOMED'
                    o = '0444';
                case 'MOT_MOVE_ABSOLUTE'
                    o = '0453';
                case 'MOT_MOVE_COMPLETED'
                    o = '0464';
                case 'MOT_MOVE_VELOCITY'
                    o = '0457';
                case 'MOT_MOVE_STOP'
                    o = '0465';
                case 'MOT_REQ_DCSTATUSUPDATE'
                    o = '0490';
                case 'MOT_ACK_DCSTATUSUPDATE'
                    o = '0492';
                case 'MOT_GET_DCSTATUSUPDATE'
                    o = '0491';
                case 'MOD_SET_CHANENABLESTATE'
                    o = '0210';
                case 'MOD_REQ_CHANENABLESTATE'
                    o = '0211';
                case 'MOD_GET_CHANENABLESTATE'
                    o = '0212';
                case 'MOT_SET_VELPARAMS'
                    o = '0413';
                case 'MOT_REQ_VELPARAMS'
                    o = '0414';
                case 'MOT_GET_VELPARAMS'
                    o = '0415';
                case 'MOT_REQ_ADCINPUTS'
                    o = '042B';
                case 'MOT_GET_ADCINPUTS'
                    o = '042C';
                case 'MOT_REQ_STATUSBITS'
                    o = '0429';
                case 'MOT_GET_STATUSBITS'
                    o = '042A';
                case 'MOT_GET_POSCOUNTER'
                    o = '0412';
                otherwise
                    error('thorlabs_serial:cmd:noKnown',['Command (' name ') is not known']);
            end
        end
    end
end