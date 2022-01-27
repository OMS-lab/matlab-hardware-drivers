%% PicoQuant Hydraharp control
%   Author  : Patrick Parkinson (patrick.parkinson@manchester.ac.uk)
%   Date    : 22/01/2022
%   Version : 0.3
%   License : CC-BY-SA (http://creativecommons.org/licenses/by-sa/4.0/)
%
%   This MATLAB class provides a handle-based approach to connecting with
%   Picoquant Hydraharp400 series. The purpose is to allow the three basic
%   modes, histogram, T2 and T3 to be used and to return data in a MATLAB
%   format.
%
%   It is work in progress.
%
%   Usage (histogram with default settings):
%       hh = tcspc();
%       hh.connect();
%       data = hh.histogram(1);
%
%   Changelog :
%       24/10/2017 : Added streaming record to photon conversion (PWP)
%       25/01/2018 : Minor update for resetting (clearing flags) (PWP)
%       14/08/2018 : Allow getting and setting:                  (PWP)
%                        base resolution via .resolution,
%                        sync_div via .sync_div
%                        sync_cfd via .sync_cfd
%                        Added auto_configure to set these values
%                        appropriately.
%       21/01/2022 : Added global offset (not sync, channel)     (PWP)

classdef tcspc < handle
    
    properties (Access=private)
        % Constants related to Hydraharp
        MODE_HIST     =         0;
        MODE_T2	      =         2;
        MODE_T3	      =         3;
        FLAG_OVERFLOW =         hex2dec('0001');
        FLAG_FIFOFULL =         hex2dec('0002');
        dev           =         0;             % This software only connects to one device at present
        TTREADMAX     =         131072;        % 128K event records
        gmax          =         1000*1024^2;   % Maximum photons to record in a single experiment (arbitrary)
        % Internal variables to store current mode, resolution etc. See
        % dependant variables, below.
        current_mode        =   [];
        current_res         =   1;
        current_sync_div    =   0;
        current_sync_cfd    =   -1;
        current_sync_offset =   NaN;
        current_offset      =   NaN;
    end
    
    properties (Dependent=true)
        % To switch modes between hist, T2 and T3
        mode
        % Properties of the Hydraharp
        resolution
        sync_div
        sync_cfd
        sync_offset
        offset
    end
    
    properties
        % Flag to use multistop mode (if available)
        multistop = false;
    end
    
    methods
        
        function obj=tcspc()
            % TCSPC constructor
            % Check if library DLL is loaded - load if not
            if (~libisloaded('HHlib'))
                loadlibrary('hhlib64.dll', 'hhlib.h', 'alias', 'HHlib'); % Windows 64 bit
            else
                fprintf('Note: HHlib was already loaded\n');
            end
            % Confirm that library is opened
            if (libisloaded('HHlib'))
                fprintf('HHlib opened successfully\n');
            else
                error('tcspc:HHLib:Open','Could not open HHlib\n');
            end
        end
        
        function delete(obj)
            % Destructor - clean close
            calllib('HHlib', 'HH_CloseDevice', obj.dev);
        end
        
        function initialize(obj,mode)
            % Check if supplied mode is valid
            if strcmpi(mode,'HIST')
                md = obj.MODE_HIST;
            elseif strcmpi(mode,'T3')
                md = obj.MODE_T3;
            elseif strcmpi(mode,'T2')
                md = obj.MODE_T2;
            else
                error('tcspc:Mode:Unrecognised','Mode not recognised.');
            end
            % Check if we're already in this mode
            if md == obj.current_mode
                return
            end
            % Initialize device into mode
            [ret] = calllib('HHlib', 'HH_Initialize', obj.dev, md, 0);
            % Check for errors
            if(ret<0)
                error('tcspc:HHLib:HH_Initialize','HH_Initialize error %s. Aborted.',obj.getError(ret));
            else
                disp(['Mode set to ', mode]);
                obj.current_mode = mode;
            end
        end
        
        function reset(obj)
            % Attempt to clear flags and reset the device. Not always
            % useful
            m = obj.current_mode;
            calllib('HHlib', 'HH_CloseDevice', obj.dev);
            unloadlibrary('HHlib');
            loadlibrary('hhlib64.dll', 'hhlib.h', 'alias', 'HHlib');
            obj.initialize(m);
        end
        
        function connect(obj,mode)
            % Connect to Hydraharp function
            if nargin<2
                if ~isempty(obj.current_mode)
                    mode = obj.current_mode;
                else
                    mode = 'HIST';
                end
            end
            % Create pointers to use with call
            Serial     = blanks(8);
            SerialPtr  = libpointer('cstring', Serial);
            
            % Open the device
            [ret, Serial] = calllib('HHlib', 'HH_OpenDevice', obj.dev, SerialPtr);
            if ret == 0
                disp(['Opened Device : ', Serial]);
            else
                error('tcspc:HHLib:HH_OpenDevice','HH_OpenDevice failed : Could not open device %s',obj.getError(ret));
            end
            
            % Set and initialize
            obj.mode = mode;
        end
        
        function calibrate(obj)
            % Run an internal calibration for timebase. Should wait a few
            % minutes before running this.
            [ret] = calllib('HHlib', 'HH_Calibrate', obj.dev);
            if(ret<0)
                error('tcspc:HHLib:HH_Calibrate','HH_calibrate error %s',obj.getError(ret));
            end
        end
        
        % Get and set internal variables
        function m=get.mode(obj)
            % Get mode
            m = obj.current_mode;
        end
        
        function set.mode(obj,mode)
            % Set mode - choice is "HIST", "T3", "T2"
            if strcmpi(mode,obj.current_mode)
                warning('tcspc:Mode:Unchanged','Already in %s, skipping',mode);
                return;
            end
            % Initialize
            obj.initialize(mode);
            % Calibrate
            obj.calibrate();
            % Reset multistop
            obj.multistop = false;
        end
        
        function r = get.resolution(obj)
            % Get current timing resolution in ps
            r = 0;
            % Create pointer
            reslPtr = libpointer('doublePtr',r);
            % Make call
            [ret,r] = calllib('HHlib','HH_GetResolution', obj.dev,reslPtr);
            if ret < 0
                error('tcspc:HHLib:HH_GetResolution','HH_GetResolution : Get Resolution Failed %s',obj.getError(ret));
            end
            obj.current_res = r;
        end
        
        function set.resolution(obj,resl)
            % Set current timing resolution in ps, acceptable units in
            % multiples of 2 (1,2,4,8,16 etc)
            if logical(log2(resl)~=round(log2(resl)))
                error('tcspc:set_resl:power2','set.resolution: Resolution must be a power of 2');
            end
            if resl == obj.current_res
                % Already set
                return;
            end
            % Check the binning
            resl = uint8(log2(resl));
            if resl>26
                error('tscpc:set_resl:out_of_range','set.resolution: Must be in range 0 1 to 2^26ps');
            end
            % Set the binning
            [ret] = calllib('HHlib','HH_SetBinning', obj.dev,resl);
            if ret < 0
                error('tcspc:HHLib:HH_SetBinning','HH_SetBinning : Set Binning Failed %s',obj.getError(ret));
            end
            obj.current_res = 2^resl;
        end
        
        function set.sync_div(obj,div)
            % Set current synchronization divider. Should be multiples of 2
            if logical(log2(div)~=round(log2(div)))
                error('tcspc:set_sync_div:power2','set.sync_div: Resolution must be a power of 2');
            end
            if div == obj.current_sync_div
                % Already set, skip
                return;
            end
            % Check range
            if or(div > 16,div<1)
                error('tcspc:set_sync_div:out_of_range','set.sync_div : must be in range 1 to 16');
            end
            % Make call
            [ret] = calllib('HHlib','HH_SetSyncDiv', obj.dev,div);
            if ret < 0
                error('tcspc:HHLib:HH_SetSyncDiv','HH_SetSyncDiv : Set Sync Div Failed %s',obj.getError(ret));
            end
            % Update
            obj.current_sync_div = div;
        end
        
        function sd=get.sync_div(obj)
            % Get current sync divider value if available
            if obj.current_sync_div == 0
                warning('tcspc:get_sync_div:no_value','Sync Div value not determinable. It must be set before first use.');
                sd = 0;
            else
                sd = obj.current_sync_div;
            end
        end
        
        function set.sync_cfd(obj,cfd)
            % Set current synchronization cfd value. Should be between 0mV
            % and 1000mV
            cfd = round(cfd);
            if or(cfd>1000,cfd<0)
                error('tcspc:set_sync_cfd:out_of_range','Sync CFD out of range. Allowable range is 0-1000mV');
            end
            if cfd == obj.current_sync_cfd
                % Already set, skip
                return;
            end
            % Make call - NOTE, ZERO CROSSING SET TO 20 HERE
            [ret] = calllib('HHlib','HH_SetSyncCFD', obj.dev,cfd,20);
            if ret < 0
                error('tcspc:HHLib:HH_SetSyncCFD','HH_SetSyncCFD : Set Sync CFD Failed %s',obj.getError(ret));
            end
            % Update
            obj.current_sync_cfd = cfd;
        end
        
        function sd=get.sync_cfd(obj)
            % Get current sync cfd value if available. It cannot be read
            % from the device programmatically, only from internal
            % variables.
            if obj.current_sync_cfd == -1
                warning('tcspc:get_sync_cfd:no_value','Sync CFD value not determinable. It must be set before first use.');
                sd = 0;
            else
                sd = obj.current_sync_cfd;
            end
        end
        
        function set.offset(obj,offset)
            % Set current zero time offset in NANOSECONDS
            offset = round(offset);
            if offset == obj.current_offset
                % Already set, skip
                return;
            end
            [ret] = calllib('HHlib','HH_SetOffset', obj.dev,offset);
            if ret < 0
                error('tcspc:HHLib:HH_SetOffset','HH_SetOffset : Set Sync channel offset Failed %s',obj.getError(ret));
            end
            % Update
            obj.current_offset = offset;
        end
        
        function co=get.offset(obj)
            % Get current sync channel offset value if available, in
            % NANOSECONDS
            if isnan(obj.current_offset)
                warning('tcspc:get_offset:no_value','Offset value not determinable. It must be set before first use.');
                co = 0;
            else
                co = obj.current_offset;
            end
        end
        
        
        function set.sync_offset(obj,offset)
            % Set current synchronization offset (to sync channel
            % specifically). Limit is +-99ns
            offset = round(offset);
            if or(offset>99999,offset<-99999)
                error('tcspc:set_sync_offset:out_of_range','Sync offset out of range. Allowable range is 0-1000mV');
            end
            if offset == obj.current_sync_offset
                % Already set, skip
                return;
            end
            [ret] = calllib('HHlib','HH_SetSyncChannelOffset', obj.dev,offset);
            if ret < 0
                error('tcspc:HHLib:HH_SetSyncChannelOffset','HH_SetSyncChannelOffset : Set Sync channel offset Failed %s',obj.getError(ret));
            end
            % Update
            obj.current_sync_offset = offset;
        end
        
        function co=get.sync_offset(obj)
            % Get current sync channel offset value if available
            if isnan(obj.current_sync_offset)
                warning('tcspc:get_sync_offset:no_value','Sync channel offset value not determinable. It must be set before first use.');
                co = 0;
            else
                co = obj.current_sync_offset;
            end
        end
        
        %% Primary data-reading functions
            
        function CR=countrate(obj,channel)
            % Get countrate for given channel (0=sync,1=ch1,2=ch2)
            CR = 0;
            % Make a pointer
            CountratePtr = libpointer('int32Ptr', CR);
            if channel > 0
                [ret, CR] = calllib('HHlib', 'HH_GetCountRate', obj.dev, channel-1, CountratePtr);
            elseif channel == 0
                [ret, CR] = calllib('HHlib', 'HH_GetSyncRate', obj.dev, CountratePtr);
            end
            if ret < 0
                error('tcspc:HHLib:CountRate','HH_GetCountRate/HH_GetSyncRate : Read failed %s',obj.getError(ret));
            end
        end
        
        function out = histogram(obj,integration_time)
            % Run a histogram experiment with settings as already applied
            % Integration time is in seconds
            if ~strcmpi(obj.mode,'HIST')
                error('tcspc:histogram:incorrect_mode','Incorrect HH mode selected');
            end
            itime = round(integration_time*1000);
            % Clear the device
            ret = calllib('HHlib', 'HH_ClearHistMem', obj.dev);
            if ret<0;error('tcspc:HHLib:HH_ClearHistMem','HH_ClearHistMeme : Cannot clear histogram memory %s',obj.getError(ret));end
            % Start measurement
            ret = calllib('HHlib', 'HH_StartMeas', obj.dev,itime);
            if ret<0;error('tcspc:HHLib:HH_StartMeas','HH_StartMeas : Cannot start measurement %s',obj.getError(ret));end
            
            % Display message
            disp(['-> Measuring histogram for ',int2str(itime), ' ms']);
            
            % Check for end
            ctcdone = int32(0);
            ctcdonePtr = libpointer('int32Ptr', ctcdone);
            while (ctcdone==0);[~,ctcdone] = calllib('HHlib', 'HH_CTCStatus', obj.dev, ctcdonePtr);end
            
            % Finished
            ret = calllib('HHlib', 'HH_StopMeas',obj.dev);
            if ret<0;error('tcspc:HHLib:HH_StopMeas','HH_StopMeas : Cannot stop histogram measurement %s',obj.getError(ret));end
            
            % Get data from 2 input channels, augment 3rd (time) channel
            out  = zeros(3,65536,'uint32');
            % Set x-axis (in picoseconds)
            out(1,:) = 0:obj.resolution:(65535*obj.resolution);
            % Read from each channel (0 and 1)
            for i =0:1
                % Make the buffer
                bufferptr = libpointer('uint32Ptr', out(i+2,:));
                % Get the histogram
                [ret,out(i+2,:)] = calllib('HHlib', 'HH_GetHistogram', obj.dev, bufferptr, i, 0);
                if ret<0;error('tcspc:HHLib:HH_GetHistogram','HH_GetHistogram : Cannot get histogram measurement %s',obj.getError(ret));end
            end
            % Count how many photons are returned
            Integralcount = sum(sum(out(2:3,:)));
            fprintf('-> TotalCount=%d (%.2f /s)\n', Integralcount,Integralcount/itime);
        end
        
        function [global_buffer,timing]=tttr(obj,integration_time,tic_val)
            % Run a tttr (time-tagged time-resolved) experiment and return the data
            
            % Check mode
            if strcmpi(obj.current_mode,'HIST')
                error('tcspc:Mode:incorrect','Hydraharp in incorrect operation mode - set to T2 or T3');
            end
            % Is timing required?
            if nargin<3
                tic_val = tic;
            end
            % Check multistop mode
            if obj.multistop
                ms = ' multistop enabled';
            else
                ms = '';
            end
            disp(['Starting TTTR experiment (',obj.mode, ' mode',ms,')']);
            
            % Enable marker inputs
            ret = calllib('HHlib', 'HH_SetMarkerEnable', obj.dev, 1,1,1,1);
            if ret<0;error('tcspc:HHLib:HH_SetMarkerEnable','HH_SetMarkerEnable : Cannot enable markers %s',obj.getError(ret));end
            ret = calllib('HHlib', 'HH_SetMarkerEdges', obj.dev, 1,1,1,1);
            if ret<0;error('tcspc:HHLib:HH_SetMarkerEdges','HH_SetMarkerEdges : Cannot set marker edges %s',obj.getError(ret));end
            ret = calllib('HHlib', 'HH_SetMarkerHoldoffTime', obj.dev, 1e5);
            if ret<0;error('tcspc:HHLib:HH_SetMarkerHoldoffTime','HH_SetMarkerHoldoffTime : Cannot set marker holdofftime %s',obj.getError(ret));end
            
            %Constants for mode and conversion. T2 is every tag, T3 does
            %not count sync pulses.
            if strcmpi(obj.current_mode,'T2')
                modeN=uint8(2);
                if obj.multistop
                    modeN = uint8(3);
                end
            elseif strcmpi(obj.current_mode,'T3')
                modeN=uint8(3);
                obj.multistop = false;
            end
            
            
            % Global (outer) buffer using "photons" class for data
            global_buffer = photons(modeN);
            global_buffer.preallocate(obj.gmax);
            gpos          = 1;
            
            % Initial state for conversions
            state     = zeros(65540,1,'uint64');
            state(3)  = 2^15;   % Initialize marker to midpoint
            
            % Buffer to pass to driver for records
            buffer    = uint32(zeros(1,obj.TTREADMAX));
            bufferptr = libpointer('uint32Ptr', buffer);
            
            % Photon count variable
            nactual    = int32(0);
            nactualptr = libpointer('int32Ptr', nactual);
            
            % Count timer
            ctcdone    = int32(0);
            ctcdonePtr = libpointer('int32Ptr', ctcdone);
            
            % Issue "Start measurement" command
            ret = calllib('HHlib', 'HH_StartMeas', obj.dev,floor(integration_time*1000));
            timing.start = toc(tic_val);
            if (ret<0);error('tcspc:HHLib:HH_StartMeas','HH_StartMeas : error. Aborted. %s',obj.getError(ret));end
            
            % Enter loop, continously reading from buffer
            startt = tic();lastto = toc(startt);
            
            flags = int32(0);
            flagsPtr = libpointer('int32Ptr', flags);
            while(1)
                % Check flags
                [ret,flags] = calllib('HHlib', 'HH_GetFlags', obj.dev, flagsPtr);
                if (ret<0);error('tcspc:HHLib:HH_GetFlags','HH-GetFlags: error %s',obj.getError(ret));end
                
                % Check for fifo-full flag
                if (bitand(uint32(flags),obj.FLAG_FIFOFULL))
                    warning('tcspc:tttr:FIFO_Full','FiFo Overrun.');
                    break;
                end
                
                % Read from buffer
                [ret, buffer, nactual] = calllib('HHlib','HH_ReadFiFo', obj.dev, bufferptr, obj.TTREADMAX, nactualptr);
                
                %Note that HH_ReadFiFo may return less than requested
                if (ret<0);error('tcspc:HHLib:FIFO_Read','Read FiFO error %s',obj.getError(ret));end
                
                % Any records?
                if(nactual)
                    if (gpos+nactual) > obj.gmax
                        warning('tcspc:tttr:Buffer_Full','Main Record Buffer is full.');
                        break;
                    end
                    % Convert using mex complied record to photon
                    % conversion
                    if obj.multistop
                        [p,state] = stream_multistop_mex(buffer(1:nactual),state);
                    else
                        [p,state] = stream_record_to_photons_mex(buffer(1:nactual),modeN,state);
                    end
                    % Add to global buffer
                    try
                        global_buffer.consume(p);
                    catch
                        warning('Exceeded photon preallocation');
                        break
                    end
                    s    = size(p);gpos = gpos+s(1);
                else
                    % None? Maybe its done
                    [ret,ctcdone] = calllib('HHlib', 'HH_CTCStatus', obj.dev, ctcdonePtr);
                    if (ret<0);error('tcspc:tttr:CTCStatus_Error','HH_CTCStatus error - could not read countdown timer status. %s',obj.getError(ret));end
                    if (ctcdone);disp('Time out, completed.');break;end
                end
                % Just show whats going on
                if toc(startt) > lastto + 2
                    fprintf('%.3i s : %d photons\n',toc(startt),gpos);
                    lastto = toc(startt);
                end
            end
            % Ended, stop
            timing.stop = toc(tic_val);
            obj.stop();
            
            % Crop down
            global_buffer.shrink();
            global_buffer.periods = state(5:end);
            
        end
        
        function stop(obj)
            ret = calllib('HHlib', 'HH_StopMeas', obj.dev);
            if (ret<0);error('tcspc:HHLib:HH_StopMeas','HH_stopMeas failed %s',obj.getError(ret));end
        end
        
        %% Helper functions
        
        function auto_configure(obj)
            % Automatically set CFD, divider, resolution.
            cfd_range = [1:35,40:5:1000];
            s = zeros(size(cfd_range));
            % Loop over CFD range
            for i = 1:numel(cfd_range)
                obj.sync_cfd = cfd_range(i);
                pause(0.2);
                s(i) = obj.countrate(0);
                if i>5
                    if all(s(i-3:i) == 0)
                        break;
                    end
                end
            end
            % Determine CFD level
            s = s-max(s)/2;
            p = find(s>0,1,'last');
            p2= round(cfd_range(p)*0.9);
            % Warn if out of a good range
            if and(p2>100,p2<900)
                disp(['Setting CFD to ',int2str(p2),'mV']);
            elseif p2<100
                disp(['**Warning - LOW CFD** Setting CFD to ',int2str(p2),'mV']);
            elseif p2>900
                disp(['**Warning - HIGH CFD** Setting CFD to ',int2str(p2),'mV']);
            end
            % Set CFD
            obj.sync_cfd = p2;
            % Check rep rate and set divider and resolution
            pause(0.2);
            if obj.countrate(0) > 12.5e6
                % Change divider
                div = 2^ceil(log2(double(obj.countrate(0))/12.5e6));
                obj.sync_div = div;
                disp(['Sync rate is above 10MHz. Changing divider to ',int2str(div)]);
            end
            pause(0.2);
            % Check range available
            overfill = (1/(double(obj.countrate(0))/obj.sync_div))/((2^15)*1e-12);
            % Change if overfilled
            if overfill > 1
                resl = 2^ceil(log2(overfill));
                obj.resolution = resl;
                disp(['Settings do not allow complete range storage - changing base resolution to ',int2str(resl), ' ps']);
            end
        end
        
        function Error=getError(~,errcode)
            Error     = blanks(40);
            ErrorPtr  = libpointer('cstring', Error);
            [ret, Error] = calllib('HHlib', 'HH_GetErrorString', ErrorPtr,errcode);
            if ret < 0;error('tcspc:HHLib:GetErrorString','HH_GetErrorString failed');end
        end
    end
end