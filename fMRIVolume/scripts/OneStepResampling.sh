#!/bin/bash 
set -e

# Requirements for this script
#  installed versions of: FSL (version 5.0.6)
#  environment: FSLDIR

################################################ SUPPORT FUNCTIONS ##################################################

Usage() {
  echo "`basename $0`: Script to combine warps and affine transforms together and do a single resampling, with specified output resolution"
  echo " "
  echo "Usage: `basename $0` --workingdir=<working dir>"
  echo "             --infmri=<input fMRI 4D image>"
  echo "             --fmrifolder=<fMRI processing folder>"
  echo "             --fmridcwarp=<transformation for undistorted fMRI>"
  echo "             --struct2std=<input T1w to MNI warp>"
  echo "             --owarp=<output fMRI to MNI warp>"
  echo "             --oiwarp=<output MNI to fMRI warp>"
  echo "             --motionmatdir=<input motion correcton matrix directory>"
  echo "             --motionmatprefix=<input motion correcton matrix filename prefix>"
  echo "             --ofmri=<input fMRI 4D image>"
  echo "             --gdfield=<input warpfield for gradient non-linearity correction>"
  echo "             --scoutin=<input scout image (EPI pre-sat, before gradient non-linearity distortion correction)>"
  echo "             --scoutgdcin=<input scout gradient nonlinearity distortion corrected image (EPI pre-sat)>"
  echo "             --jacobianin=<input Jacobian image>"
  echo "             --ojacobian=<output transformed + distortion corrected Jacobian image>"
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

################################################### OUTPUT FILES #####################################################

# Outputs (in $WD): 
#         NB: all these images are in standard space 
#             but at the specified resolution (to match the fMRI - i.e. low-res)
#     ${T1wImageFile}.${FinalfMRIResolution}  
#     Scout_gdc_MNI_warp     : a warpfield from original (distorted) scout to low-res MNI
#
# Outputs (not in either of the above):
#     ${OutputfMRI}       

################################################## OPTION PARSING #####################################################

# Just give usage if no arguments specified
if [ $# -eq 0 ] ; then Usage; exit 0; fi
# check for correct options

# parse arguments
WD=`getopt1 "--workingdir" $@`  # "$1"
InputfMRI=`getopt1 "--infmri" $@`  # "$2"
fMRIFolder=`getopt1 "--fmrifolder" $@`
fMRIDCWarp=`getopt1 "--fmridcwarp" $@`  # "$6"
MotionMatrixFolder=`getopt1 "--motionmatdir" $@`  # "$9"
MotionMatrixPrefix=`getopt1 "--motionmatprefix" $@`  # "${10}"
OutputfMRI=`getopt1 "--ofmri" $@`  # "${11}"
GradientDistortionField=`getopt1 "--gdfield" $@`  # "${14}"
ScoutInput=`getopt1 "--scoutin" $@`  # "${15}"
ScoutInputgdc=`getopt1 "--scoutgdcin" $@`  # "${15}"
JacobianIn=`getopt1 "--jacobianin" $@`  # "${17}"

echo " "
echo " START: OneStepResampling"

mkdir -p $WD

# Record the input options in a log file
echo "$0 $@" >> $WD/log.txt
echo "PWD = `pwd`" >> $WD/log.txt
echo "date: `date`" >> $WD/log.txt
echo " " >> $WD/log.txt


########################################## DO WORK ########################################## 

#Save TR for later
TR_vol=`fslval ${InputfMRI} pixdim4 | cut -d " " -f 1`
NumFrames=`fslval ${InputfMRI} dim4`

###Add stuff for RMS###
if [ -e ${fMRIFolder}/Movement_RelativeRMS.txt ] ; then
  /bin/rm -v ${fMRIFolder}/Movement_RelativeRMS.txt
fi
if [ -e ${fMRIFolder}/Movement_AbsoluteRMS.txt ] ; then
  /bin/rm -v ${fMRIFolder}/Movement_AbsoluteRMS.txt
fi
if [ -e ${fMRIFolder}/Movement_RelativeRMS_mean.txt ] ; then
  /bin/rm -v ${fMRIFolder}/Movement_RelativeRMS_mean.txt
fi
if [ -e ${fMRIFolder}/Movement_AbsoluteRMS_mean.txt ] ; then
  /bin/rm -v ${fMRIFolder}/Movement_AbsoluteRMS_mean.txt
fi

mkdir -p ${WD}/prevols
mkdir -p ${WD}/postvols

# Apply combined transformations to fMRI (combines gradient non-linearity distortion, motion correction, and registration to T1w space, but keeping fMRI resolution)
fslsplit ${InputfMRI} ${WD}/prevols/vol -t
FrameMergeSTRING=""
FrameMergeSTRINGII=""
k=0
while [ $k -lt $NumFrames ] ; do
  vnum=`zeropad $k 4`
  prevmatrix="${MotionMatrixFolder}/${MotionMatrixPrefix}${vnum}"
  convertwarp --relout --rel --ref=${WD}/prevols/vol${vnum}.nii.gz --warp1=${GradientDistortionField} --postmat=${MotionMatrixFolder}/${MotionMatrixPrefix}${vnum} --out=${MotionMatrixFolder}/${MotionMatrixPrefix}${vnum}_gdc_warp.nii.gz
  fslmaths ${WD}/prevols/vol${vnum}.nii.gz -mul 0 -add 1 ${WD}/prevols/vol${vnum}_mask.nii.gz
  applywarp --rel --interp=spline --in=${WD}/prevols/vol${vnum}.nii.gz --warp=${MotionMatrixFolder}/${MotionMatrixPrefix}${vnum}_gdc_warp.nii.gz --ref=${ScoutInputgdc} --out=${WD}/postvols/vol${k}.nii.gz
  applywarp --rel --interp=nn --in=${WD}/prevols/vol${vnum}_mask.nii.gz --warp=${MotionMatrixFolder}/${MotionMatrixPrefix}${vnum}_gdc_warp.nii.gz --ref=${ScoutInputgdc} --out=${WD}/postvols/vol${k}_mask.nii.gz
  FrameMergeSTRING="${FrameMergeSTRING}${WD}/postvols/vol${k}.nii.gz " 
  FrameMergeSTRINGII="${FrameMergeSTRINGII}${WD}/postvols/vol${k}_mask.nii.gz " 
  k=`echo "$k + 1" | bc`
  echo ${WD}/postvols/vol${k}.nii.gz
done
# Merge together results and restore the TR (saved beforehand)
fslmerge -tr ${OutputfMRI} $FrameMergeSTRING $TR_vol
fslmerge -tr ${OutputfMRI}_mask $FrameMergeSTRINGII $TR_vol
fslmaths ${OutputfMRI}_mask -Tmin ${OutputfMRI}_mask
fslview ${OutputfMRI}&
echo " "
echo "END: OneStepResampling"
echo " END: `date`" >> $WD/log.txt
