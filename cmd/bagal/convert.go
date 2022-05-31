package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
)

func convertFile(indir, outdir string, file File) error {
	thumbPath := filepath.Join(outdir, file.Thumbnail)

	if _, err := os.Stat(thumbPath); err != nil {
		if file.Type == Image {
			ratelimit(thumbnailImageCommand(file.Source, thumbPath))
		} else if file.Type == Video {
			ratelimit(thumbnailVideoCommand(file.Source, thumbPath))
		}
	}

	targetPath := filepath.Join(outdir, file.Target)
	if _, err := os.Stat(targetPath); err != nil {
		if file.Type == Image {
			ratelimit(scaleImageCommand(file.Source, targetPath))
		} else if file.Type == Video {
			ratelimit(recodeVideoCommand(file.Source, targetPath))
		}
	}

	return nil
}

func scaleImageCommand(source, target string) *exec.Cmd {
	return exec.Command(
		"magick",
		source,
		"-auto-orient",
		"-strip",
		"-scale", fmt.Sprintf("%dx%d", options.ScaleMaxWidth, options.ScaleMaxHeight),
		target,
	)
}

func thumbnailImageCommand(source, target string) *exec.Cmd {
	return exec.Command(
		"magick",
		source,
		"-auto-orient",
		"-strip",
		"-thumbnail", fmt.Sprintf("%dx%d", options.ThumbMaxWidth, options.ThumbMaxHeight),
		target,
	)
}

func recodeVideoCommand(source, target string) *exec.Cmd {
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

func thumbnailVideoCommand(source, target string) *exec.Cmd {
	return exec.Command(
		"ffmpeg",
		"-hide_banner",
		"-loglevel", "panic",
		"-i", source,
		"-vframes", "1",
		"-vf", fmt.Sprintf("scale=%d:%d:force_original_aspect_ratio=increase", options.ThumbMaxWidth, options.ThumbMaxHeight),
		target,
		"-y",
	)
}
