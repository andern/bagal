#!/bin/bash
# bagal /ˈbeɪɡəl/ (bagal ain't a gallery) is a static gallery generator.
# Copyright 2016, 2020 Andreas Halle

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

# Defaults
IMAGE_FILES_REGEX=".*\.\(jpe?g\|gif\|png\)$"
MONTAGE_MAX_SQUARE=4
THUMB_MAX_X=400
THUMB_MAX_Y=225
SCALE_MAX_X=1920
SCALE_MAX_Y=1080

function version() {
    echo "bagal v0.1"
    exit 0
}

function usage() {
    echo "Usage: $0 [-i indir] [-o outdir] [-x,y,X,Y number] [-hvV]"
    echo ""
    echo "You must supply an input directory (-i) and an output directory (-o)"
    echo ""
    echo "  -i    input directory"
    echo "  -o    output directory"
    echo "  -x    max width of thumbnail"
    echo "  -x    max height of thumbnail"
    echo "  -X    max width of scaled images"
    echo "  -Y    max height of scaled images"
    echo ""
    echo "  -h    display this help"
    echo "  -v    enable verbose mode"
    echo "  -V    display version"
    exit 0
}

# Process CLI options
while getopts hi:o:vVx:y:X:Y: flag
do
    case "${flag}" in
        h) usage;;
        i) INDIR=${OPTARG};;
        o) OUTDIR=${OPTARG};;
        v) VERBOSE=true;;
        V) version;;
        x) THUMB_MAX_X=${OPTARG};;
        y) THUMB_MAX_Y=${OPTARG};;
        X) SCALE_MAX_X=${OPTARG};;
        Y) SCALE_MAX_Y=${OPTARG};;
        *) exit 1 ;;
    esac
done

if [ $OPTIND -eq 1 ]; then
    usage
fi

if [ -z "$INDIR" ]; then
    echo "$0: the input directory option is required -- i"
    exit 1
fi

if [ -z "$OUTDIR" ]; then
    echo "$0: the output directory option is required -- o"
    exit 1
fi

# TODO:
# Use identity to get image size of video preview to set correct height/width
# Use ffprobe to get length of video to get thumbnail based on wadsworth const

shopt -s nullglob # Don't return itself on dir/* if dir is empty
shopt -s nocaseglob # Case insensitive globbing

# parse_dir [path]
# Create a gallery of the given directory and its subdirs in OUTDIR keeping
# relative path consistent.
# 
# path: directory containing pictures/videos.
function parse_dir {
    local path="$1"

    local relpath="${path:${#INDIR}}"
    local out="${OUTDIR}/${relpath}"
    mkdir -p "${out}"

    for dir in "${path}"/*/; do parse_dir "${dir}"; done # Parse dirs preorder

    cp index_top.html "${out}/index.html"

    add_images "${path}" "${out}"
    add_videos "${path}" "${out}"
    add_dir_links "${path}" "${out}"

    cat index_bottom.html >> "${out}/index.html"
}

# add_images [in_dir] [out_dir]
# Add all images found in [in_dir] and put them in [out_dir]
#
# in_dir: directory containing images
# out_dir: directory where gallery for given directory should be.
function add_images {
    local in_dir="$1"
    local out_dir="$2"

    readarray -d '' pics < <(find "${in_dir}" -maxdepth 1 -type f -iregex "${IMAGE_FILES_REGEX}" -print0)
    for pic in "${pics[@]}"; do
        add_image "${pic}" "${out_dir}"
    done
}

# add_videos [in_dir] [out_dir]
# Add all videos found in [in_dir] and put them in [out_dir]
#
# in_dir: directory containing videos
# out_dir: directory where gallery for given directory should be.
function add_videos {
    local in_dir="$1"
    local out_dir="$2"

    for vid in "${in_dir}"/*.{mp4,avi}; do
        add_video "${vid}" "${out_dir}"
    done
}

function add_dir_links {
    local in_dir="$1"
    local out_dir="$2"

    for dir in "${in_dir}"/*/; do
        add_dir_link "${dir}" "${out_dir}"
    done
}

function add_dir_link {
    local in_dir="$1"
    local out_dir="$2"

    readarray -d '' files < <(find "${in_dir}" -type f -iregex "${IMAGE_FILES_REGEX}" -print0)
    local numfiles=${#files[@]}

    if [ $numfiles -le 0 ]; then
        return
    fi

    local dirname=`basename "${in_dir}"`
    local m_path="${out_dir}/${dirname}.jpg"

    text="<a class='folder' href='${dirname}/index.html'>
        <img src='${dirname}.jpg' alt='${dirname//_/ }'/>
      </a>"
    write_node "${text}" "${out_dir}"

    if [ -f "${m_path}" ]; then
        return
    fi

    # Create montage

    # Get max grid size based on number of available files
    local grid=${MONTAGE_MAX_SQUARE}
    for (( i=$((grid - 1)); i>0; i-- ))
    do
        if [ $numfiles -lt $((grid * grid)) ]; then
            grid=${i}
        fi
    done

    # Get a number of pictures evenly distributed among $files
    local take=$((grid * grid))
    declare -a mfiles
    for (( i=0; i<${take}; i++ ))
    do
        mfiles=("${mfiles[@]}" "${files[$((i * numfiles / take - 1))]}")
    done

    if [[ $VERBOSE ]]; then
        printf '%s\n' "${m_path}"
    fi

    montage -quiet\
            -background none\
            -tile "${grid}X${grid}"\
            -geometry "$((THUMB_MAX_X / grid))X$((THUMB_MAX_Y / grid))+0+0"\
            "${mfiles[@]}"\
            "${m_path}"
}

# add_image [image_path] [out_dir]
# Create a thumbnail and a scaled version the image found at [image_path] and
# put them in [out_dir].
#
# image_path: path to image
# out_dir:    directory for storing thumbnails and scales of image found at the
#             given path
function add_image {
    local image_path="$1"
    local out_dir="$2"

    local name=`basename "${image_path}"`
    local t_path="${out_dir}/t_${name}"
    local s_path="${out_dir}/s_${name}"

    if [ ! -f "${s_path}" ]; then
        convert -quiet\
                -auto-orient\
                -scale "${SCALE_MAX_X}x${SCALE_MAX_Y}"\
                --\
                "${image_path}"\
                "${s_path}"
        if [[ $VERBOSE ]]; then
            printf '%s\n' "${s_path}"
        fi
    fi
    if [ ! -f "${t_path}" ]; then
        convert -quiet\
                -auto-orient\
                -thumbnail "${THUMB_MAX_X}x${THUMB_MAX_Y}"\
                --\
                "${image_path}"\
                "${t_path}"
        if [[ $VERBOSE ]]; then
            printf '%s\n' "${t_path}"
        fi
    fi

    text="<a href='s_${name}'>
        <img src='t_${name}' style='height: ${THUMB_MAX_Y}px;'/>
      </a>"
    write_node "${text}" "${out_dir}"
}

# add_video [video_path] [out_dir]
# Create a thumbnail and a webm version the video found at [video_path] and
# put them in [out_dir].
#
# video_path: path to video
# out_dir:    directory for storing thumbnails and webm version video found at 
#             the given path
function add_video {
    local video_path="$1"
    local out_dir="$2"

    local name=`basename "${video_path}"`
    local new_path="${out_dir}/${name}"

    if [ ! -f "${new_path}" ]; then
        #ffmpeg -i "${video_path}"\
        #       -c:v libvpx\
        #       -crf 10\
        #       -b:v 1M\
        #       -c:a libvorbis\
        #       "${new_path}.webm"\
        #       -n < /dev/null
        cp "${video_path}" "${new_path}"
        if [[ $VERBOSE ]]; then
            printf '%s\n' "${new_path}.jpg"
        fi
        ffmpeg -hide_banner -loglevel panic\
               -ss 4\
               -i "${video_path}"\
               -vframes 1\
               -vf "scale=${THUMB_MAX_X}:${THUMB_MAX_Y}:force_original_aspect_ratio=increase,crop=${THUMB_MAX_X}:${THUMB_MAX_Y}"\
               "${new_path}.jpg"\
               -n < /dev/null
    fi
    read width height <<< $(identify -format '%w %h' "${new_path}.jpg")
    text="<video width='${width}' height='${height}'
poster='${name}.jpg' preload='none' controls>
          <source src='${name}'>
        </video>"
    write_node "${text}" "${out_dir}"
}

function write_node {
    local text="$1"
    local out_dir="$2"

    printf '      %s\n' "${text}" >> "${out_dir}/index.html"
}

if [ ! -e "${INDIR}" ]; then
    echo "Input dir does not exist: '${INDIR}'" >&2; exit 1
fi

parse_dir "${INDIR}"
