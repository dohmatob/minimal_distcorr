#!/bin/bash 
set -e

# Requirements for this script
#  installed versions of: FSL (version 5.0.6) and FreeSurfer (version 5.3.0-HCP)
#  environment: FSLDIR, FREESURFER_HOME + others

# ---------------------------------------------------------------------
#  Constants for specification of Readout Distortion Correction Method
# ---------------------------------------------------------------------

FIELDMAP_METHOD_OPT="FIELDMAP"
SIEMENS_METHOD_OPT="SiemensFieldMap"
GENERAL_ELECTRIC_METHOD_OPT="GeneralElectricFieldMap"
SPIN_ECHO_METHOD_OPT="TOPUP"

################################################ SUPPORT FUNCTIONS ##################################################

# --------------------------------------------------------------------------------
#  Load Function Libraries
# --------------------------------------------------------------------------------

source $HCPPIPEDIR_Global/log.shlib # Logging related functions

Usage() {
  echo "`basename $0`: Script to register EPI to T1w, with distortion correction"
  echo " "
  echo "Usage: `basename $0` [--workingdir=<working dir>]"
  echo "             --scoutin=<input scout image (pre-sat EPI)>"
  echo "             --fmapmag=<input Siemens field map magnitude image>"
  echo "             --fmapphase=<input Siemens field map phase image>"
  echo "             --fmapgeneralelectric=<input General Electric field map image>"
  echo "             --echodiff=<difference of echo times for fieldmap, in milliseconds>"
  echo "             --SEPhaseNeg=<input spin echo negative phase encoding image>"
  echo "             --SEPhasePos=<input spin echo positive phase encoding image>"
  echo "             --echospacing=<effective echo spacing of fMRI image, in seconds>"
  echo "             --unwarpdir=<unwarping direction: x/y/z/-x/-y/-z>"
  echo "             --owarp=<output filename for warp of EPI to T1w>"
  echo "             --biasfield=<input bias field estimate image, in fMRI space>"
  echo "             --oregim=<output registered image (EPI to T1w)>"
  echo "             --freesurferfolder=<directory of FreeSurfer folder>"
  echo "             --freesurfersubjectid=<FreeSurfer Subject ID>"
  echo "             --gdcoeffs=<gradient non-linearity distortion coefficients (Siemens format)>"
  echo ""
  echo "             [--topupconfig=<topup config file>]"
  echo "             --ojacobian=<output filename for Jacobian image (in T1w space)>"
  echo "             --dof=<degrees of freedom for EPI-T1 FLIRT> (default 6)"
}

# function for parsing options
getopt1() {
    sopt="$1"
    shift 1
    for fn in $@ ; do
	if [ `echo $fn | grep -- "^${sopt}=" | wc -w` -gt 0 ] ; then
	    echo $fn | sed "s/^${sopt}=//"
	    return 0
	fi
    done
}

defaultopt() {
    echo $1
}

# --------------------------------------------------------------------------------
#  Establish tool name for logging
# --------------------------------------------------------------------------------

log_SetToolName "DistortionCorrectionAndEPIToT1wReg_FLIRTBBRAndFreeSurferBBRbased.sh"

################################################### OUTPUT FILES #####################################################

# Outputs (in $WD):
#  
#    FIELDMAP, SiemensFieldMap, and GeneralElectricFieldMap: 
#      Magnitude  Magnitude_brain  FieldMap
#
#    FIELDMAP and TOPUP sections: 
#      Jacobian2T1w
#      ${ScoutInputFile}_undistorted  
#      ${ScoutInputFile}_undistorted2T1w_init   
#      ${ScoutInputFile}_undistorted_warp
#
#    FreeSurfer section: 
#      fMRI2str.mat  fMRI2str
#      ${ScoutInputFile}_undistorted2T1w  
#
# Outputs (not in $WD):
#
#       ${RegOutput}  ${OutputTransform}  ${JacobianOut}  ${QAImage}

################################################## OPTION PARSING #####################################################


# Just give usage if no arguments specified
if [ $# -eq 0 ] ; then Usage; exit 0; fi
# check for correct options
if [ $# -lt 16 ] ; then Usage; exit 1; fi

# parse arguments
WD=`getopt1 "--workingdir" $@`
ScoutInputName=`getopt1 "--scoutin" $@`
SpinEchoPhaseEncodeNegative=`getopt1 "--SEPhaseNeg" $@`
SpinEchoPhaseEncodePositive=`getopt1 "--SEPhasePos" $@`
DwellTime=`getopt1 "--echospacing" $@`
MagnitudeInputName=`getopt1 "--fmapmag" $@`
PhaseInputName=`getopt1 "--fmapphase" $@`
GEB0InputName=`getopt1 "--fmapgeneralelectric" $@`
deltaTE=`getopt1 "--echodiff" $@`
UnwarpDir=`getopt1 "--unwarpdir" $@`
OutputTransform=`getopt1 "--owarp" $@`
RegOutput=`getopt1 "--oregim" $@`
GradientDistortionCoeffs=`getopt1 "--gdcoeffs" $@`
TopupConfig=`getopt1 "--topupconfig" $@`
JacobianOut=`getopt1 "--ojacobian" $@`
dof=`getopt1 "--dof" $@`

ScoutInputFile=`basename $ScoutInputName`

# default parameters
RegOutput=`remove_ext $RegOutput`
WD=`defaultopt $WD ${RegOutput}.wdir`
dof=`defaultopt $dof 6`
GlobalScripts=${HCPPIPEDIR_Global}
TopupConfig=`defaultopt $TopupConfig ${HCPPIPEDIR_Config}/b02b0.cnf`
UseJacobian=false

log_Msg "START"

mkdir -p $WD

# Record the input options in a log file
echo "$0 $@" >> $WD/log.txt
echo "PWD = `pwd`" >> $WD/log.txt
echo "date: `date`" >> $WD/log.txt
echo " " >> $WD/log.txt

if [ ! -e ${WD}/FieldMap ] ; then
  mkdir ${WD}/FieldMap
fi

########################################## DO WORK ########################################## 

# Use topup to distortion correct the scout scans
#    using a blip-reversed SE pair "fieldmap" sequence
${GlobalScripts}/TopupPreprocessingAll.sh \
    --workingdir=${WD}/FieldMap \
    --phaseone=${SpinEchoPhaseEncodeNegative} \
    --phasetwo=${SpinEchoPhaseEncodePositive} \
    --scoutin=${ScoutInputName} \
    --echospacing=${DwellTime} \
    --unwarpdir=${UnwarpDir} \
    --owarp=${WD}/WarpField \
    --ojacobian=${WD}/Jacobian \
    --gdcoeffs=${GradientDistortionCoeffs} \
    --topupconfig=${TopupConfig}

# create a spline interpolated image of scout (distortion corrected in same space)
log_Msg "create a spline interpolated image of scout (distortion corrected in same space)"
applywarp --rel --interp=spline -i ${ScoutInputName} -r ${ScoutInputName} -w ${WD}/WarpField.nii.gz -o ${WD}/${ScoutInputFile}_undistorted

# apply Jacobian correction to scout image (optional)
if [ $UseJacobian = true ] ; then
    log_Msg "apply Jacobian correction to scout image"
    fslmaths ${WD}/${ScoutInputFile}_undistorted -mul ${WD}/Jacobian.nii.gz ${WD}/${ScoutInputFile}_undistorted
fi

log_Msg "cp ${WD}/${ScoutInputFile}_undistorted.nii.gz ${RegOutput}.nii.gz"
cp ${WD}/${ScoutInputFile}_undistorted.nii.gz ${RegOutput}.nii.gz

OutputTransformDir=$(dirname ${OutputTransform})
mkdir -p ${OutputTransformDir}

log_Msg "cp ${WD}/WarpField.nii.gz ${OutputTransform}.nii.gz"
cp ${WD}/WarpField.nii.gz ${OutputTransform}.nii.gz

log_Msg "cp ${WD}/Jacobian.nii.gz ${JacobianOut}.nii.gz"
cp ${WD}/Jacobian.nii.gz ${JacobianOut}.nii.gz

# QA
fslview ${ScoutInputName} ${WD}/${ScoutInputFile}_undistorted&

log_Msg "END"
echo " END: `date`" >> $WD/log.txt
