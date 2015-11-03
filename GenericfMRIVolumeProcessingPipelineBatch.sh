#!/bin/bash 


help () {
    echo
    echo "fMRIVolume example pipeline."
    echo "Example Usage:"
    echo "$0 --OutputFolder=/storage/workspace/elvis/HCP_MICCAI_FINAL --StudyFolder=/storage/data/HCP/S500-1 --Njobs=2"
    exit 0
}


get_batch_options() {
    # Function to parse command line arguments and options.
    local arguments=($@)

    unset command_line_specified_study_folder
    unset command_line_specified_output_folder
    unset command_line_specified_njobs

    local index=0
    local numArgs=${#arguments[@]}
    local argument

    while [ ${index} -lt ${numArgs} ]; do
        argument=${arguments[index]}

        case ${argument} in
            --Njobs=*)
                command_line_specified_njobs=${argument/*=/""}
                index=$(( index + 1 ))
		;;
            --StudyFolder=*)
                command_line_specified_study_folder=${argument/*=/""}
                index=$(( index + 1 ))
                ;;
            --OutputFolder=*)
                command_line_specified_output_folder=${argument/*=/""}
                index=$(( index + 1 ))
                ;;
	    --help)
		help
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


function do_subject {
    # function to process a single subject
    Subject=$1

    for task in $Tasklist ; do
	for UnwarpDir in x- x; do
	    if [ ${UnwarpDir} = "x" ]; then
		fMRIName=tfMRI_${task}_RL
	    else
		fMRIName=tfMRI_${task}_LR
	    fi
	    echo "  ${fMRIName}"
	    fMRITimeSeries="${StudyFolder}/${Subject}/unprocessed/3T/${fMRIName}/${Subject}_3T_${fMRIName}.nii.gz"
	    if [ ! -e ${fMRITimeSeries} ]; then
		echo "Missing due to missing file: ${fMRITimeSeries}"
		continue
	    fi
	    fMRISBRef="${StudyFolder}/${Subject}/unprocessed/3T/${fMRIName}/${Subject}_3T_${fMRIName}_SBRef.nii.gz"
	    if [ ! -e ${fMRISBRef} ]; then
		echo "Missing due to missing file: ${fMRISBref}"
		continue
	    fi
	    DwellTime="0.00058"
	    SpinEchoPhaseEncodeNegative="${StudyFolder}/${Subject}/unprocessed/3T/${fMRIName}/${Subject}_3T_SpinEchoFieldMap_LR.nii.gz"
	    if [ ! -e ${SpinEchoPhaseEncodeNegative} ]; then
		echo "Missing due to missing file: ${SpinEchoPhaseEncodeNegative}"
		continue
	    fi
	    SpinEchoPhaseEncodePositive="${StudyFolder}/${Subject}/unprocessed/3T/${fMRIName}/${Subject}_3T_SpinEchoFieldMap_RL.nii.gz"
	    if [ ! -e ${SpinEchoPhaseEncodepositive} ]; then
		echo "Missing due to missing file: ${SpinEchoPhaseEncodepositive}"
		continue
	    fi
	    PhaseInputName="NONE"
	    GEB0InputName="NONE"
	
	    DeltaTE="NONE"
	    FinalFMRIResolution="2"
	    GradientDistortionCoeffs="NONE"
	    TopUpConfig="${HCPPIPEDIR_Config}/b02b0.cnf"
	
	    cmd="${HCPPIPEDIR}/fMRIVolume/GenericfMRIVolumeProcessingPipeline.sh \
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
      --printcom=$PRINTCOM"
	    echo "Running "
	    echo ${cmd}
	    ${cmd}
    done
done
}


# Misc: sanitize input
get_batch_options $@
Njobs=1
Tasklist="MOTOR EMOTION WM RELATIONAL GAMBLING LANGUAGE SOCIAL" # Space delimited list of tasks
if [ -n "${command_line_specified_study_folder}" ]; then
    StudyFolder="${command_line_specified_study_folder}"
    if [ ! -d ${StudyFolder} ]; then
	echo "Error: ${StudyFolder} is not a folder!"
	exit 1
    fi
else
    echo "Error: --StudyFolder option is mandatory!"
    exit 1
fi
if [ -n "${command_line_specified_output_folder}" ]; then
    OutputFolder="${command_line_specified_output_folder}"
else
    echo "Error: --OutputFolder option is mandatory!"
    exit 1
fi
if [ -n "${command_line_specified_njobs}" ]; then
    Njobs="${command_line_specified_njobs}"
fi

# Set up pipeline environment variables and software
. SetUpHCPPipeline.sh

# Log the originating call
echo "$@"
PRINTCOM=""

# Export stuff
export StudyFolder=${StudyFolder}
export OutputFolder=${OutputFolder}
export Tasklist=${Tasklist}
export -f do_subject

# Process subjects in parallel
for Subject in `ls ${StudyFolder}`; do
    echo ${Subject}; done | xargs -n 1 -P ${Njobs} -i bash -c 'do_subject "$@"' _ {}


