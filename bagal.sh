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
# Use ffprobe to get length of video to get thumbnail based on wadsworth const

shopt -s nullglob # Don't return itself on dir/* if dir is empty
shopt -s nocaseglob # Case insensitive globbing

HTML_TOP="
<!DOCTYPE html>
<html>
  <head>
    <meta charset='UTF-8'>
    <meta name='viewport' content='width=device-width, initial-scale=1'>
    <style>
      body {
        margin: 2px;
      }

      #container {
        /* For browsers without flex support */
        text-align: justify;
        text-align-last: justify;
        /**/

        display: flex;
        flex-wrap: wrap;
      }

      #container::after {
        content: '';
        flex-grow: 1e10;
      }

      #slider {
        position: fixed;
        top: 0;
        left: 0;
        width: 100%;
        height: 100%;
        background-color: #222222;
        display: none;
        overflow-x: auto;
        overflow-y: hidden;
        scroll-snap-type: x mandatory;
        -ms-overflow-style: none;  /* IE and Edge */
        scrollbar-width: none;  /* Firefox */
      }

      #slider::-webkit-scrollbar {
        display: none;
      }

      .is-hidden {
        display: none;
      }

      .slider-item {
        display: contents;
        display: flex;
        height: 100%;
        min-width: 100%;
        justify-content: center;
        align-items: center;
        scroll-snap-align: center;
      }

      .slider-item > img {
        max-height: 100%;
        max-width: 100%;
      }

      .noscroll { overflow: hidden; }

      #container > a {
        display: contents;
      }

      #container > a > img, #container > video {
        object-fit: cover;
        flex-grow: 1;
        margin: 2px;
        height: ${THUMB_MAX_Y}px;
      }

      #container > a > img:hover, #container > video:hover {
        box-shadow: 0 0 0 2px #444;
      }

      #container > video {
        width: ${THUMB_MAX_X}px;
      }

      #close {
        position: fixed;
        right: 32px;
        top: 32px;
        width: 32px;
        height: 32px;
        opacity: 0.6;
      }
      #close:hover {
        opacity: 1;
        cursor: pointer;
      }
      #close:before, #close:after {
        position: absolute;
        left: 15px;
        content: ' ';
        height: 33px;
        width: 2px;
        background-color: #FFF;
      }
      #close:before {
        transform: rotate(45deg);
      }
      #close:after {
        transform: rotate(-45deg);
      }
    </style>
    <title>Gallery</title>
  </head>
  <body>
    <div id='container'>
"

HTML_BOTTOM="
      <div id="slider">
        <div id="close" class="is-hidden"></div>
        <div class="slider-item">
          <img />
        </div>
      </div>
    </div>
    <script>
      let body = document.querySelector('body');
      let imgs = document.querySelectorAll('#container > a:not(.folder) > img');
      let slider = document.querySelector('#slider');
      let close = document.querySelector('#close');
      let index = 0;

      function getSliderItems() {
        return document.querySelectorAll('#slider > .slider-item');
      }

      function bufferImages(i) {
        const items = getSliderItems();
        const curr = items[i].firstElementChild;
        if (curr.src.length === 0)
          curr.src = imgs[i].parentNode.href;

        if (i > 0) {
          const prev = items[i - 1].firstElementChild;
          if (prev.src.length === 0)
            prev.src = imgs[i - 1].parentNode.href;
        }

        if (i < imgs.length - 1) {
          const next = items[i + 1].firstElementChild;
          if (next.src.length === 0)
            next.src = imgs[i + 1].parentNode.href;
        }
      }

      function addSliderItems() {
        const obs = new IntersectionObserver(entries => {
          let entry = entries.find(entry => entry.isIntersecting);
          if (entry == null) return;

          let idx = Array.from(getSliderItems()).findIndex(child => child === entry.target);
          bufferImages(idx);
          index = idx;
        }, { threshold: 0.20 });

        for (let i = 1; i < imgs.length; i++) {
          let child = getSliderItems()[0].cloneNode(true);
          obs.observe(child);
          slider.appendChild(child);
        }
      }

      function focusImage(idx) {
        if (getSliderItems().length === 1) {
          addSliderItems();
          console.log('adding slider items');
        }
        bufferImages(idx);
        index = idx

        new IntersectionObserver((entries, observer) => {
          slider.scrollLeft = getSliderItems()[idx].offsetLeft;
          observer.unobserve(entries[0].target);
        }, { threshold: 0.9 }).observe(slider);

        slider.style.display = 'flex';
        body.classList.toggle('noscroll');

      }

      function closePreview() {
        slider.style.display = 'none';
        body.classList.toggle('noscroll');
        imgs[index].scrollIntoView({block: 'center' });
      }

      function imageClickHandler(idx) {
        return (e) => {
          e.preventDefault();
          e.stopPropagation();
          focusImage(idx);
        };
      }

      slider.addEventListener('click', (e) => {
        close.classList.toggle('is-hidden');
      });

      close.addEventListener('click', (e) => {
        e.stopPropagation();
        close.classList.toggle('is-hidden');
        closePreview();
      });

      for (let i = 0; i < imgs.length; i++) {
        imgs[i].addEventListener('click', imageClickHandler(i));
      }

      document.addEventListener('keyup', (e) => {
        if (e.key === 'Escape') {
          closePreview();
          return;
        }

        if (e.key === 'ArrowRight') {
          e.stopPropagation();
          e.preventDefault();
          index = Math.min(index + 1, imgs.length - 1);
          getSliderItems()[index].scrollIntoView();
        }
        else if (e.key === 'ArrowLeft') {
          e.stopPropagation();
          e.preventDefault();
          index = Math.max(index - 1, 0);
          getSliderItems()[index].scrollIntoView();
        }
      });
    </script>
  </body>
</html>
"

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

    echo "$HTML_TOP" > "${out}/index.html"

    add_images "${path}" "${out}"
    add_videos "${path}" "${out}"
    add_dir_links "${path}" "${out}"

    echo "$HTML_BOTTOM" >> "${out}/index.html"
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
            "${m_path}"\
            2> /dev/null
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
                "${s_path}"\
                2> /dev/null
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
                "${t_path}"\
                2> /dev/null
        if [[ $VERBOSE ]]; then
            printf '%s\n' "${t_path}"
        fi
    fi

    text="<a href='s_${name}'>
        <img src='t_${name}' />
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
    text="<video
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
