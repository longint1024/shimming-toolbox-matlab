classdef ShimCom_Greg < ShimCom 
%SHIMCOMACDC - Shim Communication for AC/DC neck coil 
%
% .......
%   
% Usage
%
%   Shims = ShimCom_Greg(  )
%
%   Shims contains fields
%
%       .Cmd
%           
%       .ComPort    
%
%       .Data 
%
%       .Params
%
% =========================================================================
% Notes
%
%   Part of series of classes pertaining to shimming:
%
%    ProbeTracking
%    ShimCal
%    ShimCom
%    ShimEval
%    ShimOpt
%    ShimSpecs
%    ShimTest 
%    ShimUse
%     
%    ShimCom_Greg is a ShimCom subclass.
%
% =========================================================================
% Updated::20180611::ryan.topfer@polymtl.ca
% =========================================================================

% =========================================================================
% =========================================================================
methods
% =========================================================================
function Shim = ShimCom_Greg( Specs )
%SHIMCOM - Shim Communication

if nargin < 2 || isempty( Specs ) 
    Shim.Specs = ShimSpecs_Greg( );
end

Shim.ComPort = ShimCom_Greg.initializecomport( Shim.Specs ) ;
Shim.Cmd     = ShimCom_Greg.getcommands( ) ;

Shim.Data.output = uint8(0) ;
Shim.Data.input  = uint8(0) ;

Shim.Params.nBytesToRead     = [] ; % depends on cmd sent to system
Shim.Params.nSendAttemptsMax = 5; % # communication attempts before error

end
% =========================================================================
function [isAckReceived] = getsystemheartbeat( Shim ) ;
%GETSYSTEMHEARTBEAT

warning('Unimplemented funct. ShimCom_Greg.GETSYSTEMHEARTBEAT()')
isAckReceived=true;

end
% =========================================================================
function [] = setandloadshim( Shim, channel, current )  ;
%SETANDLOADSHIM
%
% Set shim current (in units of Amps) for single channel 
% 
% [] = SETANDLOADSHIM( Shims, channelIndex, current ) 

% TODO
% temp. fix: scaling to mA
current = current*1000;

calibrationVal = ( current - Shim.Specs.Com.feedbackcalibrationcoeffy(channel) )/ Shim.Specs.Com.feedbackcalibrationcoeffx(channel) ;

% Variable used to convert currents into DAC value-------------------------

  preampresistance = 0.22;
  DACmaxvalue      = 26214;
  
%Conversion----------------------------------------------------------------

  DACcurrent = num2str((( Shim.Specs.Dac.referenceVoltage - calibrationVal * 0.001 * preampresistance) * DACmaxvalue));
  Channel=num2str(channel);
  
  
  command=strcat(Shim.Cmd.updateOneChannel,Channel,'_',DACcurrent);

fprintf(Shim.ComPort,'%s',command,'sync');  

end

% =========================================================================
function [] = setandloadallshims( Shim, currents )
%SETANDLOADALLSHIM
% 
% [] = SETANDLOADALLSHIMS( Shim, currents ) 
%
% Update all channels with currents (8-element vector w/units in A)

% TODO
% temp. fix: scaling to mA
currents = currents *1000;

currentsDac = Shim.ampstodac( currents ) ;

command = strcat('o',num2str(currentsDac(1)),num2str(currentsDac(2)),num2str(currentsDac(3)),num2str(currentsDac(4)),...
          num2str(currentsDac(5)),num2str(currentsDac(6)),num2str(currentsDac(7)),num2str(currentsDac(8)));

Shim.sendcmd( command ) ;

fscanf(Shim.ComPort,'%s');

end
%==========================================================================
function [dacValue] = ampstodac( Shim, currents )
%AMPSTODAC
%
% Convert currents from Amps to DAC value.
 
calibrationVal = zeros(Shim.Specs.Amp.nChannels,1);

for i=1:Shim.Specs.Amp.nChannels
    calibrationVal(i) = ( currents(i) - Shim.Specs.Com.feedbackcalibrationcoeffy(i) ) / Shim.Specs.Com.feedbackcalibrationcoeffx(i);
end
  
% Variable used to convert currents into DAC value-------------------------

preampresistance = 0.22;
DACmaxvalue      = 26214;
  
%Conversion----------------------------------------------------------------

dacValue = round( (Shim.Specs.Dac.referenceVoltage - calibrationVal * 0.001 * preampresistance) * DACmaxvalue ) ;

end
% =========================================================================
function [] = resetallshims( Shim )
%RESETALLSHIMS 
%
%   Shim currents reset to 0 A
   
Shim.sendcmd( Shim.Cmd.resetAllShims );

end
% =========================================================================
function [] = opencomport( Shim ) 
%OPENCOMPORT
% 
% Open serial communication port & reset Arduino Board 

instrument = instrfind;

if isempty(instrument)
    Shim.ComPort = ShimCom_Greg.initializecomport( Shim.Specs ) ;
end

fopen(Shim.ComPort);

fprintf(Shim.ComPort,'%s',Shim.Cmd.resetArduino,'sync');

nlinesFeedback = 8 ; % Lines of feedback after opening serial communication

% Read the Feedback from the arduino---------------------------------------
for i=1:nlinesFeedback
    a = fscanf(Shim.ComPort,'%s');
end

end
% =========================================================================
function [] = closecomport( Shim ) 
%CLOSECOMPORT
% 
% Close serial communication port 

fclose(Shim.ComPort);
delete(Shim.ComPort);
clear Shim.ComPort;

end
% =========================================================================
function [ChannelOutput] = getchanneloutput( Shim , ~, Channel )
%GETCHANNELOUTPUT
% 
%   Querry and display a current feedback for one channel
 
%Command to querry the channel feedback------------------------------------
command = strcat(Shim.Cmd.getChannelFeedback,Channel);

fprintf(Shim.ComPort,'%s',command,'sync');

% Read the Feedback from the arduino---------------------------------------
ChannelOutput=fscanf(Shim.ComPort,'%s');

end
% =========================================================================
function [ChannelOutputs] = getallchanneloutputs( Shim )
%GETALLCHANNELSOUTPUTS      
%
% ChannelOutputs = GETALLCHANNELOUTPUTS( Shim ) 
% 
% ChannelOutputs has fields
%
%   .current [amperes]
 
Shim.sendcmd( Shim.Cmd.getAllChannelOutputs ) ;

ChannelOutputs.current = zeros(1,Shim.Specs.Amp.nChannels);

for iCh = 1 : Shim.Specs.Amp.nChannels
    ChannelOutputs.current = str2double( fscanf( Shim.ComPort,'%s' ) ); 
end

end
% =========================================================================
function [Shims, isSendOk]= sendcmd( Shim, command )
%SENDCMD 
% 
%   Transmits command from client to shim microcontroller 

isSendOk  = [] ;

if strcmp( Shim.ComPort.Status, 'closed' ) ;
    fopen( Shim.ComPort ) ;
end 
    
fprintf( Shim.ComPort, '%s', command, 'sync' ) ;
    
end
% =========================================================================
function [calibrationvalues]= getcalibrationcoefficient( Shim)
% getcalibrationcoefficient : 
%
% - Send a command to calibrate Adc feedback coefficients
% - Receive and save calibrationvalues to calculate the coefficients
%
%--------------------------------------------------------------------------

if strcmp( Shim.ComPort.Status, 'closed' ) ;
    fopen( Shim.ComPort ) ;
end 
    
fprintf( Shim.ComPort,'%s', Shim.Cmd.calibrateDacCurrent,'sync' ) ;

ncalibrationpoint = 5 ; %Number of calibration points to calculate coefficient
calibrationvalues = zeros(ncalibrationpoint,8);
display('Calibration in process, please wait')
pause(41);

% Read Feedback from the arduino-------------------------------------------
for j=1:(Shim.Specs.Amp.nChannels)
    for i=1:(ncalibrationpoint)  
        a = fscanf(Shim.ComPort,'%s');
        display(a);
        calibrationvalues(i,j) = str2double(a);
    end
end

Shim.resetallshims() ;

display(calibrationvalues);

end
% =========================================================================

end
% =========================================================================
% =========================================================================
methods(Static)
% =========================================================================
function [Cmd] = getcommands( )
% getcommands :
%
% - Get shim system commands 
%
%--------------------------------------------------------------------------

% System commands (as strings)---------------------------------------------

Cmd.getAllChannelOutputs  = 'q'; 
Cmd.updateOneChannel      = 'a';
Cmd.resetAllShims         = 'w' ;

Cmd.calibrateDacCurrent   = 'x';

Cmd.resetArduino          = 'r';

Cmd.querry                = 'q' ;

end
% =========================================================================
function [ComPort] = initializecomport( Specs )
% initializecomport : 
%
% -  Initialize (RS-232) Communication Port
% 
%--------------------------------------------------------------------------

% Serial Port 
%
warning( 'Serial port device name may change depending on the host computer.' )

if ismac
   % portName = '/dev/cu.usbserial' ;          % USB to serial adapter
    portName = '/dev/tty.usbserial' ;          % USB to serial adapter
elseif isunix
    portName = '/dev/ttyUSB0' ;   
elseif ispc
    portName = 'COM4' ;
else
    error('What kind of computer is this!?')
end

ComPort = serial( portName,...
    'BaudRate', Specs.Com.baudRate,...
    'DataBits', Specs.Com.dataBits,...
    'StopBits', Specs.Com.stopBits,...
    'FlowControl', Specs.Com.flowControl,...
    'Parity', Specs.Com.parity,...
    'ByteOrder', Specs.Com.byteOrder ) ; 

end
% =========================================================================

% =========================================================================
function dacCount = voltstodac( Shims, current)
%VOLTSTODAC

%MAX_VOLTAGE = 2.5 ; % mV 

MAX_DIGI = (2^(Shims.Specs.Dac.resolution-1)) - 1 ; % Digital to Analog Converter max value

dacCount = int16( current*( MAX_DIGI/Shims.Specs.Dac.maxCurrent  ) ) ;

end
% =========================================================================


end
% =========================================================================

end