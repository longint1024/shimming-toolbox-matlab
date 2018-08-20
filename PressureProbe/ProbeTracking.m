classdef ProbeTracking < ProbeTracked & AuxTracking 
% PROBETRACKING - Respiratory probe for real-time shimming 
%
% Aux = PROBETRACKING(  )
%
%   Aux contains fields
%           
%       .ComPort    
%
%       .Data 
%
%       .Specs
%
% .......
%
%   Description
%
%
% =========================================================================
% Part of series of classes pertaining to shimming:
%
%    AuxTracking
%    ShimCal
%    ShimCom
%    ShimEval
%    ShimOpt
%    ShimSpecs
%    ShimTest 
%    ShimUse
%
% =========================================================================
% Updated::20180721::ryan.topfer@polymtl.ca
% =========================================================================

% *** TODO 
%
% ..... 
%
%   check/assert ComPort is in fact open before attempting read
%   (issue is that strcmp( ComPort.status, 'closed' ) is fairly slow (~ 3ms)
%   compared to the 1/10ms sample rate of the probe.      
% =========================================================================

properties   
    ComPort ;
end

% =========================================================================
% =========================================================================
methods
% =========================================================================
function Aux = ProbeTracking( Specs )
%PROBE - ProbeTracking  

if nargin < 1
    Specs = [] ;
end

[Aux.ComPort, Aux.Specs] = ProbeTracking.declareprobe( Specs ) ;

Aux.Data.p = [];

if isempty( Aux.ComPort )
    % return ProbeTracked object instead?
end

end    
% =========================================================================
function [AuxInert] = copyinert( Aux )
%COPYINERT  
% 
% Aux = COPYINERT( Aux )

AuxInert = ProbeTracked(  ) ; % or just allow that constructor to accept ProbeTracking as an input and copy the fields...

AuxInert.Data     = Aux ;
AuxInert.Specs.dt = Aux.Specs.dt ;

end
% =========================================================================
function [] = delete( Aux )
%DELETE  
% DELETE( Aux )
% 
% Destructor. Calls Aux.deletecomport( ) 

if myisfield( Aux, 'ComPort' ) && ~isempty( Aux.ComPort ) 
    Aux.deletecomport();
end

clear Aux ;

end
% =========================================================================
function [Aux] = deletecomport( Aux )
%DELETECOMPORT  
% 
% DELETECOMPORT( Aux )
% 
% Proper way to close + delete the serial port object

if myisfield( Aux, 'ComPort' ) && ~isempty( Aux.ComPort ) 
    fclose( Aux.ComPort ) ;
    delete( Aux.ComPort ) ;
    clear Aux.ComPort  ;
else
    disp('Failed to delete .ComPort - it does not exist.');
end

end
% =========================================================================
function [isTracking] = begintracking( Aux )
%BEGINTRACKING - Initialize & open (RS-232) communication port 
%
% [isTracking] = BEGINTRACKING( Aux )
%
% Opens Aux.ComPort 
%
% Returns TRUE if successful

isTracking = false;

maxCommunicationAttempts = 3; 

fopen(Aux.ComPort);

iAttempt = 1 ;
disp('Connecting to respiratory probe...')

while(~isTracking && iAttempt <= maxCommunicationAttempts )

    disp(['Attempt #' num2str(iAttempt)]);    
   
    firstWord = fscanf( Aux.ComPort, '%u') ;
    
    if( ~isempty(firstWord) && isnumeric(firstWord) )  
        isTracking = true;
    end
    
    iAttempt = iAttempt + 1;

end

if isTracking
    disp('Communication successful. Reading in from serial port...')
else
    Aux.stoptracking() ;
    error('Communication to respiratory probe failed. Closing Aux.ComPort.')
end

end
% =========================================================================
function [] = stoptracking( Aux )
%STOPTRACKING - close (RS-232) Communication Port 
%
% [] = STOPTRACKING( Aux )
%
% fclose( Aux.ComPort )

fclose(Aux.ComPort);

end
% =========================================================================
function [p] = getupdate( Aux )
%GETUPDATE 
%
% Reads a single (16-bit) pressure measurement (p) in from open com port and 
% returns p as the typecasted double.
%
% p = GETUPDATE( Aux )

assert( strcmp( Aux.ComPort.Status, 'open' ), 'Error: Serial port is closed.' );

p = fscanf( Aux.ComPort, '%u', [1 1] );

end  
% =========================================================================
function [pressureLog, sampleTimes] = recordandplotpressurelog( Aux, Params ) 
%RECORDANDPLOTPRESSURELOG    
%
%   Description
%   
%   Reads pressure data from microcontroller 
%
%   Syntax
%
%   [pressureLog, sampleTimes] = RECORDANDPLOTPRESSURELOG( Aux, Parameters )
%
%    .......................
%   
%   The following Parameters.fields are supported
%
%   .isSavingData
%       default = true
%
%   .isForcingOverwrite 
%       Will overwrite the log files if they already exist. 
%       default = false
%
%   .pressureLogFilename
%       default = ['./' datestr(now,30) '-pressureLog.bin' ] ; 
%
%   .sampleTimesFilename
%       default = ['./' datestr(now,30) '-sampleTimes.bin' ] ;
%
%   .runTime 
%       Total sampling time in seconds.
%       default = 30
%
%   .isPlottingInRealTime
%       [default : true ]
%
%   .refreshRate  
%       Rate at which the real-time display refreshes. 
%       Problems may arise if this is too fast!
%       [default : 4 Hz ]

assert( strcmp( Aux.ComPort.Status, 'closed' ), 'Error: Serial port is open/in use.' );

DEFAULT_ISSAVINGDATA          = true ;
DEFAULT_ISFORCINGOVERWRITE    = false ;
DEFAULT_PRESSURELOGFILENAME   = ['./' datestr(now,30) '-pressureLog.bin' ] ;
DEFAULT_SAMPLETIMESFILENAME   = ['./' datestr(now,30) '-sampleTimes.bin' ] ;

if  nargin < 2 || isempty(Params)
    Params.dummy = [] ;
end
 
if  ~myisfield( Params, 'isSavingData' ) || isempty(Params.isSavingData)
    Params.isSavingData = DEFAULT_ISSAVINGDATA ;
end

if  ~myisfield( Params, 'isForcingOverwrite' ) || isempty(Params.isForcingOverwrite)
    Params.isForcingOverwrite = DEFAULT_ISFORCINGOVERWRITE ;
end

if  ~myisfield( Params, 'pressureLogFilename' ) || isempty(Params.pressureLogFilename)
    Params.pressureLogFilename = DEFAULT_PRESSURELOGFILENAME ;
end

if  ~myisfield( Params, 'sampleTimesFilename' ) || isempty(Params.sampleTimesFilename)
    Params.sampleTimesFilename  = DEFAULT_SAMPLETIMESFILENAME ; 
end

msg = input( ['\n Press [Enter] to begin recording pressure log.\n'], 's' );
assert( isempty(msg), 'Cancelled calibration.')

% ------- 
isUserSatisfied = false ;

while ~isUserSatisfied
    
    % ------- 
    Aux.Data.p = 0 ;
    Aux = Aux.recordpressurelog( Params ) ;
    
    pressureLog = Aux.Data.p ;    
    sampleTimes = (Aux.Specs.dt/1000)*[0:(numel(Aux.Data.p)-1)] ;
   
    % ------- 
    fprintf(['\n ----- \n Plotting pressure for user verification... \n']) ;
    figure ;
    plot( sampleTimes, Aux.Data.p, '+' ) ;

    if Params.isSavingData
        title( Params.pressureLogFilename ) ;
    else
        title( 'Pressure log' )
    end
    xlabel('Time (s)');
    ylabel('Pressure (AU)');
    
    response = input(['\n Is the current pressure log satisfactory? ' ...
        'Enter 0 to rerecord; 1 to continue. \n']) ;

    isUserSatisfied = logical(response) ;

end

% ------- 
if Params.isSavingData
    pressureLogFid = fopen( Params.pressureLogFilename, 'w+' ) ;
    fwrite( pressureLogFid, Aux.Data.p, 'double' ) ;
    fclose( pressureLogFid );

    sampleTimesFid = fopen( Params.sampleTimesFilename, 'w+' ) ;
    fwrite( sampleTimesFid, sampleTimes, 'double' ) ;
    fclose( sampleTimesFid );
end

end
% =========================================================================
function [Aux] = recordpressurelog( Aux, Params )
%RECORDPRESSURELOG  
%
% Continuously tracks respiratory probe.
%
% Aux = TRACKPROBE( Aux, Params )
%
% Params
%   .runTime
%       [default : 30 s]
%
%   .isPlottingInRealTime
%       [default : true ]
%
%   .refreshRate  
%       Rate at which the real-time display refreshes. 
%       Problems may arise if this is too fast!
%       [default : 4 Hz ]

DEFAULT_RUNTIME = 30 ; % [units : s]

DEFAULT_ISPLOTTINGINREALTIME = true ; 
DEFAULT_REFRESHRATE          = 4 ; % [units : Hz]
if  nargin < 2 || isempty(Params)
    Params.dummy = [] ;
end

if  ~myisfield( Params, 'runTime' ) || isempty(Params.runTime)
    Params.runTime = DEFAULT_RUNTIME ;
end

if  ~myisfield( Params, 'isPlottingInRealTime' ) || isempty(Params.isPlottingInRealTime)
    Params.isPlottingInRealTime = DEFAULT_ISPLOTTINGINREALTIME ;
end

if  ~myisfield( Params, 'refreshRate' ) || isempty(Params.refreshRate)
    Params.refreshRate = DEFAULT_REFRESHRATE ;
end
    
% ------- 
StopButton     = stoploop({'Stop recording'}) ;
Aux.Data.p = [] ;
sampleIndices  = [] ;

nSamples = Params.runTime / (Aux.Specs.dt/1000) ;
iSample  = 0 ; 

isTracking = Aux.begintracking() ;

assert(isTracking, 'Could not begin tracking. Check device connection.')

if Params.isPlottingInRealTime

    % ------- 
    % figure
    figureHandle = figure('NumberTitle','off',...
        'Name','Sonde de respiration',...
        'Color',[0 0 0],'Visible','off');
        
    % Set axes
    axesHandle = axes('Parent',figureHandle,...
        'YGrid','on',...
        'YColor',[0.9725 0.9725 0.9725],...
        'XGrid','on',...
        'XColor',[0.9725 0.9725 0.9725],...
        'Color',[0 0 0]);

    hold on;
        
    plotHandle = plot(axesHandle,0,0,'Marker','.','LineWidth',1,'Color',[1 0 0]);
        
    xlim(axesHandle,[0 nSamples]);
        
    title('Respiration Aux','FontSize',15,'Color',[1 1 0]);
    xlabel('Sample index','FontWeight','bold','FontSize',14,'Color',[1 1 0]);
    ylabel('Amplitude','FontWeight','bold','FontSize',14,'Color',[1 1 0]);

    drawnow limitrate; 
    set(figureHandle,'Visible','on');

end

% for real-time plotting, updating @the same rate as the pressure samples
% (100 Hz) poses a problem (computer can't seem to keep up with the incoming samples).
% solution is to update the display ~every so often~ (4x per second seems OK)
nSamplesBetweenRefresh = (1/Params.refreshRate)/(Aux.Specs.dt/1000) ;

while ( iSample < nSamples ) && ~StopButton.Stop()

    iSamplesBetweenRefresh = 0;

    for iSamplesBetweenRefresh = 1 : nSamplesBetweenRefresh 
        
        iSample = iSample + 1 ;
        Aux.Data.p(end+1) = Aux.getupdate() ;
        sampleIndices(end+1)  = iSample ;

    end

    if Params.isPlottingInRealTime
        set(plotHandle,'YData',Aux.Data.p,'XData',sampleIndices);
    end

end

Aux.stoptracking();

StopButton.Clear() ;

end
% =========================================================================
end

% =========================================================================
% =========================================================================

% =========================================================================
% =========================================================================
methods(Static)
% =========================================================================
function [ComPort, AuxSpecs] = declareprobe( AuxSpecs )
%DECLAREPROBE Declares serial object for probe 
% 
% [ComPort,AuxSpecs] = declareprobe( AuxSpecs )
%
% AuxSpecs can have the following fields 
%  
% NOTE 
%   these are not really optional/configurable... TODO: remove deprecated/false 'options'
%
% .dt
%   Interval between pressure samples [units: ms]
%   Should be a positive multiple of the minimum period of 10 ms.
% 
% .baudRate
%   default : 115200
%
% .portName 
%   Address of the probe-associated serial port within file system
%   default: 
%       if ismac 
%           portName = '/dev/tty.usbmodem*'
%       elseif isunix
%           portName = '/dev/ttyS100'

ShimUse.customdisplay( ['\n----- Pressure probe -----\n'] );

MIN_ARDUINOPERIOD     = 10 ; % [units: ms] 
DEFAULT_ARDUINOPERIOD = 10 ; % [units: ms] 
DEFAULT_BAUDRATE      = 115200 ;

if nargin < 1 || isempty(AuxSpecs)
    ShimUse.customdisplay('Default parameters will be used:')
    AuxSpecs.dummy = [] ;
end

if ~myisfield( AuxSpecs, 'baudRate' ) || isempty(AuxSpecs.baudRate) ...
    AuxSpecs.baudRate = DEFAULT_BAUDRATE ;
end

if  ~myisfield( AuxSpecs, 'dt' ) || isempty(AuxSpecs.dt) ...
    || (AuxSpecs.dt < MIN_ARDUINOPERIOD) 

        AuxSpecs.dt = DEFAULT_ARDUINOPERIOD ;
else
    
    skipSampleFactor = round( AuxSpecs.dt / MIN_ARDUINOPERIOD ) ;
    AuxSpecs.dt = skipSampleFactor * MIN_ARDUINOPERIOD ;

end


% -------------------------------------------------------------------------
% check and/or assign serial port
ComPort = [] ; 
isAssigningSerialPort = false ;

if  myisfield( AuxSpecs, 'portName' ) && ~isempty(AuxSpecs.portName)
    
    [fileDir,portname,fileExtension] = fileparts( AuxSpecs.portName ) ;
    
    listOfDevices = dir( fileDir ) ;

    isPortDetected = false ;
    
    % Check for file existence. For some reason this doesn't work...
    for iFile = 1 : length(listOfDevices)-1
        if strcmp( [portname fileExtension], Tmp(iFile).name )
            isPortDetected = true ;
        end
    end

    if ~isPortDetected    
        disp(['Warning: Given port name (' AuxSpecs.portName ' ) not found. ' ...
            'Checking default port names.']) ;
        AuxSpecs.portName = [] ;
    end
end

if  ~myisfield( AuxSpecs, 'portName' ) || isempty(AuxSpecs.portName)

    if ismac
        % For some reason this doesn't work...
        % -------
        % if exist( '/dev/tty.usbmodem1411', 'file' ) ; % my macbook's left USB port
        %   AuxSpecs.portName = '/dev/tty.usbmodem1411';
        % elseif exist( '/dev/tty.usbmodem1421', 'file' ) ;
        %     AuxSpecs.portName = '/dev/tty.usbmodem1421' ; % my macbook's right USB port
        % else
        %     error(['Device file not found. ' ...
        %         'Is the microcontroller connected?']) ; 
        % ------
        listOfDevices = dir( '/dev/tty.usbmodem*' ) ;

        if isempty(listOfDevices) 
            ShimUse.customdisplay( 'Error: Device file not found. Check USB device is connected.' ) ;
        elseif length(listOfDevices) ~= 1, ...
            ShimUse.customdisplay( ['Error: Ambiguous device identifier.' ...
                'Enter device file name as function argument. See HELP AuxAuxTracking.declareprobe.'] ) ;
        else
            isAssigningSerialPort = true ;
            AuxSpecs.portName = ['/dev/' listOfDevices.name] ;
        end

    elseif isunix
        % if exist('/dev/ttyS100', 'file')  
            warning('ProbeTracking.declareprobe() assumes a serial port address/name that may be invalid!')
            AuxSpecs.portName = '/dev/ttyS100' ;
        % % else
        %     errorMsg = ['Device file ( ' portName ' ) not found.'  ...
        %     'Is the microcontroller connected?' ...
        %     'Ensure symbolic link exists between actual Arduino device' ...
        %     'file and the phantom-device file discoverable by MATLAB:' ...
        %     'In a terminal, type: ' ... 
        %     'sudo ln -f /dev/ttyACM0 /dev/ttyS100' ] ; 
        %     error( errorMsg ) ;
        % end

    else
        error( 'OS not supported' ) ;
    end
end


if isAssigningSerialPort
    ComPort = serial( AuxSpecs.portName, 'BaudRate',  AuxSpecs.baudRate ) ;

    ShimUse.customdisplay( [ 'Arduino sampling frequency = ' ...
        num2str(1000/AuxSpecs.dt) ' Hz'] )
    % ComPort = serial( AuxSpecs.portName, ...
    %   'InputBufferSize', 8 ) ; % 2x 32-bit floats
else
    ComPort = [] ;
end

end
% =========================================================================

% =========================================================================

end
% =========================================================================
% =========================================================================

end