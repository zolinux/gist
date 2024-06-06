#!/bin/bash

# This is a console-based photo/video converter
# It can be used to mass reduce image/video file size with keeping useful metadata in the files. It uses `convert`, `exiftools` and `ffmpeg`

# SPDX-License-Identifier: GPL-3.0-or-later

# Example call:
# convert all images recursive from folders 2023 and 2024 to WEBP with a quality set to 45% and resized to 1920x1080 and the output files shall be stored in folder `output_dir` (with keeping the original folder structure):
#      ./massDownscaleImages.sh -o output_dir -i -q 45 -s 1920x1080 -t .webp 2023/* 2024/*

version=1.0

usage()
{
  echo "Usage: $0 [ -o | --outdir output_folder] [-i] [-m] [ -n | --dry-run ] [ -v | --version ] [ -q | --quality 85] [ -s | --size 1024x768 ] [ -e | --remove-exif ] [ -t | --imgtype .jpg ] source_folder(s)"
  exit 2
}

declare -a imgSize
parseImageSize()
{
    local _OLDIFS=$IFS
    IFS='x'
    imgSize=($1)
    IFS=$_OLDIFS
}

declare -a imgSizeStr
getImageSize()
{
    local _OLDIFS=$IFS
    IFS=$'\n'
    imgSizeStr=$($exiftool -ImageWidth -ImageHeight "$1" |sed -e '/:/{s/^.*:[[:space:]]*//}' |sed -e 'N;s/\n/x/')
    IFS=$_OLDIFS
}

convert()
{
    actDir=$(pwd -P)
    outDir=$OUTDIR${1#$actDir}
    od=$(readlink -m "$outDir")
    if [ "$od" == "$1" ]; then
        echo "Source files would be overwritten, exiting!"
        exit 7
    fi

    [[ $DRY -eq 0 && $(mkdir -p "$outDir" 2>/dev/null) ]] && echo "Could not create folder $outDir, exiting!" && exit 6

    if [ $VIDONLY -eq 0 ]; then
        images=$(find $1 -type f -iname "*.jp*" -or -iname "*.png" -or -iname "*.webp")

        for f in $images; do
            bn=$(basename $f)
            outFileName=${bn%.*}${IMGSUFFIX}
            fullPath=$outDir/$outFileName

            [ -f "$fullPath" ] && echo "File $outFileName already exists, skipping." && continue

            echo "Processing image: $f -> $fullPath"

            imgSizeStr=""
            getImageSize "$f"
            parseImageSize $imgSizeStr

            [ ${#imgSize[@]} -ne 2 ] && echo "Image size reading failed, skipping." && continue

            local width
            local height
            local runConvert=0
            local portrait=0
            local orientation=$($exiftool -Orientation# "$f" |sed -e 's/^.*:\s*//')

            [ -z "$orientation" ] && orientation=0
            [[ $orientation -ge 5 ]] && portrait=1

            # Resize the image
            if [ ${imgSize[0]} -ge ${imgSize[1]} ]; then
                width=$IMG_WIDTH
                height=$IMG_HEIGHT
            else
                portrait=1
                height=$IMG_WIDTH
                width=$IMG_HEIGHT
            fi 

            # check if need to convert
            [[ ${imgSize[0]} -gt $width || ${imgSize[1]} -gt $height ]] && runConvert=1
            imgSize=()

            if [ $runConvert -eq 0 ]; then
                echo "Skip downscale due to image size"
                [ $DRY -eq 0 ] && cp "$f" "$outDir"
                continue
            fi
            
            # Do the image conversion
            if [ $DRY -eq 0 ]; then
                res=$(sh -c "convert -sampling-factor 4:2:0 -resize ${width}x${height} -strip -quality $QUALITY -interlace Plane -colorspace RGB \"$f\" \"$fullPath\"")
                if [ $? -ne 0 ]; then
                    echo "Conversion of file $f failed: $res"
                fi

                if [ $REMOVE_EXIF -gt 0 ]; then
                    # write the orientation only
                    $exiftool -overwrite_original_in_place -Orientation#=$orientation "$fullPath"
                    continue
                fi

                # copy metadata to the new file
                res2=$($exiftool -overwrite_original_in_place -tagsFromFile "$f" -ExifImageWidth=${width} -ExifImageHeight=${height} "$fullPath")
                if [ $? -ne 0 ]; then
                    echo "Metadata copy failed: $res2, skipping."
                fi
            fi
        done
    fi

    if [ $IMGONLY -eq 0 ]; then
        videos=$(find $1 -type f -iname "*_archvd.mp4")

        for f in $videos; do
            bn=$(basename $f)
            outFileName=${bn%.*}.mp4
            fullPath=$outDir/$outFileName

            [ -f "$fullPath" ] && echo "File $outFileName already exists, skipping." && continue

            echo "Processing video: $f -> $fullPath"
            # Do the video conversion
            if [ $DRY -eq 0 ]; then
                res=$(sh -c "ffmpeg -hide_banner -v verbose  -i \"$f\"  -vsync cfr  -sws_flags lanczos+accurate_rnd+full_chroma_int+full_chroma_inp  -c:v h264_v4l2m2m  -preset veryslow  -qp -1  -g:v 25  -b:v 2000000 -minrate:v 500000 -maxrate:v 5000000 -bufsize:v 5000000 -movflags +faststart -c:a copy -y \"$fullPath\" 2>&1")
                if [ $? -ne 0 ]; then
                    echo "Conversion of file $f failed: $res"
                fi
            fi
        done
    fi
}

IFS=$'\n'

exiftool=$(which exiftool)
[ -z "$exiftool" ] && echo "Error: No \"exiftool\" found, exiting!" && exit 8
[ -z "$(which convert)" ] && echo "Error: No \"convert\" found, exiting!" && exit 9

echo "using exiftool from : $exiftool"

PARSED_ARGUMENTS=$(getopt -n $(basename $0) -o o:imvneq:s:t: --long outdir: --long dry-runquality: --long size: --long remove-exif --long imgtype: -- "$@")
VALID_ARGUMENTS=$?
if [ "$VALID_ARGUMENTS" != "0" ]; then
  usage
  exit 2
fi

if [ "$#" == "0" ]; then
  usage
  exit 3
fi

OUTDIR=.
IMGONLY=0
VIDONLY=0
DRY=0
QUALITY=85
REMOVE_EXIF=0
SIZE=1024x768
IMGSUFFIX=.jpg

eval set -- "$PARSED_ARGUMENTS"
while :
do
  case "$1" in
    -q | --quality)   QUALITY=$2   ; shift 2 ;;
    -s | --size)   SIZE=$2   ; shift 2 ;;
    -e | --remove-exif)   REMOVE_EXIF=1   ; shift 2 ;;
    -n | --dry-run)   DRY=1   ; shift 2 ;;
    -o | --outdir)   OUTDIR="$2"   ; shift 2 ;;
    -t | --imgtype) IMGSUFFIX="$2"; shift 2 ;;
    -i)   IMGONLY=1;  VIDONLY=0 ; shift ;;
    -m)   IMGONLY=0; VIDONLY=1  ; shift ;;
    -v)   echo "version: $version"; exit 0 ;;
    # -- means the end of the arguments; drop this, and break out of the while loop
    --) shift; break ;;
    # If invalid options were passed, then getopt should have reported an error,
    # which we checked as VALID_ARGUMENTS when getopt was called...
    *) echo "Unexpected option: $1 - this should not happen."
       usage ;;
  esac
done

parseImageSize $SIZE
[ ${#imgSize[@]} -ne 2 ] && echo "Error: Invalid image size, exiting!" && exit 10
IMG_WIDTH=${imgSize[0]}
IMG_HEIGHT=${imgSize[1]}

while :
do
    srcDir=$1
    [ -z $srcDir ] && break

    shift

    if [ ! -d "$srcDir" ]; then
        echo "Folder \"$srcDir\" not found, skipping folder!" >/dev/stderr
        continue
    fi

    sd=$(readlink -f $srcDir)
    echo "Start processing folder \"$sd\"..."
    convert "$sd"
done

echo "Conversion finished"
