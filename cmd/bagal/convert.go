package main

import (
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
)

// Converts media files to web compatible media
type MediaWebConverter struct {
	convertToJpegExtensions map[string]bool

	thumbMaxWidth  int
	thumbMaxHeight int

	scaleMaxWidth  int
	scaleMaxHeight int

	semaphore chan int
}

func NewMediaWebConverter(options Options) MediaWebConverter {
	var res MediaWebConverter
	res.convertToJpegExtensions = extensionsToMap(options.Convert2JpegExtensions)
	res.thumbMaxWidth = options.ThumbMaxWidth
	res.thumbMaxHeight = options.ThumbMaxHeight
	res.scaleMaxWidth = options.ScaleMaxWidth
	res.scaleMaxHeight = options.ScaleMaxHeight
	res.semaphore = make(chan int, options.ParallellOps)
	return res
}

// TODO: This _SHOULD_ (I think) return path to scaled and thumbnail versions
// This function (or struct) should decide which files are converted to what
// names etc ??

// TODO: Consider functions CreateThumbnail and CreateScaled with
// source + outdir as input?
func (c MediaWebConverter) Convert(outdir string, f File) error {
	thumb := filepath.Join(outdir, f.Thumbnail)
	if _, err := os.Stat(thumb); err != nil {
		if f.Type == Image {
			c.ratelimit(c.thumbnailImageCommand(f.Source, thumb))
		} else if f.Type == Video {
			c.ratelimit(c.thumbnailVideoCommand(f.Source, thumb))
		}
	}

	scale := filepath.Join(outdir, f.Scale)
	if _, err := os.Stat(scale); err != nil {
		if f.Type == Image {
			c.ratelimit(c.scaleImageCommand(f.Source, scale))
		} else if f.Type == Video {
			c.ratelimit(c.recodeVideoCommand(f.Source, scale))
		}
	}
	return nil
}

func (c MediaWebConverter) WaitForRatelimitedOperations() {
	for i := 0; i < cap(c.semaphore); i++ {
		c.semaphore <- 1
	}
}

func extensionsToMap(extsCommaSeparated string) map[string]bool {
	res := map[string]bool{}
	exts := strings.Split(extsCommaSeparated, ",")
	for _, ext := range exts {
		if !strings.HasPrefix(ext, ".") {
			ext = "." + ext
		}
		res[ext] = true
	}
	return res
}

/*
func (c MediaWebConverter) convertImage(indir, outdir, file string) (string, string) {
	ext := filepath.Ext(file)
	name := filepath.Base(file)
	if _, ok := c.convertToJpegExtensions[ext]; ok {
		name = name + ".jpg"
	}
	scale := filepath.Join(outdir, fmt.Sprintf("s_%s", name))
	thumb := filepath.Join(outdir, fmt.Sprintf("t_%s", name))

	source := filepath.Join(indir, file)
	if _, err := os.Stat(thumb); err != nil {
		c.ratelimit(c.thumbnailImageCommand(source, thumb))
	}

	if _, err := os.Stat(scale); err != nil {
		c.ratelimit(c.scaleImageCommand(source, scale))
	}

	return scale, thumb
}

func (c MediaWebConverter) convertVideo(indir, outdir, filename string) (string, string) {
	scale := filepath.Join(outdir, fmt.Sprintf("s_%s.mp4", filename))
	thumb := filepath.Join(outdir, fmt.Sprintf("t_%s.jpg", filename))

	source := filepath.Join(indir, filename)
	if _, err := os.Stat(thumb); err != nil {
		c.ratelimit(c.thumbnailVideoCommand(source, thumb))
	}

	if _, err := os.Stat(scale); err != nil {
		c.ratelimit(c.recodeVideoCommand(source, scale))
	}

	return scale, thumb
}
*/

func (c MediaWebConverter) ratelimit(cmd *exec.Cmd) {
	c.semaphore <- 1
	cmd.SysProcAttr = &syscall.SysProcAttr{
		Setpgid: true,
	}
	go func() {
		output, err := cmd.CombinedOutput()
		if err != nil {
			str := string(output)
			if str != "" {
				log.Println(str)
			}
			log.Println(err.Error())
		}
		log.Println(cmd.String())
		<-c.semaphore
	}()
}

// TODO: Reconsider the above!

func (c MediaWebConverter) scaleImageCommand(source, target string) *exec.Cmd {
	return exec.Command(
		"magick",
		source,
		"-auto-orient",
		"-strip",
		"-scale", fmt.Sprintf("%dx%d", c.scaleMaxWidth, c.scaleMaxHeight),
		target,
	)
}

func (c MediaWebConverter) thumbnailImageCommand(source, target string) *exec.Cmd {
	return exec.Command(
		"magick",
		source,
		"-auto-orient",
		"-strip",
		"-thumbnail", fmt.Sprintf("%dx%d", c.thumbMaxWidth, c.thumbMaxHeight),
		target,
	)
}

func (c MediaWebConverter) recodeVideoCommand(source, target string) *exec.Cmd {
	return exec.Command(
		"ffmpeg",
		"-i", source,
		"-vcodec", "h264",
		"-acodec", "aac",
		"-preset", "veryfast",
		"-crf", "18",
		target,
		"-y",
	)
}

func (c MediaWebConverter) thumbnailVideoCommand(source, target string) *exec.Cmd {
	return exec.Command(
		"ffmpeg",
		"-hide_banner",
		"-loglevel", "panic",
		"-i", source,
		"-vframes", "1",
		"-vf", fmt.Sprintf("scale=%d:%d:force_original_aspect_ratio=increase", c.thumbMaxWidth, c.thumbMaxHeight),
		target,
		"-y",
	)
}
