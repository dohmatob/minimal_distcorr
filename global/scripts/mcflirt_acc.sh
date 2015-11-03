#!/bin/bash -e

#   Copyright (C) 2004-2011 University of Oxford
#
#   SHCOPYRIGHT

Usage() {
    echo ""
    echo "Usage: mcflirt_acc <4dinput> <4doutput> [ref_image]"
    echo ""
    exit
}

[ "$2" = "" ] && Usage

input=`remove_ext ${1}`
output=`remove_ext ${2}`
TR=`fslval $input pixdim4`

if [ `imtest $input` -eq 0 ];then
    echo "Input does not exist or is not in a supported format"
    exit
fi

rm -rf $output ; mkdir $output

if [ x$3 = x ] ; then
  fslroi $input ${output}_ref 10 10
  fslsplit ${output}_ref ${output}_tmp
  for i in `imglob ${output}_tmp????.*` ; do
      echo making reference: processing $i
      echo making reference: processing $i  >> ${output}.ecclog
      flirt -in $i -ref ${output}_tmp0000 -nosearch -dof 6 -o $i -paddingsize 1 >> ${output}.ecclog
  done
  fslmerge -t ${output}_ref ${output}_tmp????.*
  fslmaths ${output}_ref -Tmean ${output}_ref
  ref=${output}_ref
else
  ref=${3}
fi

pi=$(echo "scale=10; 4*a(1)" | bc -l)
outputFile=`basename ${output}`
fslsplit $input ${output}_tmp
fslmaths ${output}_tmp0000 -mul 0 -add 1 ${output}_allones
for i in `imglob ${output}_tmp????.*` ; do
    echo processing $i
    echo processing $i >> ${output}.ecclog
    ii=`basename $i | sed s/${outputFile}_tmp/MAT_/g`
    flirt -in $i -ref $ref -nosearch -dof 6 -o $i -paddingsize 1 -omat ${output}/${ii}.mat >> ${output}.ecclog
    maskname=`echo $i | sed 's/_tmp/_mask/'`
    flirt -in ${output}_allones -ref $ref -o $maskname -paddingsize 1 -setbackground 0 -init ${output}/${ii}.mat -applyxfm -noresampblur 
    mm=`avscale --allparams ${output}/${ii}.mat $ref | grep "Translations" | awk '{print $5 " " $6 " " $7}'`
    mmx=`echo $mm | cut -d " " -f 1`
    mmy=`echo $mm | cut -d " " -f 2`
    mmz=`echo $mm | cut -d " " -f 3`
    radians=`avscale --allparams ${output}/${ii}.mat $ref | grep "Rotation Angles" | awk '{print $6 " " $7 " " $8}'`
    radx=`echo $radians | cut -d " " -f 1`
    degx=`echo "$radx * (180 / $pi)" | bc -l`
    rady=`echo $radians | cut -d " " -f 2`
    degy=`echo "$rady * (180 / $pi)" | bc -l`
    radz=`echo $radians | cut -d " " -f 3`
    degz=`echo "$radz * (180 / $pi)" | bc -l`
    # The "%.6f" formatting specifier allows the numeric value to be as wide as it needs to be to accomodate the number
    # Then we mandate (include) a single space as a delimiter between values.
    echo `printf "%.6f" $mmx` `printf "%.6f" $mmy` `printf "%.6f" $mmz` `printf "%.6f" $degx` `printf "%.6f" $degy` `printf "%.6f" $degz` >> ${output}/mc.par
done

fslmerge -tr $output `imglob ${output}_tmp????.*` $TR
fslmerge -tr ${output}_mask `imglob ${output}_mask????.*` $TR
fslmaths ${output}_mask -Tmean -mul `$FSLDIR/bin/fslval ${output}_mask dim4` ${output}_mask

# rm ${output}_tmp????.* ${output}_mask????.* ${output}_allones.*  # [Elvis] uncomment




