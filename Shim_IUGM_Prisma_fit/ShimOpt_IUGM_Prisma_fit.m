classdef ShimOpt_IUGM_Prisma_fit < ShimOpt
%SHIMOPT_IUGM_PRISMA_FIT - Shim Optimization for Prisma-fit @ UNF 
%     
% =========================================================================
% Updated::20180726::ryan.topfer@polymtl.ca
% =========================================================================

% =========================================================================
% =========================================================================    
methods
% =========================================================================
function Shim = ShimOpt_IUGM_Prisma_fit( Params, Field )
%SHIMOPTACDC - Shim Optimization

Shim.img   = [] ;
Shim.Hdr   = [] ;
Shim.Field = [] ;       
Shim.Model = [] ;
Shim.Aux   = [] ;
Shim.System.Specs    = ShimSpecs_IUGM_Prisma_fit();
Shim.System.currents = zeros( Shim.System.Specs.Amp.nActiveChannels, 1 ) ; 

if nargin < 1 || isempty( Params ) 
    Params.dummy = [] ;
end

Params = ShimOpt_IUGM_Prisma_fit.assigndefaultparameters( Params ) ;

if Params.isCalibratingReferenceMaps

    Params = ShimOpt_IUGM_Prisma_fit.declarecalibrationparameters( Params ) ;
    [ Shim.img, Shim.Hdr ] = ShimOpt_IUGM_Prisma_fit.calibratereferencemaps( Params ) ;

elseif ~isempty(Params.pathToShimReferenceMaps)
   
   [ Shim.img, Shim.Hdr ] = ShimOpt.loadshimreferencemaps( Params.pathToShimReferenceMaps ) ; 

    % TODO
    % --> DICOM positional fields (notably, ImagePositionPatient & ImageOrientationPatient)
    % refer to the 'patient coordinate system' which is itself established upon positioning
    % the patient (i.e. this coordinate system *moves with the patient table!*)
    % therefore, in fact, i need a way to relate the PCS system to the scanner's (static) shim/coordinate system! 
    
    Shim.Ref.img = Shim.img ;
    Shim.Ref.Hdr = Shim.Hdr ;

end

Shim.Tracker = ProbeTracking( Params.TrackerSpecs )  ; 

if (nargin == 2) && (~isempty(Field))
    
    Shim.setoriginalfield( Field ) ;

end

end
% =========================================================================
function [] = interpolatetoimggrid( Shim, Field )
%INTERPOLATETOIMGGRID 
%
% [] = INTERPOLATETOIMGGRID( Shim, Field )
%
% Interpolates Shim.img (reference maps) to the grid (voxel positions) of
% MaRdI-type Img
% 
% i.e.
%
%   [X,Y,Z] = Field.getvoxelpositions ;
%   Shim.resliceimg( X, Y, Z ) ;
%
% NOTE
%   On how this method differs from that of the parent class ShimOpt:
%
%   The patient coordinate system is defined by the initial (laser) placement
%   of the subject. After the 1st localizer (for which the Z=0 position will
%   correspond to isocenter), it is likely that the operator will choose a
%   particular FOV for the following scans, thereby repositioning the table by
%   a certain amount ( Field.Hdr.Img.ImaRelTablePosition ).  i.e. Isocenter has
%   been moved from Z=0 to Z = Field.Hdr.Img.ImaRelTablePosition.
% 
%   For our multi-coil shim arrays, the shim moves along with the table (as
%   does the patient coordinate system), so a shim field shift at initial
%   location r' = (x',y',z') will continue to be exactly that.
%
%   The scanner shims, on the other hand, are fixed relative to isocenter. So a
%   shim field shift induced at initial table position r', will now instead be
%   induced at r' + Field.Hdr.Img.ImaRelTablePosition.

[X, Y, Z]    = Field.getvoxelpositions ;
[X0, Y0, Z0] = Shim.getvoxelpositions ;

dR = Field.getisocenter() ; 
assert( dR(1) == 0, 'Table shifted in L/R direction?' ) ;
assert( dR(2) == 0, 'Table shifted in A/P direction?' ) ;

if ( dR(3) ~= 0 ) % field positions originally at Z0 have been shifted
    % NOTE
    %   tablePosition is increasingly negative the more it is into the scanner.
    %   the opposite is true for the z-coordinate of a voxel in the dicom
    %   reference system.
    warning('Correcting for table shift with respect to shim reference images')
    Z0 = Z0 + dR(3) ;
    Shim.Hdr.ImagePositionPatient(3) = Shim.Hdr.ImagePositionPatient(3) + dR(3) ;   
end

% -------
% check if voxel positions already happen to coincide. if they do, don't interpolate (time consuming).
if any( size(X) ~= size(X0) ) || any( X0(:) ~= X(:) ) || any( Y0(:) ~= Y(:) ) || any( Z0(:) ~= Z(:) )
    Shim.resliceimg( X, Y, Z ) ;
else
    % voxel positions already coincide,
    % i.e.
    assert( all(X0(:) == X(:) ) && all( Y0(:) == Y(:) ) && all( Z0(:) == Z(:) ) ) ;
end

end
% =========================================================================
function [Corrections] = optimizeshimcurrents( Shim, Params )
%OPTIMIZESHIMCURRENTS 
%
% Corrections = OPTIMIZESHIMCURRENTS( Shim, Params )
%   
% Params can have the following fields 
%   
%   .maxCurrentPerChannel
%       [default: determined by class ShimSpecs.Amp.maxCurrentPerChannel]
 
if nargin < 2 
    Params.dummy = [];
end

Corrections = optimizeshimcurrents@ShimOpt( Shim, Params, @checknonlinearconstraints ) ;

function [C, Ceq] = checknonlinearconstraints( corrections )
%CHECKNONLINEARCONSTRAINTS 
%
% Check current solution satisfies nonlinear system constraints
% 
% i.e. this is the C(x) function in FMINCON (see DOC)
%
% C(x) <= 0
%
% (e.g. x = currents)
    
    Ceq = [];
    % check on abs current per channel
    C = abs( corrections ) - Params.maxCurrentPerChannel ;

end

end
% =========================================================================
function [] = setoriginalfield( Shim, Field )
%SETORIGINALFIELD 
%
% [] = SETORIGINALFIELD( Shim, Field )
%
% Sets Shim.Field
%
% Field is a FieldEval type object with .img in Hz

Shim.Field = Field.copy() ;

Shim.interpolatetoimggrid( Shim.Field ) ;
Shim.setshimvolumeofinterest( Field.Hdr.MaskingImage ) ;

% get the original shim offsets
[f0, g0, s0]  = Shim.Field.adjvalidateshim() ;
Shim.System.currents            =  [ ShimOpt_IUGM_Prisma_fit.converttomultipole( [g0 ; s0] ) ] ; 
Shim.System.Tx.imagingFrequency = f0 ;

% if ~isempty( Shim.Aux ) && ~isempty( Shim.Aux.Shim ) 
%     Shim.Aux.Shim.Field = Shim.Field ;
%     Shim.Aux.Shim.interpolatetoimggrid( Shim.Field ) ;
%     Shim.Aux.Shim.setshimvolumeofinterest( Field.Hdr.MaskingImage ) ;
% end

end
% =========================================================================
end

% =========================================================================
% =========================================================================
methods(Access=protected)
% =========================================================================

end
% =========================================================================
% =========================================================================
methods(Static=true, Hidden=true)
% =========================================================================
function  [ Params ] = assigndefaultparameters( Params )
%ASSIGNDEFAULTPARAMETERS  
% 
% Params = ASSIGNDEFAULTPARAMETERS( Params )
% 
% Add default parameters fields to Params without replacing values (unless empty)
%
% DEFAULT_ISCALIBRATINGREFERENCEMAPS = false ;
%
% DEFAULT_PATHTOSHIMREFERENCEMAPS = [] ;
%
% DEFAULT_PROBESPECS = [] ;


DEFAULT_ISCALIBRATINGREFERENCEMAPS = false ;
DEFAULT_PATHTOSHIMREFERENCEMAPS    = '~/Projects/Shimming/Static/Calibration/Data/ShimReferenceMaps_IUGM_Prisma_fit_20180726';
DEFAULT_PROBESPECS                 = [] ;

if ~myisfield( Params, 'isCalibratingReferenceMaps' ) || isempty(Params.isCalibratingReferenceMaps)
   Params.isCalibratingReferenceMaps = DEFAULT_ISCALIBRATINGREFERENCEMAPS ;
end

if ~myisfield( Params, 'pathToShimReferenceMaps' ) || isempty(Params.pathToShimReferenceMaps)
   
    if Params.isCalibratingReferenceMaps
        today = datestr( now, 30 ) ;
        today = today(1:8) ; % ignore the time of the day
        Params.pathToShimReferenceMaps = [ '~/Projects/Shimming/Static/Calibration/Data/' ...
                        'ShimReferenceMaps_IUGM_Prisma_fit_' today ] ;
    else
        Params.pathToShimReferenceMaps = DEFAULT_PATHTOSHIMREFERENCEMAPS ;
    end

end

if ~myisfield( Params, 'TrackerSpecs' ) || isempty(Params.TrackerSpecs)
   Params.TrackerSpecs = DEFAULT_PROBESPECS ;
end

end
% =========================================================================
function Params = declarecalibrationparameters( Params )
%DECLARECALIBRATIONPARAMETERS
% 
% Initializes parameters for shim reference map construction (aka shim calibration)

% error('if Params is empty, then replace w/following Params :' )
% ...

Params.nChannels  = 8 ;
Params.nCurrents  = 2 ;
Params.nEchoes    = 1 ; % nEchoes = # phase *difference* images

% 2 columns: [ MAG | PHASE ] ;
Params.dataLoadDirectories = cell( Params.nEchoes, 2, Params.nCurrents, Params.nChannels ) ;

Params.currents = zeros( Params.nChannels, Params.nCurrents ) ; 
% will read shim current offsets (relative to baseline 'tune-up' values)
% directly from Siemens DICOM Hdr below, but they should be:
% Params.currents = [ -30 30; % A11
%                     -30 30; % B11
%                     -30 30; % A10
%                     -600 600; % A20
%                     -600 600; % A21
%                     -600 600; % B21
%                     -600 600; % A22
%                     -600 600;] ; % B22
tmp = { ...
    '~/Projects/Shimming/Static/Calibration/Data/acdc_21p/149-eld_mapping_shim0_axial_fovPhase100perc_phaseOver0perc_S76_DIS3D/echo_7.38/'  ;
    '~/Projects/Shimming/Static/Calibration/Data/acdc_21p/151-eld_mapping_shim0_axial_fovPhase100perc_phaseOver0perc_S78_DIS3D/echo_7.38/' ;
    '~/Projects/Shimming/Static/Calibration/Data/acdc_21p/153-gre_field_mapping_A11_minus30_S80_DIS3D/echo_7.38/' ;
    '~/Projects/Shimming/Static/Calibration/Data/acdc_21p/155-gre_field_mapping_A11_minus30_S82_DIS3D/echo_7.38/' ;
    '~/Projects/Shimming/Static/Calibration/Data/acdc_21p/157-gre_field_mapping_A11_plus30_S84_DIS3D/echo_7.38/' ;
    '~/Projects/Shimming/Static/Calibration/Data/acdc_21p/159-gre_field_mapping_A11_plus30_S86_DIS3D/echo_7.38/' ;
    '~/Projects/Shimming/Static/Calibration/Data/acdc_21p/161-gre_field_mapping_B11_minus30_S88_DIS3D/echo_7.38/' ;
    '~/Projects/Shimming/Static/Calibration/Data/acdc_21p/163-gre_field_mapping_B11_minus30_S90_DIS3D/echo_7.38/' ;
    '~/Projects/Shimming/Static/Calibration/Data/acdc_21p/165-gre_field_mapping_B11_plus30_S92_DIS3D/echo_7.38/' ;
    '~/Projects/Shimming/Static/Calibration/Data/acdc_21p/167-gre_field_mapping_B11_plus30_S94_DIS3D/echo_7.38/' ;
    '~/Projects/Shimming/Static/Calibration/Data/acdc_21p/169-gre_field_mapping_A10_minus30_S96_DIS3D/echo_7.38/' ;
    '~/Projects/Shimming/Static/Calibration/Data/acdc_21p/171-gre_field_mapping_A10_minus30_S98_DIS3D/echo_7.38/' ;
    '~/Projects/Shimming/Static/Calibration/Data/acdc_21p/173-gre_field_mapping_A10_plus30_S101_DIS3D/echo_7.38/' ;
    '~/Projects/Shimming/Static/Calibration/Data/acdc_21p/175-gre_field_mapping_A10_plus30_S103_DIS3D/echo_7.38/' ;
    '~/Projects/Shimming/Static/Calibration/Data/acdc_21p/177-gre_field_mapping_A20_minus600_S105_DIS3D/echo_7.38/' ;
    '~/Projects/Shimming/Static/Calibration/Data/acdc_21p/179-gre_field_mapping_A20_minus600_S107_DIS3D/echo_7.38/' ;
    '~/Projects/Shimming/Static/Calibration/Data/acdc_21p/181-gre_field_mapping_A20_plus600_S109_DIS3D/echo_7.38/' ;
    '~/Projects/Shimming/Static/Calibration/Data/acdc_21p/183-gre_field_mapping_A20_plus600_S111_DIS3D/echo_7.38/' ;
    '~/Projects/Shimming/Static/Calibration/Data/acdc_21p/185-gre_field_mapping_A21_minus600_S113_DIS3D/echo_7.38/' ;
    '~/Projects/Shimming/Static/Calibration/Data/acdc_21p/187-gre_field_mapping_A21_minus600_S115_DIS3D/echo_7.38/' ;
    '~/Projects/Shimming/Static/Calibration/Data/acdc_21p/189-gre_field_mapping_A21_plus600_S117_DIS3D/echo_7.38/' ;
    '~/Projects/Shimming/Static/Calibration/Data/acdc_21p/191-gre_field_mapping_A21_plus600_S119_DIS3D/echo_7.38/' ;
    '~/Projects/Shimming/Static/Calibration/Data/acdc_21p/193-gre_field_mapping_B21_minus600_S121_DIS3D/echo_7.38/' ;
    '~/Projects/Shimming/Static/Calibration/Data/acdc_21p/195-gre_field_mapping_B21_minus600_S123_DIS3D/echo_7.38/' ;
    '~/Projects/Shimming/Static/Calibration/Data/acdc_21p/197-gre_field_mapping_B21_plus600_S125_DIS3D/echo_7.38/' ;
    '~/Projects/Shimming/Static/Calibration/Data/acdc_21p/199-gre_field_mapping_B21_plus600_S127_DIS3D/echo_7.38/' ;
    '~/Projects/Shimming/Static/Calibration/Data/acdc_21p/201-gre_field_mapping_A22_minus800_S129_DIS3D/echo_7.38/' ;
    '~/Projects/Shimming/Static/Calibration/Data/acdc_21p/203-gre_field_mapping_A22_minus800_S131_DIS3D/echo_7.38/' ;
    '~/Projects/Shimming/Static/Calibration/Data/acdc_21p/209-gre_field_mapping_A22_plus600_S137_DIS3D/echo_7.38/' ;
    '~/Projects/Shimming/Static/Calibration/Data/acdc_21p/211-gre_field_mapping_A22_plus600_S139_DIS3D/echo_7.38/' ;
    '~/Projects/Shimming/Static/Calibration/Data/acdc_21p/213-gre_field_mapping_B22_minus600_S141_DIS3D/echo_7.38/' ;
    '~/Projects/Shimming/Static/Calibration/Data/acdc_21p/215-gre_field_mapping_B22_minus600_S143_DIS3D/echo_7.38/' ;
    '~/Projects/Shimming/Static/Calibration/Data/acdc_21p/217-gre_field_mapping_B22_plus600_S145_DIS3D/echo_7.38/' ;
    '~/Projects/Shimming/Static/Calibration/Data/acdc_21p/219-gre_field_mapping_B22_plus600_S147_DIS3D/echo_7.38/' ; } ;

% 1st 2 directories correspond to the baseline shim 
Params.dataLoadDirectories{1,1,1,1} = tmp{1} ;
Params.dataLoadDirectories{1,2,1,1} = tmp{2} ;

nImgPerCurrent = 2 ; % = 1 mag image + 1 phase

disp( ['Preparing shim calibration...' ] )        

for iChannel = 1 : Params.nChannels
    disp(['Channel ' num2str(iChannel) ' of ' num2str(Params.nChannels) ] )        
    
    for iCurrent = 1 : Params.nCurrents 
        % mag
        Params.dataLoadDirectories{ 1, 1, iCurrent, iChannel + 1} = tmp{ nImgPerCurrent*(Params.nCurrents*iChannel + iCurrent) -3 } ;
        % phase
        Params.dataLoadDirectories{ 1, 2, iCurrent, iChannel + 1} = tmp{ nImgPerCurrent*(Params.nCurrents*iChannel + iCurrent) -2 } ;
       
        % for calibration of Siemens (e.g. Prisma) scanner shims only : 
        % load one of the images for each 'current' to get the shim values directly from the Siemens Hdr
        Img = MaRdI( Params.dataLoadDirectories{ 1, 1, iCurrent, iChannel +1 }  ) ; % mag
        [f0,g0,s0] = Img.adjvalidateshim( ) ;
        shimValues = ShimOpt_IUGM_Prisma_fit.converttomultipole( [g0 ; s0] ) ; % convert to the 'multipole units' of the 3D shim card (Siemens console GUI)
        Params.currents( iChannel, iCurrent ) = shimValues( iChannel ) ; % TODO : consistent approach to units, since these aren't in amps...
    end
end

Params.Filtering.isFiltering  = true ;
Mag                           = MaRdI( Params.dataLoadDirectories{1} ) ;
voxelSize                     = Mag.getvoxelsize() ;
Params.Filtering.filterRadius = voxelSize(3) ;

Params.reliabilityMask = (Mag.img/max(Mag.img(:))) > 0.1 ; % region of reliable SNR for unwrapping


Params.Extension.isExtending    = false ; % harmonic field extrapolation
Params.Extension.voxelSize      = voxelSize ;
Params.Extension.radius         = 8 ;
Params.Extension.expansionOrder = 2 ;

Params.unwrapper = 'AbdulRahman_2007' ;        

end
% =========================================================================

end
% =========================================================================
% =========================================================================
methods(Static)
% =========================================================================
function [ shimValues  ] = converttomultipole( shimValues )
%CONVERTTOMULTIPOLE
% 
% shimValues = CONVERTTOMULTIPOLE( shimValues )
%
% Shim values stored in MrProt (private Siemens DICOM.Hdr) are in units of 
% DAC counts for the gradient offsets and in units of mA for the 2nd order shims.
% CONVERTTOMULTIPOLE uses the information given by the Siemens commandline tool
%   AdjValidate -shim -info
% to convert a vector of shim settings in those units into the "multipole" values
% which are used in the Siemens GUI display (i.e. Shim3d)
%
%TODO
%   Refactor and move the method to ShimCom_IUGM_Prisma_fit() 

nChannels = numel( shimValues ) ;

if nChannels == 3 
    % input shimValues are gradient offsets [units : DAC counts]
    % output shimValues units : micro-T/m]
    
    shimValues(1) = 2300*shimValues(1)/14436 ;
    shimValues(2) = 2300*shimValues(2)/14265 ;
    shimValues(3) = 2300*shimValues(3)/14045 ;

elseif nChannels == 5
    % input shimValues are for the 2nd order shims [units : mA]
    % output shimValues units : micro-T/m^2]

    shimValues(1) = 4959.01*shimValues(1)/9998 ;
    shimValues(2) = 3551.29*shimValues(2)/9998 ;
    shimValues(3) = 3503.299*shimValues(3)/9998 ;
    shimValues(4) = 3551.29*shimValues(4)/9998 ;
    shimValues(5) = 3487.302*shimValues(5)/9998 ;

elseif nChannels == 8

    shimValues(1) = 2300*shimValues(1)/14436 ;
    shimValues(2) = 2300*shimValues(2)/14265 ;
    shimValues(3) = 2300*shimValues(3)/14045 ;

    shimValues(4) = 4959.01*shimValues(4)/9998 ;
    shimValues(5) = 3551.29*shimValues(5)/9998 ;
    shimValues(6) = 3503.299*shimValues(6)/9998 ;
    shimValues(7) = 3551.29*shimValues(7)/9998 ;
    shimValues(8) = 3487.302*shimValues(8)/9998 ;

end

end
% =========================================================================

end
% =========================================================================
% =========================================================================

end
