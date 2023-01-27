(nixos-gc-fc-userscan)=

# Garbage collection & fc-userscan

*fc-userscan* protects installed packages from garbage collection that are not
referenced in the Nix store but might still be needed.

## Rationale: why fc-userscan?

You may want to install some library via the package manager (Nix), and
manually build code against the library, typically as part of an application
deployment in a service user home directory. On NixOS, though, the library is
not installed to a "well-known" location but to a directory in the Nix store,
with a name containing the hash of the package dependencies. Same goes for
creating a Python virtualenv using a Nix-installed Python and similar
environments which use an interpreter living in the Nix store.

With Nix, smallest changes somewhere down the dependency chain will change
hashes. That means that references to Nix store paths may become outdated
quickly. Nix automatically rebuilds Nix packages to reflect all dependency
changes.

Things installed via other means outside of the Nix store, though, have to be
updated manually. As long as the outdated Nix store path is available,
everything will work fine. But, as Nix normally wouldn't know about this
external reference to the store path, the Nix store garbage collector would remove
the old version if it's not referenced in the Nix store or by a explicitly
added [garbage collector root](https://nixos.org/manual/nix/stable/package-management/garbage-collector-roots.html).
This means that your application cannot find the dependency anymore and may
stop working properly.

## How does fc-userscan work?

To avoid that, [fc-userscan](https://github.com/flyingcircusio/userscan)
searches files for references to Nix store paths in home directories and
ensures that these packages are not garbage collected by creating *garbage
collector roots* for the files that reference these packages. Nix store paths
are then only cleaned up when the referring files had been deleted from all
home directories and a later *fc-userscan* run has removed the garbage
collector roots for them.

Also see {command}`man fc-userscan` for more information about the tool.

## When and how does garbage collection happen?

Our daily platform task *fc-collect-garbage.timer* runs *fc-userscan* first
, which searches all home directories of human and service users to protect
them in the following garbage collection step. Garbage collection is run
with limited disk IO speed to not affect running applications. Store paths
that are not used anymore may are not deleted immediately when they are
referenced by a system generation that was in use in the last three days.

You can also run {command}`sudo fc-collect-garbage` (available for *service*
and *sudo-srv* users) to trigger the process if you need to reclaim disk
space quickly. This command has no IO limit in contrast to the automatic job.

## How are files excluded from fc-userscan?

Keeping all packages that are referenced somewhere brings a new problem.
*fc-userscan* cannot know if a reference to a Nix path is really used or has
just been written to some file for some other reason, for example for
logging purposes or as part of a command in a shell history. These unneeded
Nix packages are then kept around as long as the log or history entry exists
which may be a long time.

*fc-userscan* can exclude certain paths from scanning to avoid that. There's a
default set of excludes in {file}`/etc/userscan/exclude` which is used
by *fc-collect-garbage* automatically.

If you need to add more exclusion rules you may add them as one regex per line
to {file}`~/.userscan-ignore`. The file uses a pattern format like
[gitignore](https://git-scm.com/docs/gitignore).

Note that paths to a sub-directory, like `.cache/test/somefile` don't match
anything unless prefixed with `**/` which means that the path is matched
everywhere, for example at `/home/test/sub/dir/.cache/test/somefile`.

There's no way to reference sub directories of the home directory directly at
the moment. We will fix that in the future.

Currently, the following paths are ignored:

~~~shell
# Directories to ignore (anywhere in the home directory)
**/.cache/nix/
**/.git/objects/
**/.gnupg/
**/.hg/store/
**/.nix-defexpr/
**/elasticsearch/data/
**/graylog/data/
**/influxdb/data/
**/journal/
**/lucene/
**/solr/data/
# Files in sub-directories to ignore (anywhere in the home directory)
**/.local/share/fish/fish_history
**/diagnostic.data/metrics.*
**/mongodb/*.wt
**/mysql/*/*.{MYD,MYI,frm,ibd}
**/mysql/ib*
**/postgresql/*/base
**/postgresql/*/pg_*
**/redis/*.rdb
# File extensions to ignore
*.JPG
*.bak
*.bmp
*.bz2
*.crt
*.css
*.deb
*.diff
*.doc
*.docx
*.eml
*.flac
*.gif
*.gz
*.htm
*.html
*.icc
*.jar
*.jpeg
*.jpg
*.json
*.kml
*.kmz
*.lock
*.log
*.log-????????
*.log.?
*.lzh
*.m4a
*.md
*.mid
*.mp3
*.mp4
*.ods
*.odt
*.ogg
*.otf
*.patch
*.pcl
*.pdf
*.pdf
*.pid
*.pki
*.png
*.ppt
*.pptx
*.psd
*.psd
*.rar
*.rpm
*.rss
*.sock
*.socket
*.spl
*.sql
*.svg
*.tgz
*.tif
*.tiff
*.ttf
*.vcl
*.war
*.wav
*.webm
*.xlf
*.xls
*.xlsx
*.xml
*.xz
*.zdsock
*.zopectlsock
*~
# Cache, history and data files to ignore
.bash_history
.viminfo
.z
.zsh_history
Data.fs
Data.fs.tmp
GeoLite2-City.mmdb
fc-userscan.cache
zeoclient_*.zec
~~~
