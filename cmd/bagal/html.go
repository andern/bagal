package main

import (
	"bufio"
	_ "embed"
	"fmt"
	"os"
	"strconv"
	"strings"
)

//go:embed index.html
var indexHTML string

func WriteGallery(path, content string) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	w := bufio.NewWriter(f)

	str := strings.ReplaceAll(indexHTML, "THUMB_MAX_HEIGHT", strconv.Itoa(options.ThumbMaxHeight))
	str = strings.ReplaceAll(str, "THUMB_MAX_WIDTH", strconv.Itoa(options.ThumbMaxWidth))
	str = strings.ReplaceAll(str, "BAGAL_CONTENT_HERE", content)

	_, err = w.WriteString(str)
	if err != nil {
		return err
	}

	err = w.Flush()
	if err != nil {
		return err
	}
	return nil
}

func FileHTML(f File) string {
	if f.Type == Unknown {
		return ""
	}

	if f.Type == Image {
		return fmt.Sprintf(
			"<a href='%s'><img src='%s' loading='lazy'/></a>",
			f.Scale,
			f.Thumbnail,
		)
	}

	return fmt.Sprintf(
		"<video poster='%s' preload='none' controls><source src='%s'></video>",
		f.Thumbnail,
		f.Scale,
	)
}

func DirectoryHTML(dir Directory) string {
	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("<a class='folder' href='%s/index.html'>", dir.Name))
	if dir.Thumbnail == "" {
		sb.WriteString(fmt.Sprintf("<img src='%s/%s' />", dir.Name, dir.SubThumbnail))
	} else {
		sb.WriteString(fmt.Sprintf("<img src='%s' />", dir.Thumbnail))
	}

	/*
		var stats []string
		if dir.Images > 0 {
			sb.WriteString(fmt.Sprintf("<span class='tag'>%d + %d img</span>", dir.Images, dir.SubImages))
		}
		if dir.Videos > 0 {
			sb.WriteString(fmt.Sprintf("<span class='tag'>%d + %d vid</span>", dir.Videos, dir.SubVideos))
		}
		if dir.Directories > 0 {
			sb.WriteString(fmt.Sprintf("<span class='tag'>%d dir</span>", dir.Directories))
		}

		sb.WriteString(strings.Join(stats, " • "))
	*/
	sb.WriteString(fmt.Sprintf("<div>%s</div>", dir.Name))
	sb.WriteString("</a>")
	return sb.String()
}
