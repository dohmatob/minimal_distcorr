#!/bin/bash 
set -e

# Requirements for this script
#  installed versions of: FSL (version 5.0.6), FreeSurfer (version 5.3.0-HCP) , gradunwarp (HCP version 1.0.2) 
#  environment: use SetUpHCPPipeline.sh  (or individually set FSLDIR, FREESURFER_HOME, HCPPIPEDIR, PATH - for gradient_unwarp.py)

########################################## PIPELINE OVERVIEW ########################################## 

# TODO

########################################## OUTPUT DIRECTORIES ########################################## 

# TODO

# --------------------------------------------------------------------------------
#  Load Function Libraries
# --------------------------------------------------------------------------------

source $HCPPIPEDIR/global/scripts/log.shlib  # Logging related functions
source $HCPPIPEDIR/global/scripts/opts.shlib # Command line option functions

################################################ SUPPORT FUNCTIONS ##################################################

# --------------------------------------------------------------------------------
#  Usage Description Function
# --------------------------------------------------------------------------------

show_usage() {
    echo "Usage information To Be Written"
    exit 1
}

# --------------------------------------------------------------------------------
#   Establish tool name for logging
# --------------------------------------------------------------------------------
log_SetToolName "GenericfMRIVolumeProcessingPipeline.sh"

################################################## OPTION PARSING #####################################################

opts_ShowVersionIfRequested $@

if opts_CheckForHelpRequest $@; then
    show_usage
fi

log_Msg "Parsing Command Line Options"

# parse arguments
Path=`opts_GetOpt1 "--path" $@`
Subject=`opts_GetOpt1 "--subject" $@`
NameOffMRI=`opts_GetOpt1 "--fmriname" $@`
fMRITimeSeries=`opts_GetOpt1 "--fmritcs" $@`
fMRIScout=`opts_GetOpt1 "--fmriscout" $@`
SpinEchoPhaseEncodeNegative=`opts_GetOpt1 "--SEPhaseNeg" $@`
SpinEchoPhaseEncodePositive=`opts_GetOpt1 "--SEPhasePos" $@`
MagnitudeInputName=`opts_GetOpt1 "--fmapmag" $@`  # Expects 4D volume with two 3D timepoints
PhaseInputName=`opts_GetOpt1 "--fmapphase" $@`  
GEB0InputName=`opts_GetOpt1 "--fmapgeneralelectric" $@`
DwellTime=`opts_GetOpt1 "--echospacing" $@`  
deltaTE=`opts_GetOpt1 "--echodiff" $@`  
UnwarpDir=`opts_GetOpt1 "--unwarpdir" $@`  

GradientDistortionCoeffs=`opts_GetOpt1 "--gdcoeffs" $@`  
TopupConfig=`opts_GetOpt1 "--topupconfig" $@`  # NONE if Topup is not being used

dof=`opts_GetOpt1 "--dof" $@`
dof=`opts_DefaultOpt $dof 6`

RUN=`opts_GetOpt1 "--printcom" $@`  # use ="echo" for just printing everything and not running the commands (default is to run)

# Setup PATHS
PipelineScripts=${HCPPIPEDIR_fMRIVol}
GlobalScripts=${HCPPIPEDIR_Global}

#Naming Conventions
MovementRegressor="Movement_Regressors" #No extension, .txt appended
MotionMatrixFolder="MotionMatrices"
MotionMatrixPrefix="MAT_"
FieldMapOutputName="FieldMap"
MagnitudeOutputName="Magnitude"
MagnitudeBrainOutputName="Magnitude_brain"
ScoutName="Scout"
OrigScoutName="${ScoutName}_orig"
OrigTCSName="${NameOffMRI}_orig"
OutputTransform="${NameOffMRI}_undistortion_warp"
RegOutput="Scout_undistorted"
JacobianOut="${OutputTransform}_jacobian"


########################################## DO WORK ########################################## 

fMRIFolder="$Path"/"$Subject"/"$NameOffMRI"
mkdir -p "$fMRIFolder"
cp "$fMRITimeSeries" "$fMRIFolder"/"$OrigTCSName".nii.gz

#Create fake "Scout" if it doesn't exist
if [ $fMRIScout = "NONE" ] ; then
  ${RUN} fslroi "$fMRIFolder"/"$OrigTCSName" "$fMRIFolder"/"$OrigScoutName" 0 1
else
  cp "$fMRIScout" "$fMRIFolder"/"$OrigScoutName".nii.gz
fi

#Gradient Distortion Correction of fMRI
log_Msg "Gradient Distortion Correction of fMRI"
if [ ! $GradientDistortionCoeffs = "NONE" ] ; then
    log_Msg "mkdir -p ${fMRIFolder}/GradientDistortionUnwarp"
    mkdir -p "$fMRIFolder"/GradientDistortionUnwarp
    ${RUN} "$GlobalScripts"/GradientDistortionUnwarp.sh \
	--workingdir="$fMRIFolder"/GradientDistortionUnwarp \
	--coeffs="$GradientDistortionCoeffs" \
	--in="$fMRIFolder"/"$OrigTCSName" \
	--out="$fMRIFolder"/"$NameOffMRI"_gdc \
	--owarp="$fMRIFolder"/"$NameOffMRI"_gdc_warp

    log_Msg "mkdir -p ${fMRIFolder}/${ScoutName}_GradientDistortionUnwarp"	
     mkdir -p "$fMRIFolder"/"$ScoutName"_GradientDistortionUnwarp
     ${RUN} "$GlobalScripts"/GradientDistortionUnwarp.sh \
	 --workingdir="$fMRIFolder"/"$ScoutName"_GradientDistortionUnwarp \
	 --coeffs="$GradientDistortionCoeffs" \
	 --in="$fMRIFolder"/"$OrigScoutName" \
	 --out="$fMRIFolder"/"$ScoutName"_gdc \
	 --owarp="$fMRIFolder"/"$ScoutName"_gdc_warp
else
    log_Msg "NOT PERFORMING GRADIENT DISTORTION CORRECTION"
    ${RUN} imcp "$fMRIFolder"/"$OrigTCSName" "$fMRIFolder"/"$NameOffMRI"_gdc
    ${RUN} fslroi "$fMRIFolder"/"$NameOffMRI"_gdc "$fMRIFolder"/"$NameOffMRI"_gdc_warp 0 3
    ${RUN} fslmaths "$fMRIFolder"/"$NameOffMRI"_gdc_warp -mul 0 "$fMRIFolder"/"$NameOffMRI"_gdc_warp
    ${RUN} imcp "$fMRIFolder"/"$OrigScoutName" "$fMRIFolder"/"$ScoutName"_gdc
fi

log_Msg "mkdir -p ${fMRIFolder}/MotionCorrection_FLIRTbased"
mkdir -p "$fMRIFolder"/MotionCorrection_FLIRTbased
${RUN} "$PipelineScripts"/MotionCorrection_FLIRTbased.sh \
    "$fMRIFolder"/MotionCorrection_FLIRTbased \
    "$fMRIFolder"/"$NameOffMRI"_gdc \
    "$fMRIFolder"/"$ScoutName"_gdc \
    "$fMRIFolder"/"$NameOffMRI"_mc \
    "$fMRIFolder"/"$MovementRegressor" \
    "$fMRIFolder"/"$MotionMatrixFolder" \
    "$MotionMatrixPrefix" 

# EPI Distortion Correction and EPI to T1w Registration
log_Msg "EPI Distortion Correction and EPI to T1w Registration"
log_Msg "mkdir -p ${fMRIFolder}/DistortionCorrectionAndEPIToT1wReg_FLIRTBBRAndFreeSurferBBRbased"
mkdir -p ${fMRIFolder}/DistortionCorrectionAndEPIToT1wReg_FLIRTBBRAndFreeSurferBBRbased

${RUN} ${PipelineScripts}/DistortionCorrectionAndEPIToT1wReg_FLIRTBBRAndFreeSurferBBRbased.sh \
    --workingdir=${fMRIFolder}/DistortionCorrectionAndEPIToT1wReg_FLIRTBBRAndFreeSurferBBRbased \
    --scoutin=${fMRIFolder}/${ScoutName}_gdc \
    --fmapmag=${MagnitudeInputName} \
    --fmapphase=${PhaseInputName} \
    --fmapgeneralelectric=${GEB0InputName} \
    --echodiff=${deltaTE} \
    --SEPhaseNeg=${SpinEchoPhaseEncodeNegative} \
    --SEPhasePos=${SpinEchoPhaseEncodePositive} \
    --echospacing=${DwellTime} \
    --unwarpdir=${UnwarpDir} \
    --owarp=${fMRIFolder}/${OutputTransform} \
    --oregim=${fMRIFolder}/${RegOutput} \
    --gdcoeffs=${GradientDistortionCoeffs} \
    --topupconfig=${TopupConfig} \
    --ojacobian=${fMRIFolder}/${JacobianOut} \
    --dof=${dof}

#One Step Resampling
log_Msg "One Step Resampling"
log_Msg "mkdir -p ${fMRIFolder}/OneStepResampling"
mkdir -p ${fMRIFolder}/OneStepResampling
${RUN} ${PipelineScripts}/OneStepResampling.sh \
    --workingdir=${fMRIFolder}/OneStepResampling \
    --infmri=${fMRIFolder}/${OrigTCSName}.nii.gz \
    --fmrifolder=${fMRIFolder} \
    --fmridcwarp=${fMRIFolder}/${OutputTransform} \
    --motionmatdir=${fMRIFolder}/${MotionMatrixFolder} \
    --motionmatprefix=${MotionMatrixPrefix} \
    --ofmri=${fMRIFolder}/${NameOffMRI}_undistorted \
    --gdfield=${fMRIFolder}/${NameOffMRI}_undistortion_warp \
    --scoutin=${fMRIFolder}/${OrigScoutName} \
    --scoutgdcin=${fMRIFolder}/${ScoutName}_gdc \
    --jacobianin=${fMRIFolder}/${JacobianOut} \
    
log_Msg "Completed"

