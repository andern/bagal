#!/bin/bash
# bagal /ˈbeɪɡəl/ (bagal ain't a gallery) is a static gallery generator in bash.
# Copyright 2016, Andreas Halle

#INDIR=/home/USER/pics
#OUTDIR=/home/USER/gallery
#INDIR=/home/ah/nas/pics
#OUTDIR=/home/ah/gallery/priv
INDIR=/home/ah/delete/testdata
OUTDIR=/home/ah/gallery

THUMB_MAX_X=600
THUMB_MAX_Y=400

SCALE_MAX_X=1200
SCALE_MAX_Y=800

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
    add_dir_links "${out}" "${out}"

    cat index_bottom.html >> "${out}/index.html"
    cp main.css "${out}"/main.css
}

# add_images [in_dir] [out_dir]
# Add all images found in [in_dir] and put them in [out_dir]
#
# in_dir: directory containing images
# out_dir: directory where gallery for given directory should be.
function add_images {
    local in_dir="$1"
    local out_dir="$2"

    for pic in "${in_dir}"/*.jpg; do
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

    local dirname=`basename "${in_dir}"`
    local m_path="${out_dir}/${dirname}.jpg"

    local x=$((THUMB_MAX_X / 3 ))
    local y=$((THUMB_MAX_Y / 3 ))

    text="
<a class='image' href='${dirname}/index.html'>
    <img data-src='${dirname}.jpg' />
    <h2>${dirname//_/ }</h2>
</a>"
    write_node "${text}" "${out_dir}"

    rm "${m_path}"

    if [ -f "${m_path}" ]; then
        return
    fi
    printf '%s\n' "${m_path}"

    local files=("${in_dir}"/*.jpg)
    local numfiles=${#files[@]}
    if [ $numfiles -le 0 ]; then
        return
    fi
    if [ $numfiles -ge 9 ]; then
        numfiles=8
    fi

    local gridx=3
    if [ $numfiles -lt 3 ]; then
        gridx=$numfiles
    fi

    local gridy=$(((numfiles + 2) / 3))
    montage -quiet\
            -background none\
            -tile "${gridx}X${gridy}"\
            -geometry "$((THUMB_MAX_X / gridx))X$((THUMB_MAX_Y / gridy))+0+0"\
            "${files[@]:0:$((gridx * gridy))}"\
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
        printf '%s\n' "${s_path}"
    fi
    if [ ! -f "${t_path}" ]; then
        convert -quiet\
                -auto-orient\
                -thumbnail "${THUMB_MAX_X}x${THUMB_MAX_Y}"\
                --\
                "${image_path}"\
                "${t_path}"
        printf '%s\n' "${s_path}"
    fi

    text="<a href='s_${name}'><img data-src='t_${name}' /></a>"
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

    if [ ! -f "${new_path}.webm" ]; then
        ffmpeg -i "${video_path}"\
               -c:v libvpx\
               -crf 10\
               -b:v 1M\
               -c:a libvorbis\
               "${new_path}.webm"\
               -n < /dev/null
        ffmpeg -ss 4\
               -i "${video_path}"\
               -s "${THUMB_MAX_X}x${THUMB_MAX_Y}"\
               -frames:v 1 "${new_path}.jpg"\
               -n < /dev/null
    fi
    text="
<a href='${name}.webm'>
    <video controls>
        <source src='${name}.webm'>
    </video>
</a>"
    write_node "${text}" "${out_dir}"
}

function write_node {
    local text="$1"
    local out_dir="$2"

    printf '<div class="node-container">\n' >> "${out_dir}/index.html"
    printf '<div class="node">\n' >> "${out_dir}/index.html"
    printf '%s\n' "${text}" >> "${out_dir}/index.html"
    printf '</div>\n' >> "${out_dir}/index.html"
    printf '</div>\n' >> "${out_dir}/index.html"
}

if [ ! -e "${INDIR}" ]; then
    echo "Input dir does not exist: '${INDIR}'" >&2; exit 1
fi

parse_dir "${INDIR}"
