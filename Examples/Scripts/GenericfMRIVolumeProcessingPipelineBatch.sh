#!/bin/bash 

get_batch_options() {
    local arguments=($@)

    unset command_line_specified_study_folder
    unset command_line_specified_output_folder
    unset command_line_specified_subj_list
    unset command_line_specified_run_local

    local index=0
    local numArgs=${#arguments[@]}
    local argument

    while [ ${index} -lt ${numArgs} ]; do
        argument=${arguments[index]}

        case ${argument} in
            --StudyFolder=*)
                command_line_specified_study_folder=${argument/*=/""}
                index=$(( index + 1 ))
                ;;
            --OutputFolder=*)
                command_line_specified_output_folder=${argument/*=/""}
                index=$(( index + 1 ))
                ;;
            --Subjlist=*)
                command_line_specified_subj_list=${argument/*=/""}
                index=$(( index + 1 ))
                ;;
            --runlocal)
                command_line_specified_run_local="TRUE"
                index=$(( index + 1 ))
                ;;
	    *)
		echo ""
		echo "ERROR: Unrecognized Option: ${argument}"
		echo ""
		exit 1
		;;
        esac
    done
}

get_batch_options $@

Subjlist="100307" #Space delimited list of subject IDs
EnvironmentScript=`dirname $0`/"SetUpHCPPipeline.sh" #Pipeline environment script

if [ -n "${command_line_specified_study_folder}" ]; then
    StudyFolder="${command_line_specified_study_folder}"
fi

if [ -n "${command_line_specified_output_folder}" ]; then
    OutputFolder="${command_line_specified_output_folder}"
fi

if [ -n "${command_line_specified_subj_list}" ]; then
    Subjlist="${command_line_specified_subj_list}"
fi

#Set up pipeline environment variables and software
. ${EnvironmentScript}

# Log the originating call
echo "$@"

QUEUE="-q hcp_priority.q"

PRINTCOM=""

# The PhaseEncodinglist contains phase encoding direction indicators for each corresponding
# task in the Tasklist.  Therefore, the Tasklist and the PhaseEncodinglist should have the
# same number of (space-delimited) elements.
Tasklist=""
PhaseEncodinglist=""

Tasklist="${Tasklist} tfMRI_EMOTION_RL"
PhaseEncodinglist="${PhaseEncodinglist} x"

Tasklist="${Tasklist} tfMRI_EMOTION_LR"
PhaseEncodinglist="${PhaseEncodinglist} x-"

Tasklist="${Tasklist} tfMRI_MOTOR_RL"
PhaseEncodinglist="${PhaseEncodinglist} x"

Tasklist="${Tasklist} tfMRI_MOTOR_LR"
PhaseEncodinglist="${PhaseEncodinglist} x-"

# Verify that Tasklist and PhaseEncodinglist have the same number of elements
TaskArray=($Tasklist)
PhaseEncodingArray=($PhaseEncodinglist)

nTaskArray=${#TaskArray[@]}
nPhaseEncodingArray=${#PhaseEncodingArray[@]}

if [ "${nTaskArray}" -ne "${nPhaseEncodingArray}" ] ; then
    echo "Tasklist and PhaseEncodinglist do not have the same number of elements."
    echo "Exiting without processing"
    exit 1
fi

# Start or launch pipeline processing for each subject
for Subject in $Subjlist ; do
  echo $Subject

  i=1
  for fMRIName in $Tasklist ; do
    echo "  ${fMRIName}"
    UnwarpDir=`echo $PhaseEncodinglist | cut -d " " -f $i`
    fMRITimeSeries="${StudyFolder}/${Subject}/unprocessed/3T/${fMRIName}/${Subject}_3T_${fMRIName}.nii.gz"
    [ ! -e ${fMRITimeSeries} ] && echo "Missing due to missing file: ${fMRITimeSeries}" && continue
    fMRISBRef="${StudyFolder}/${Subject}/unprocessed/3T/${fMRIName}/${Subject}_3T_${fMRIName}_SBRef.nii.gz"
    [ ! -e ${fMRISBRef} ] && continue
    DwellTime="0.00058"
    SpinEchoPhaseEncodeNegative="${StudyFolder}/${Subject}/unprocessed/3T/${fMRIName}/${Subject}_3T_SpinEchoFieldMap_LR.nii.gz"
    [ ! -e ${SpinEchoPhaseEncodeNegative} ] && echo "Missing due to missing file: ${SpinEchoPhaseEncodeNegative}" && continue
    SpinEchoPhaseEncodePositive="${StudyFolder}/${Subject}/unprocessed/3T/${fMRIName}/${Subject}_3T_SpinEchoFieldMap_RL.nii.gz"
  [ ! -e ${SpinEchoPhaseEncodepositive} ] && echo "Missing due to missing file: ${SpinEchoPhaseEncodepositive}" && continue
    PhaseInputName="NONE"
    GEB0InputName="NONE"

    DeltaTE="NONE"
    FinalFMRIResolution="2"
    GradientDistortionCoeffs="NONE"
    TopUpConfig="${HCPPIPEDIR_Config}/b02b0.cnf"

    if [ -n "${command_line_specified_run_local}" ] ; then
        echo "About to run ${HCPPIPEDIR}/fMRIVolume/GenericfMRIVolumeProcessingPipeline.sh"
        queuing_command=""
    else
        echo "About to use fsl_sub to queue or run ${HCPPIPEDIR}/fMRIVolume/GenericfMRIVolumeProcessingPipeline.sh"
        queuing_command="${FSLDIR}/bin/fsl_sub ${QUEUE}"
    fi

    ${queuing_command} ${HCPPIPEDIR}/fMRIVolume/GenericfMRIVolumeProcessingPipeline.sh \
      --path=$OutputFolder \
      --subject=$Subject \
      --fmriname=$fMRIName \
      --fmritcs=$fMRITimeSeries \
      --fmriscout=$fMRISBRef \
      --SEPhaseNeg=$SpinEchoPhaseEncodeNegative \
      --SEPhasePos=$SpinEchoPhaseEncodePositive \
      --fmapmag=$MagnitudeInputName \
      --fmapphase=$PhaseInputName \
      --fmapgeneralelectric=$GEB0InputName \
      --echospacing=$DwellTime \
      --echodiff=$DeltaTE \
      --unwarpdir=$UnwarpDir \
      --fmrires=$FinalFMRIResolution \
      --gdcoeffs=$GradientDistortionCoeffs \
      --topupconfig=$TopUpConfig \
      --printcom=$PRINTCOM

  # The following lines are used for interactive debugging to set the positional parameters: $1 $2 $3 ...
  echo "set -- --path=$OutputFolder \
      --subject=$Subject \
      --fmriname=$fMRIName \
      --fmritcs=$fMRITimeSeries \
      --fmriscout=$fMRISBRef \
      --SEPhaseNeg=$SpinEchoPhaseEncodeNegative \
      --SEPhasePos=$SpinEchoPhaseEncodePositive \
      --fmapmag=$MagnitudeInputName \
      --fmapphase=$PhaseInputName \
      --fmapgeneralelectric=$GEB0InputName \
      --echospacing=$DwellTime \
      --echodiff=$DeltaTE \
      --unwarpdir=$UnwarpDir \
      --fmrires=$FinalFMRIResolution \
      --dcmethod=$DistortionCorrection \
      --gdcoeffs=$GradientDistortionCoeffs \
      --topupconfig=$TopUpConfig \
      --printcom=$PRINTCOM"

  echo ". ${EnvironmentScript}"
	
    i=$(($i+1))
  done
done


