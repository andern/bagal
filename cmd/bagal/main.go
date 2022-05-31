// TODO:
// Follow symlinks!
// Run a given amount of imagemagicks simultaneously
package main

import (
	"flag"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
)

type Options struct {
	Indir           string
	Outdir          string
	ImageExtensions string
	VideoExtensions string
	ThumbMaxWidth   int
	ThumbMaxHeight  int
	ScaleMaxWidth   int
	ScaleMaxHeight  int
	ParallellOps    int
	Verbose         bool
}

type Directory struct {
	Name        string
	Thumbnail   string
	Images      int
	Videos      int
	Directories int
	SubImages   int
	SubVideos   int
}

type FileType int

const (
	Image FileType = iota
	Video
	Unknown
)

type File struct {
	Type      FileType
	Source    string
	Target    string
	Thumbnail string
}

var options Options
var sem chan int
var cleanup chan os.Signal
var finishUp bool

func init() {
	log.SetFlags(0)

	flag.StringVar(&options.Indir, "i", "", "input directory")
	flag.StringVar(&options.Outdir, "o", "", "output directory")
	flag.StringVar(&options.ImageExtensions, "image", "jpg,jpeg,gif,png,heic", "image file extensions")
	flag.StringVar(&options.VideoExtensions, "video", "mp4,avi,mov", "video file extensions")
	flag.IntVar(&options.ThumbMaxWidth, "x", 400, "max width of thumbnail")
	flag.IntVar(&options.ThumbMaxHeight, "y", 225, "max height of thumbnail")
	flag.IntVar(&options.ScaleMaxWidth, "X", 1920, "max width of scaled images")
	flag.IntVar(&options.ScaleMaxHeight, "Y", 1080, "max height of scaled images")
	flag.IntVar(&options.ParallellOps, "p", runtime.NumCPU(), "number of parallell operations")
	flag.BoolVar(&options.Verbose, "v", false, "verbose output")

	sem = make(chan int, options.ParallellOps)
	cleanup = make(chan os.Signal)
	signal.Notify(cleanup, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-cleanup
		fmt.Println("Interrupt received! Finishing ongoing tasks before terminating")
		finishUp = true
	}()
}

func main() {
	flag.Parse()

	if len(os.Args) <= 1 {
		flag.Usage()
		return
	}

	if options.Indir == "" {
		log.Fatalln("you must provide an indir")
	}

	if options.Outdir == "" {
		log.Fatalln("you must provide an indir")
	}

	if !options.Verbose {
		log.SetOutput(ioutil.Discard)
	}

	_, err := readDir(options.Indir)
	if err != nil {
		panic(err)
	}

	// Wait for all operations to finish
	for i := 0; i < cap(sem); i++ {
		sem <- 1
	}
}

func ratelimit(cmd *exec.Cmd) {
	sem <- 1
	cmd.SysProcAttr = &syscall.SysProcAttr{
		Setpgid: true,
	}
	go func() {
		output, err := cmd.CombinedOutput()
		if err != nil {
			str := string(output)
			if options.Verbose && str != "" {
				log.Println(str)
			}
			log.Println(err.Error())
		}
		if options.Verbose {
			log.Println(cmd.String())
		}
		<-sem
	}()
}

func getFile(path string) (File, error) {
	var res File
	res.Source = path

	name := filepath.Base(path)
	if strings.ToLower(filepath.Ext(name)) == ".heic" {
		name = name + ".jpg"
	}

	if isImage(name) {
		res.Type = Image
		res.Target = fmt.Sprintf("s_%s", name)
		res.Thumbnail = fmt.Sprintf("t_%s", name)
	} else if isVideo(name) {
		name = strings.TrimSuffix(name, filepath.Ext(name)) + ".mp4"
		res.Type = Video
		res.Target = fmt.Sprintf("%s", name)
		res.Thumbnail = fmt.Sprintf("%s.jpg", name)
	} else {
		res.Type = Unknown
	}

	return res, nil
}

func getDirItems(dirpath string) ([]os.DirEntry, []os.DirEntry, error) {
	entries, err := os.ReadDir(dirpath)
	if err != nil {
		return nil, nil, err
	}
	var dirs []os.DirEntry
	var files []os.DirEntry

	for _, entry := range entries {
		if entry.IsDir() {
			dirs = append(dirs, entry)
		} else {
			files = append(files, entry)
		}
	}

	return dirs, files, nil
}

// TODO: Consider making it "getDirectory" that only reads, then loop later.
func readDir(dirpath string) (Directory, error) {
	rel, err := filepath.Rel(options.Indir, dirpath)
	if err != nil {
		return Directory{}, err
	}

	outdir := filepath.Join(options.Outdir, rel)
	// Make sure output dir exists
	err = os.MkdirAll(outdir, 0755)
	if err != nil {
		return Directory{}, err
	}

	// TODO: Handle symlinks here
	var sb strings.Builder

	var dir Directory
	dir.Name = filepath.Base(dirpath)

	dirs, files, err := getDirItems(dirpath)
	if err != nil {
		return Directory{}, err
	}

	for _, dirEntry := range dirs {
		if finishUp {
			return dir, nil
		}

		subDir, err := readDir(filepath.Join(dirpath, dirEntry.Name()))
		dir.Directories = dir.Directories + 1
		dir.SubImages = dir.SubImages + subDir.Images + subDir.SubImages
		dir.SubVideos = dir.SubVideos + subDir.Videos + subDir.SubVideos
		if err != nil {
			return Directory{}, err
		}

		sb.WriteString(DirectoryHTML(subDir))
	}

	for _, fileEntry := range files {
		file, err := getFile(filepath.Join(dirpath, fileEntry.Name()))
		if err != nil {
			return dir, err
		}

		err = convertFile(dirpath, outdir, file)
		if err != nil {
			return dir, err
		}

		sb.WriteString(FileHTML(file))

		if file.Type == Image {
			if dir.Thumbnail == "" {
				dir.Thumbnail = filepath.Join(dir.Name, file.Thumbnail)
			}
			dir.Images = dir.Images + 1
		} else if file.Type == Video {
			dir.Videos = dir.Videos + 1
		}

		if finishUp {
			return dir, nil
		}
	}

	outfile := filepath.Join(outdir, "index.html")
	err = WriteGallery(outfile, sb.String())
	if err != nil {
		return dir, err
	}

	return dir, nil
}

func isImage(path string) bool {
	extensions := strings.Split(options.ImageExtensions, ",")
	for _, ext := range extensions {
		if strings.HasSuffix(strings.ToLower(path), ext) {
			return true
		}
	}
	return false
}

func isVideo(path string) bool {
	extensions := strings.Split(options.VideoExtensions, ",")
	for _, ext := range extensions {
		if strings.HasSuffix(strings.ToLower(path), ext) {
			return true
		}
	}
	return false
}
